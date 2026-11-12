import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/mixed_playlist_dialogs.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/playlist_cover_service.dart';
import 'package:provider/provider.dart';

class MixedPlaylistPage extends StatefulWidget {
  const MixedPlaylistPage({super.key, required this.playlistId, this.onBack});

  final String playlistId;
  final VoidCallback? onBack;

  @override
  State<MixedPlaylistPage> createState() => _MixedPlaylistPageState();
}

class _MixedPlaylistPageState extends State<MixedPlaylistPage> {
  late final PlaybackModel _playback;
  StreamSubscription<Map<String, dynamic>?>? _subscription;
  StreamSubscription<Map<String, String>>? _coverSubscription;
  String? _customCoverUrl;
  bool _uploadingCover = false;
  Map<String, dynamic>? _playlist;
  bool _loading = true;
  bool _missing = false;
  int? _loadingIndex;
  final Map<String, bool> _localExists = {};

  List<Map<String, dynamic>> get _tracks =>
      (_playlist?['tracks'] as List<Map<String, dynamic>>?) ?? const [];

  String get _title => (_playlist?['title'] as String?) ?? 'Playlist';

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _coverSubscription = PlaylistCoverService.watchAll().listen((overrides) {
      if (!mounted) return;
      setState(
        () => _customCoverUrl =
            overrides[MixedPlaylistService.coverKey(widget.playlistId)],
      );
    });
    _subscription = MixedPlaylistService.watchOne(widget.playlistId).listen(
      (playlist) {
        if (!mounted) return;
        if (playlist != null) {
          for (final track
              in playlist['tracks'] as List<Map<String, dynamic>>) {
            if (track['source'] == 'local') {
              final path = (track['path'] as String?) ?? '';
              _localExists[path] = path.isNotEmpty && File(path).existsSync();
            }
          }
        }
        setState(() {
          _playlist = playlist;
          _missing = playlist == null;
          _loading = false;
        });
      },
      onError: (_) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _missing = true;
        });
      },
    );
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _coverSubscription?.cancel();
    super.dispose();
  }

  Future<void> _changeCover() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null || !mounted) return;
    setState(() => _uploadingCover = true);
    try {
      await PlaylistCoverService.upload(
        MixedPlaylistService.coverKey(widget.playlistId),
        File(picked.path),
      );
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't update cover image: $error");
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  Future<void> _removeCover() async {
    setState(() => _uploadingCover = true);
    try {
      await PlaylistCoverService.remove(
        MixedPlaylistService.coverKey(widget.playlistId),
      );
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't remove cover image: $error");
      }
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
  }

  static String _sourceOf(Map<String, dynamic> track) =>
      (track['source'] as String?) ?? 'youtube';

  static String _expectedPath(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return (track['path'] as String?) ?? '';
      case 'drive':
        return (track['videoId'] as String?) ?? '';
      default:
        return 'yt:${track['videoId'] ?? ''}';
    }
  }

  bool _isPlayable(Map<String, dynamic> track) {
    if (_sourceOf(track) != 'local') return true;
    return _localExists[(track['path'] as String?) ?? ''] ?? false;
  }

  Map<String, dynamic> _queueItem(Map<String, dynamic> track) {
    final title = (track['title'] as String?) ?? '';
    final artist = (track['artist'] as String?) ?? '';
    final artistId = (track['artistId'] as String?) ?? '';
    final durationMs = (track['durationMs'] as int?) ?? 0;
    final item = <String, dynamic>{
      'title': title,
      'artist': artist,
      'songName': title,
      'artistName': artist,
      'artistId': artistId.isEmpty ? null : artistId,
      'thumbnailUrl': (track['thumbnailUrl'] as String?) ?? '',
      'durationSeconds': (durationMs / 1000).round(),
    };
    if (_sourceOf(track) == 'local') {
      item['path'] = (track['path'] as String?) ?? '';
      item['coverImageBytes'] = null;
    } else {
      item['videoId'] = (track['videoId'] as String?) ?? '';
    }
    return item;
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) return response.bodyBytes;
    } catch (_) {}
    return null;
  }

  Future<bool> _startPlayback(Map<String, dynamic> track) async {
    final playback = _playback;
    final title = (track['title'] as String?) ?? 'Unknown song';
    final artist = (track['artist'] as String?) ?? 'Unknown artist';
    final durationMs = (track['durationMs'] as int?) ?? 0;
    final duration = durationMs > 0
        ? Duration(milliseconds: durationMs)
        : Duration.zero;
    final videoId = (track['videoId'] as String?) ?? '';

    switch (_sourceOf(track)) {
      case 'local':
        final path = (track['path'] as String?) ?? '';
        if (path.isEmpty || !await File(path).exists()) {
          if (mounted) {
            AppFlushbar.error(context, '"$title" is not on this computer.');
          }
          return false;
        }
        await playback.switchToLocalEngine();
        playback.setDuration(Duration.zero);
        await player.setFilePath(path);
        await player.seek(Duration.zero);
        await player.play();
        playback.setArtist(artist);
        playback.setArtistId(null);
        playback.setSongName(title);
        playback.setCurrentSongPath(path);
        playback.setCoverImageBytes(null);
        playback.setDuration(duration);
        playback.setIsPlaying(true);
        playback.setIsMuted(false);
        return true;
      case 'drive':
        if (!videoId.startsWith(driveTrackIdPrefix)) return false;
        final fileId = videoId.substring(driveTrackIdPrefix.length);
        await playback.switchToLocalEngine();
        playback.setDuration(Duration.zero);
        final headers = await GoogleDriveService.streamHeaders(fileId);
        await player.setUrl(
          GoogleDriveService.streamUri(fileId).toString(),
          headers: headers,
        );
        await player.seek(Duration.zero);
        await player.play();
        playback.setArtist(artist);
        playback.setArtistId(null);
        playback.setSongName(title);
        playback.setCurrentSongPath(videoId);
        playback.setCoverImageBytes(null);
        playback.setDuration(duration);
        playback.setIsPlaying(true);
        playback.setIsMuted(false);
        return true;
      default:
        if (videoId.isEmpty) return false;
        final cover = await _downloadImageBytes(
          (track['thumbnailUrl'] as String?) ?? '',
        );
        final artistId = (track['artistId'] as String?) ?? '';
        playback.setSongName(title);
        playback.setArtist(artist);
        playback.setArtistId(artistId.isEmpty ? null : artistId);
        playback.setCurrentSongPath('yt:$videoId');
        playback.setCoverImageBytes(cover);
        playback.setDuration(duration);
        await playback.playYouTubeVideoById(videoId);
        await playback.applyVolume(playback.currentSliderValue);
        return true;
    }
  }

  Future<void> _playFrom(
    List<Map<String, dynamic>> tracks,
    int index, {
    required bool syncQueue,
  }) async {
    if (index < 0 || index >= tracks.length) return;
    if (syncQueue) setState(() => _loadingIndex = index);
    try {
      final started = await _startPlayback(tracks[index]);
      if (!started) return;

      if (syncQueue) {
        _playback.setPlaylistQueue(
          tracks.map(_queueItem).toList(),
          startIndex: index,
        );
        _playback.setQueueHandlers(
          playAtSourceIndex: (sourceIndex) async {
            if (sourceIndex < 0 || sourceIndex >= tracks.length) return;
            final ok = await _startPlayback(tracks[sourceIndex]);
            if (ok) _playback.markCurrentSourceIndex(sourceIndex);
          },
          prefetchQueueItem: (item) async {
            if (item is! Map<String, dynamic>) return;
            final videoId = (item['videoId'] as String?) ?? '';
            if (videoId.isEmpty || videoId.startsWith(driveTrackIdPrefix)) {
              return;
            }
            await _playback.prefetchYouTubeVideoById(videoId);
          },
        );
      } else {
        _playback.markCurrentSourceIndex(index);
      }
    } catch (error) {
      if (mounted) AppFlushbar.error(context, 'Failed to play: $error');
    } finally {
      if (syncQueue && mounted) setState(() => _loadingIndex = null);
    }
  }

  Future<void> _playAll() async {
    final tracks = List<Map<String, dynamic>>.from(_tracks);
    final first = tracks.indexWhere(_isPlayable);
    if (first < 0) return;
    await _playFrom(tracks, first, syncQueue: true);
  }

  Future<void> _playTrack(int index) async {
    if (_loadingIndex != null) return;
    await _playFrom(
      List<Map<String, dynamic>>.from(_tracks),
      index,
      syncQueue: true,
    );
  }

  Future<void> _rename() async {
    final name = await showMixedPlaylistNameDialog(
      context,
      title: 'Rename playlist',
      initial: _title,
      actionLabel: 'Save',
    );
    if (name == null || name == _title) return;
    try {
      await MixedPlaylistService.rename(widget.playlistId, name);
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't rename playlist: $error");
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await confirmDeleteMixedPlaylist(context, _title);
    if (!confirmed) return;
    try {
      await MixedPlaylistService.delete(widget.playlistId);
      if (mounted) widget.onBack?.call();
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't delete playlist: $error");
      }
    }
  }

  Future<void> _removeTrack(int index) async {
    final title = (_tracks[index]['title'] as String?) ?? 'song';
    try {
      await MixedPlaylistService.removeTrackAt(widget.playlistId, index);
      if (mounted) AppFlushbar.success(context, 'Removed "$title"');
    } catch (error) {
      if (mounted) AppFlushbar.error(context, "Couldn't remove song: $error");
    }
  }

  String _sourceLabel(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return _isPlayable(track) ? 'This computer' : 'Not on this computer';
      case 'drive':
        return 'Google Drive';
      default:
        return 'YouTube';
    }
  }

  IconData _sourceIcon(Map<String, dynamic> track) {
    switch (_sourceOf(track)) {
      case 'local':
        return Icons.computer_rounded;
      case 'drive':
        return Icons.cloud_rounded;
      default:
        return Icons.music_note_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final currentPath = context.select<PlaybackModel, String?>(
      (p) => p.currentSongPath,
    );

    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_missing) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'This playlist no longer exists.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
            TextButton(onPressed: widget.onBack, child: const Text('Back')),
          ],
        ),
      );
    }

    final tracks = _tracks;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: widget.onBack,
              ),
              GestureDetector(
                onTap: _uploadingCover ? null : _changeCover,
                child: Tooltip(
                  message: 'Change cover image',
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: SizedBox(
                          width: 56,
                          height: 56,
                          child: Builder(
                            builder: (context) {
                              final firstThumb = tracks
                                  .map(
                                    (t) => (t['thumbnailUrl'] as String?) ?? '',
                                  )
                                  .firstWhere(
                                    (u) => u.isNotEmpty,
                                    orElse: () => '',
                                  );
                              final cover =
                                  (_customCoverUrl != null &&
                                      _customCoverUrl!.isNotEmpty)
                                  ? _customCoverUrl!
                                  : firstThumb;
                              return cover.isEmpty
                                  ? Container(
                                      color: colorScheme.surfaceContainerHigh,
                                      child: Icon(
                                        Icons.library_music_rounded,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Image.network(
                                      cover,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => Container(
                                        color: colorScheme.surfaceContainerHigh,
                                      ),
                                    );
                            },
                          ),
                        ),
                      ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          color: Colors.black.withValues(alpha: 0.3),
                        ),
                        alignment: Alignment.center,
                        child: _uploadingCover
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(
                                Icons.camera_alt_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 18,
                  ),
                ),
              ),
              if (_customCoverUrl != null && _customCoverUrl!.isNotEmpty)
                IconButton(
                  tooltip: 'Remove custom cover',
                  icon: const Icon(Icons.hide_image_rounded),
                  onPressed: _uploadingCover ? null : _removeCover,
                ),
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_rounded),
                onPressed: _rename,
              ),
              IconButton(
                tooltip: 'Delete playlist',
                icon: Icon(Icons.delete_rounded, color: colorScheme.error),
                onPressed: _delete,
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: Text(
              'PhamiJam playlist · ${tracks.length} '
              '${tracks.length == 1 ? 'song' : 'songs'}',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, bottom: 8),
            child: ElevatedButton.icon(
              onPressed: tracks.any(_isPlayable) ? _playAll : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: const Text('Play all'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
            ),
          ),
          Expanded(
            child: tracks.isEmpty
                ? Center(
                    child: Text(
                      'No songs yet. Add songs from a YouTube playlist, '
                      'Google Drive or Local Files using "Add to playlist".',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  )
                : ListView.separated(
                    itemCount: tracks.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 4),
                    itemBuilder: (context, index) {
                      final track = tracks[index];
                      final playable = _isPlayable(track);
                      final isCurrent = currentPath == _expectedPath(track);
                      final thumbnailUrl =
                          (track['thumbnailUrl'] as String?) ?? '';
                      final artist = (track['artist'] as String?) ?? '';
                      return Material(
                        color: isCurrent
                            ? colorScheme.primary.withValues(alpha: 0.18)
                            : colorScheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(8),
                        child: ListTile(
                          enabled: playable,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          leading: ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              width: 44,
                              height: 44,
                              child: thumbnailUrl.isEmpty
                                  ? Container(
                                      color: colorScheme.surfaceContainerHigh,
                                      child: Icon(
                                        _sourceIcon(track),
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                    )
                                  : Image.network(
                                      thumbnailUrl,
                                      fit: BoxFit.cover,
                                      cacheWidth: 88,
                                      cacheHeight: 88,
                                      errorBuilder: (_, _, _) => Container(
                                        color: colorScheme.surfaceContainerHigh,
                                      ),
                                    ),
                            ),
                          ),
                          title: Text(
                            (track['title'] as String?) ?? 'Unknown song',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                          subtitle: Text(
                            '${artist.isEmpty ? '' : '$artist · '}'
                            '${_sourceLabel(track)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: _loadingIndex == index
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : PopupMenuButton<String>(
                                  tooltip: '',
                                  onSelected: (value) {
                                    if (value == 'next' && playable) {
                                      _playback.addToQueue(_queueItem(track));
                                    } else if (value == 'queue' && playable) {
                                      _playback.appendToQueue(
                                        _queueItem(track),
                                      );
                                    } else if (value == 'remove') {
                                      _removeTrack(index);
                                    }
                                  },
                                  itemBuilder: (context) => const [
                                    PopupMenuItem(
                                      value: 'next',
                                      child: Text('Play next'),
                                    ),
                                    PopupMenuItem(
                                      value: 'queue',
                                      child: Text('Add to queue'),
                                    ),
                                    PopupMenuItem(
                                      value: 'remove',
                                      child: Text('Remove from playlist'),
                                    ),
                                  ],
                                ),
                          onTap: playable ? () => _playTrack(index) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
