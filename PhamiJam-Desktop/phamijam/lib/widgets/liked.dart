import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:provider/provider.dart';

class LikedPage extends StatefulWidget {
  final void Function(String artistId, String artistName)? onOpenArtist;

  const LikedPage({super.key, this.onOpenArtist});

  @override
  State<LikedPage> createState() => _LikedPageState();
}

class _LikedPageState extends State<LikedPage> {
  String? _currentlyLoadingVideoId;
  late final PlaybackModel _playback;

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    final liked = context.read<LikedSongsProvider>();
    if (!liked.hasLoadedOnce && !liked.isLoading) {
      liked.refresh();
    }
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

        final title = (song['title'] as String?) ?? 'Unknown song';
        final artist = (song['artist'] as String?) ?? 'Unknown artist';
        final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
        final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
        final coverBytes = await _downloadImageBytes(thumbnailUrl);

        _playback.setSongName(title);
        _playback.setArtist(artist);
        _playback.setArtistId(song['artistId'] as String?);
        _playback.setCurrentSongPath('yt:$videoId');
        _playback.setCoverImageBytes(coverBytes);

        if (durationSeconds > 0) {
          _playback.setDuration(Duration(seconds: durationSeconds));
        } else {
          _playback.setDuration(Duration.zero);
        }

        await _playback.playYouTubeVideoById(videoId);
        await _playback.applyVolume(_playback.currentSliderValue);
        _playback.markCurrentSourceIndex(sourceIndex);
      },
      prefetchQueueItem: (item) async {
        if (item is! Map<String, dynamic>) return;
        final videoId = (item['videoId'] as String?) ?? '';
        if (videoId.isEmpty) return;
        await _playback.prefetchYouTubeVideoById(videoId);
      },
    );
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
      final title = (song['title'] as String?) ?? 'Unknown song';
      final artist = (song['artist'] as String?) ?? 'Unknown artist';
      final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
      final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
      final coverBytes = await _downloadImageBytes(thumbnailUrl);

      _playback.setSongName(title);
      _playback.setArtist(artist);
      _playback.setArtistId(song['artistId'] as String?);
      _playback.setCurrentSongPath('yt:$videoId');
      _playback.setCoverImageBytes(coverBytes);

      if (durationSeconds > 0) {
        _playback.setDuration(Duration(seconds: durationSeconds));
      } else {
        _playback.setDuration(Duration.zero);
      }

      await _playback.playYouTubeVideoById(videoId);
      await _playback.applyVolume(_playback.currentSliderValue);

      _playback.setPlaylistQueue(songs, startIndex: index);
      _registerQueueHandlers(List<Map<String, dynamic>>.from(songs));
    } catch (error) {
      debugPrint('YouTube audio playback failed for $videoId: $error');
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
    final downloads = context.watch<DownloadsProvider>();

    return ListView.separated(
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final song = songs[index];
        final title = (song['title'] as String?) ?? 'Unknown song';
        final artist = (song['artist'] as String?) ?? 'Unknown artist';
        final artistId = (song['artistId'] as String?) ?? '';
        final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
        final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
        final songDurationLabel = _formatDuration(durationSeconds);
        final videoId = (song['videoId'] as String?) ?? '';
        final isLoadingThisSong =
            videoId.isNotEmpty && _currentlyLoadingVideoId == videoId;
        final isDownloaded = downloads.isDownloaded(videoId);
        final isDownloadingThisSong = downloads.isDownloading(videoId);

        return Builder(
          builder: (context) {
            final isCurrentSong = context.select<PlaybackModel, bool>(
              (playback) => playback.currentSongPath == 'yt:$videoId',
            );

            return ContextMenuRegion<String>(
              contextMenu: ContextMenu(
                borderRadius: BorderRadius.circular(12),
                entries: [
                  MenuItem<String>(
                    value: 'play_next',
                    icon: const Icon(Icons.playlist_play_rounded),
                    label: const Text('Add to play next'),
                  ),
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
                    label: Text(isDownloaded ? 'Remove download' : 'Download'),
                  ),
                ],
              ),
              onItemSelected: (value) {
                if (value == 'play_next') {
                  _addToQueue(song);
                } else if (value == 'add_to_playlist') {
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
                    leading: thumbnailUrl.isNotEmpty
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
                            child: GestureDetector(
                              onTap: () =>
                                  widget.onOpenArtist!(artistId, artist),
                              child: Text(
                                artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colorScheme.onSurfaceVariant,
                                  decoration: TextDecoration.underline,
                                ),
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
                    onTap: () => _playSongAtIndex(index, songs, song),
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
            children: [
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
              IconButton(
                onPressed: liked.isLoading ? null : () => liked.refresh(),
                icon: Icon(Icons.refresh_rounded, color: colorScheme.onSurface),
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
