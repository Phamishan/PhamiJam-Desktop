import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/edit_song_dialog.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:provider/provider.dart';

enum _LikedSort {
  custom,
  dateAddedNewest,
  dateAddedOldest,
  durationShort,
  durationLong,
}

extension on _LikedSort {
  String get label {
    switch (this) {
      case _LikedSort.custom:
        return 'Default order';
      case _LikedSort.dateAddedNewest:
        return 'Recently added';
      case _LikedSort.dateAddedOldest:
        return 'Oldest added';
      case _LikedSort.durationShort:
        return 'Duration (shortest first)';
      case _LikedSort.durationLong:
        return 'Duration (longest first)';
    }
  }
}

class LikedPage extends StatefulWidget {
  final void Function(String artistId, String artistName)? onOpenArtist;

  const LikedPage({super.key, this.onOpenArtist});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  String? _currentlyLoadingVideoId;
  late final PlaybackModel _playback;
  bool _selectionMode = false;
  final Set<String> _selectedVideoIds = {};
  _LikedSort _sort = _LikedSort.custom;

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    final liked = context.read<LikedSongsProvider>();
    if (!liked.hasLoadedOnce && !liked.isLoading) {
      liked.refresh();
    }
  }

  DateTime? _parseAddedAt(Object? value) {
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  int _compareAddedAt(
    Map<String, dynamic> a,
    Map<String, dynamic> b, {
    required bool newestFirst,
  }) {
    final da = _parseAddedAt(a['addedAt']);
    final db = _parseAddedAt(b['addedAt']);
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return newestFirst ? db.compareTo(da) : da.compareTo(db);
  }

  List<Map<String, dynamic>> _applySort(List<Map<String, dynamic>> songs) {
    if (_sort == _LikedSort.custom) return songs;
    final sorted = List<Map<String, dynamic>>.from(songs);
    switch (_sort) {
      case _LikedSort.custom:
        break;
      case _LikedSort.dateAddedNewest:
        sorted.sort((a, b) => _compareAddedAt(a, b, newestFirst: true));
      case _LikedSort.dateAddedOldest:
        sorted.sort((a, b) => _compareAddedAt(a, b, newestFirst: false));
      case _LikedSort.durationShort:
        sorted.sort(
          (a, b) => ((a['durationSeconds'] as int?) ?? 0).compareTo(
            (b['durationSeconds'] as int?) ?? 0,
          ),
        );
      case _LikedSort.durationLong:
        sorted.sort(
          (a, b) => ((b['durationSeconds'] as int?) ?? 0).compareTo(
            (a['durationSeconds'] as int?) ?? 0,
          ),
        );
    }
    return sorted;
  }

  void _enterSelectionMode(String videoId) {
    if (videoId.isEmpty) return;
    setState(() {
      _selectionMode = true;
      _selectedVideoIds
        ..clear()
        ..add(videoId);
    });
  }

  void _toggleSongSelection(String videoId) {
    if (videoId.isEmpty) return;
    setState(() {
      if (!_selectedVideoIds.remove(videoId)) {
        _selectedVideoIds.add(videoId);
      }
      if (_selectedVideoIds.isEmpty) _selectionMode = false;
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedVideoIds.clear();
    });
  }

  Future<void> _addSelectedToPlaylist(List<Map<String, dynamic>> songs) async {
    final selectedSongs = songs
        .where(
          (s) => _selectedVideoIds.contains((s['videoId'] as String?) ?? ''),
        )
        .toList();
    if (selectedSongs.isEmpty) return;
    await showAddSongsToPlaylistDialog(context, songs: selectedSongs);
    if (!mounted) return;
    _exitSelectionMode();
  }

  String _formatDuration(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (error) {
      debugPrint('Failed to download image from $imageUrl: $error');
    }
    return null;
  }

  void _registerQueueHandlers(List<Map<String, dynamic>> songs) {
    _playback.setQueueHandlers(
      playAtSourceIndex: (sourceIndex) async {
        if (sourceIndex < 0 || sourceIndex >= songs.length) return;

        final song = songs[sourceIndex];
        final videoId = (song['videoId'] as String?) ?? '';
        if (videoId.isEmpty) return;

        await _startPlayback(song, videoId);
        _playback.markCurrentSourceIndex(sourceIndex);
      },
      prefetchQueueItem: (item) async {
        if (item is! Map<String, dynamic>) return;
        final videoId = (item['videoId'] as String?) ?? '';
        if (videoId.isEmpty || videoId.startsWith(driveTrackIdPrefix)) return;
        await _playback.prefetchYouTubeVideoById(videoId);
      },
    );
  }

  Future<void> _startPlayback(Map<String, dynamic> song, String videoId) async {
    final title = (song['title'] as String?) ?? 'Unknown song';
    final artist = (song['artist'] as String?) ?? 'Unknown artist';
    final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
    final effectiveDuration = durationSeconds > 0
        ? Duration(seconds: durationSeconds)
        : Duration.zero;

    if (videoId.startsWith(driveTrackIdPrefix)) {
      final fileId = videoId.substring(driveTrackIdPrefix.length);
      await _playback.switchToLocalEngine();
      _playback.setDuration(Duration.zero);
      final headers = await GoogleDriveService.streamHeaders(fileId);
      await player.setUrl(
        GoogleDriveService.streamUri(fileId).toString(),
        headers: headers,
      );
      await player.seek(Duration.zero);
      await player.play();

      _playback.setArtist(artist);
      _playback.setArtistId(null);
      _playback.setSongName(title);
      _playback.setCurrentSongPath(videoId);
      _playback.setCoverImageBytes(null);
      _playback.setDuration(effectiveDuration);
      _playback.setIsPlaying(true);
      _playback.setIsMuted(false);
      return;
    }

    final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
    final coverBytes = await _downloadImageBytes(thumbnailUrl);

    _playback.setSongName(title);
    _playback.setArtist(artist);
    _playback.setArtistId(song['artistId'] as String?);
    _playback.setCurrentSongPath('yt:$videoId');
    _playback.setCoverImageBytes(coverBytes);
    _playback.setDuration(effectiveDuration);

    await _playback.playYouTubeVideoById(videoId);
    await _playback.applyVolume(_playback.currentSliderValue);
  }

  Future<void> _playSongAtIndex(
    int index,
    List<Map<String, dynamic>> songs,
    Map<String, dynamic> song,
  ) async {
    if (_currentlyLoadingVideoId != null) return;

    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) {
      if (!mounted) return;
      AppFlushbar.error(context, 'This song has no playable video id.');
      return;
    }

    setState(() => _currentlyLoadingVideoId = videoId);

    try {
      await _startPlayback(song, videoId);
      _playback.setPlaylistQueue(songs, startIndex: index);
      _registerQueueHandlers(List<Map<String, dynamic>>.from(songs));
    } catch (error) {
      debugPrint('Playback failed for $videoId: $error');
      if (!mounted) return;
      AppFlushbar.error(context, 'Failed to play audio: $error');
    } finally {
      if (mounted) setState(() => _currentlyLoadingVideoId = null);
    }
  }

  void _addToQueue(Map<String, dynamic> song) {
    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) {
      if (!mounted) return;
      AppFlushbar.error(context, 'This song cannot be queued.');
      return;
    }

    _playback.addToQueue(Map<String, dynamic>.from(song));
    if (!mounted) return;
    final title = (song['title'] as String?) ?? 'Song';
    AppFlushbar.info(context, '"$title" will play next.');
  }

  void _appendToQueue(Map<String, dynamic> song) {
    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) {
      if (!mounted) return;
      AppFlushbar.error(context, 'This song cannot be queued.');
      return;
    }

    _playback.appendToQueue(Map<String, dynamic>.from(song));
    if (!mounted) return;
    final title = (song['title'] as String?) ?? 'Song';
    AppFlushbar.info(context, '"$title" added to queue.');
  }

  Widget _buildContent(BuildContext context, LikedSongsProvider liked) {
    final colorScheme = Theme.of(context).colorScheme;

    if (liked.isLoading && liked.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (liked.songs.isEmpty) {
      return Center(
        child: Text(
          'Your liked songs will appear here.',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18),
        ),
      );
    }

    final songs = liked.songs;
    final displaySongs = _applySort(songs);
    final downloads = context.watch<DownloadsProvider>();

    return ListView.separated(
      itemCount: displaySongs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, displayIndex) {
        final song = displaySongs[displayIndex];
        final videoIdForIndex = (song['videoId'] as String?) ?? '';
        final index = videoIdForIndex.isEmpty
            ? displayIndex
            : songs.indexWhere(
                (s) => (s['videoId'] as String?) == videoIdForIndex,
              );
        final title = (song['title'] as String?) ?? 'Unknown song';
        final artist = (song['artist'] as String?) ?? 'Unknown artist';
        final artistId = (song['artistId'] as String?) ?? '';
        final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
        final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
        final songDurationLabel = _formatDuration(durationSeconds);
        final videoId = (song['videoId'] as String?) ?? '';
        final isDriveSong = videoId.startsWith(driveTrackIdPrefix);
        final isLoadingThisSong =
            videoId.isNotEmpty && _currentlyLoadingVideoId == videoId;
        final isDownloaded = downloads.isDownloaded(videoId);
        final isDownloadingThisSong = downloads.isDownloading(videoId);

        return Builder(
          builder: (context) {
            final isCurrentSong = context.select<PlaybackModel, bool>(
              (playback) =>
                  playback.currentSongPath ==
                  (isDriveSong ? videoId : 'yt:$videoId'),
            );

            return ContextMenuRegion<String>(
              contextMenu: ContextMenu(
                borderRadius: BorderRadius.circular(12),
                entries: [
                  if (!_selectionMode)
                    MenuItem<String>(
                      value: 'select',
                      icon: const Icon(Icons.check_box_outlined),
                      label: const Text('Select'),
                    ),
                  MenuItem<String>(
                    value: 'play_next',
                    icon: const Icon(Icons.playlist_play_rounded),
                    label: const Text('Add to play next'),
                  ),
                  MenuItem<String>(
                    value: 'add_to_queue',
                    icon: const Icon(Icons.queue_music_rounded),
                    label: const Text('Add to queue'),
                  ),
                  if (!isDriveSong) ...[
                    MenuItem<String>(
                      value: 'add_to_playlist',
                      icon: const Icon(Icons.playlist_add_rounded),
                      label: const Text('Add to playlist'),
                    ),
                    MenuItem<String>(
                      value: isDownloaded ? 'remove_download' : 'download',
                      icon: Icon(
                        isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                      ),
                      label: Text(
                        isDownloaded ? 'Remove download' : 'Download',
                      ),
                    ),
                    MenuItem<String>(
                      value: 'edit_trim',
                      icon: const Icon(Icons.content_cut_rounded),
                      label: const Text('Edit song'),
                    ),
                  ],
                ],
              ),
              onItemSelected: (value) {
                if (value == 'select') {
                  _enterSelectionMode(videoId);
                } else if (value == 'play_next') {
                  _addToQueue(song);
                } else if (value == 'add_to_queue') {
                  _appendToQueue(song);
                } else if (value == 'add_to_playlist') {
                  if (_selectionMode && _selectedVideoIds.isNotEmpty) {
                    _addSelectedToPlaylist(songs);
                    return;
                  }
                  if (videoId.isEmpty) {
                    AppFlushbar.error(
                      context,
                      'This song cannot be added to a playlist.',
                    );
                    return;
                  }
                  showAddToPlaylistDialog(
                    context,
                    videoId: videoId,
                    songTitle: title,
                  );
                } else if (value == 'download') {
                  if (videoId.isEmpty) return;
                  downloads.download(
                    videoId: videoId,
                    songName: title,
                    artistName: artist,
                    artistId: artistId,
                    durationSeconds: durationSeconds,
                  );
                } else if (value == 'remove_download') {
                  downloads.remove(videoId);
                } else if (value == 'edit_trim') {
                  if (videoId.isEmpty) {
                    AppFlushbar.error(context, 'This song is unavailable.');
                    return;
                  }
                  showEditSongDialog(
                    context,
                    videoId: videoId,
                    title: title,
                    artist: artist,
                    thumbnailUrl: thumbnailUrl,
                    durationSeconds: durationSeconds,
                  );
                }
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isCurrentSong
                      ? colorScheme.surfaceContainerHigh
                      : colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: ListTile(
                    leading: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_selectionMode) ...[
                          Icon(
                            _selectedVideoIds.contains(videoId)
                                ? Icons.check_circle_rounded
                                : Icons.circle_outlined,
                            color: _selectedVideoIds.contains(videoId)
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],
                        thumbnailUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  thumbnailUrl,
                                  width: 56,
                                  height: 56,
                                  cacheWidth: 112,
                                  cacheHeight: 112,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Icon(
                                        Icons.music_note_rounded,
                                        color: colorScheme.onSurface,
                                      ),
                                ),
                              )
                            : Icon(
                                Icons.music_note_rounded,
                                color: colorScheme.onSurface,
                              ),
                      ],
                    ),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: colorScheme.onSurface),
                    ),
                    subtitle:
                        (artistId.isNotEmpty && widget.onOpenArtist != null)
                        ? MouseRegion(
                            cursor: SystemMouseCursors.click,
                            child: RichText(
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              text: TextSpan(
                                text: artist,
                                style: DefaultTextStyle.of(context).style.merge(
                                  TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                recognizer: TapGestureRecognizer()
                                  ..onTap = () =>
                                      widget.onOpenArtist!(artistId, artist),
                              ),
                            ),
                          )
                        : Text(
                            artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: () => liked.toggleLike(song),
                          icon: Icon(
                            Icons.favorite_rounded,
                            color: colorScheme.onSurface,
                            size: 18,
                          ),
                          splashRadius: 18,
                        ),
                        const SizedBox(width: 4),
                        isLoadingThisSong
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : isDownloadingThisSong
                            ? IconButton(
                                onPressed: () =>
                                    downloads.cancelDownload(videoId),
                                splashRadius: 14,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(
                                  minWidth: 18,
                                  minHeight: 18,
                                ),
                                icon: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      const CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                      Icon(
                                        Icons.stop_rounded,
                                        size: 10,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    ],
                                  ),
                                ),
                              )
                            : Text(
                                songDurationLabel,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                      ],
                    ),
                    onTap: _selectionMode
                        ? () => _toggleSongSelection(videoId)
                        : () => _playSongAtIndex(index, songs, song),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final liked = context.watch<LikedSongsProvider>();

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: _selectionMode
                ? [
                    IconButton(
                      onPressed: _exitSelectionMode,
                      icon: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${_selectedVideoIds.length} selected',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      onPressed: _selectedVideoIds.isEmpty
                          ? null
                          : () => _addSelectedToPlaylist(liked.songs),
                      icon: Icon(
                        Icons.playlist_add_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ]
                : [
                    Icon(Icons.favorite_rounded, color: colorScheme.onSurface),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Liked Songs',
                        style: TextStyle(
                          color: colorScheme.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (liked.songs.isNotEmpty) ...[
                      Text(
                        '${liked.songs.length} songs',
                        style: TextStyle(color: colorScheme.onSurfaceVariant),
                      ),
                      const SizedBox(width: 12),
                    ],
                    PopupMenuButton<_LikedSort>(
                      initialValue: _sort,
                      onSelected: (value) => setState(() => _sort = value),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      icon: Icon(
                        _sort == _LikedSort.custom
                            ? Icons.sort_rounded
                            : Icons.filter_list_rounded,
                        color: _sort == _LikedSort.custom
                            ? colorScheme.onSurfaceVariant
                            : colorScheme.primary,
                      ),
                      itemBuilder: (context) => [
                        for (final option in _LikedSort.values)
                          PopupMenuItem(
                            value: option,
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: option == _sort
                                  ? Icon(
                                      Icons.check_rounded,
                                      color: colorScheme.primary,
                                    )
                                  : const SizedBox(width: 24),
                              title: Text(option.label),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      onPressed: liked.isLoading ? null : () => liked.refresh(),
                      icon: Icon(
                        Icons.refresh_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
          ),
          const SizedBox(height: 12),
          Expanded(child: _buildContent(context, liked)),
        ],
      ),
    );
  }
}
