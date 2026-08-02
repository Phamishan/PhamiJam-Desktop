import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/edit_song_dialog.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

class _PlaylistInspectCacheEntry {
  const _PlaylistInspectCacheEntry({
    required this.songs,
    required this.playlistCreator,
    required this.playlistSongCount,
    required this.playlistDurationSeconds,
    required this.resolvedPlaylistTitle,
    required this.errorMessage,
  });

  final List<Map<String, dynamic>> songs;
  final String? playlistCreator;
  final int? playlistSongCount;
  final int playlistDurationSeconds;
  final String? resolvedPlaylistTitle;
  final String? errorMessage;
}

class PlaylistInspectPage extends StatefulWidget {
  final Map<String, dynamic>? extra;
  final VoidCallback? onBack;
  final VoidCallback? onPlayPauseToggle;
  final VoidCallback? onShuffleToggle;
  final VoidCallback? onLoopToggle;
  final bool isPlaying;
  final bool isShuffled;
  final bool isLooped;
  final void Function(String artistId, String artistName)? onOpenArtist;

  const PlaylistInspectPage({
    super.key,
    this.extra,
    this.onBack,
    this.onPlayPauseToggle,
    this.onShuffleToggle,
    this.onLoopToggle,
    this.isPlaying = false,
    this.isShuffled = false,
    this.isLooped = false,
    this.onOpenArtist,
  });

  @override
  State<PlaylistInspectPage> createState() => _PlaylistInspectPageState();
}

class _PlaylistInspectPageState extends State<PlaylistInspectPage> {
  static final Map<String, _PlaylistInspectCacheEntry>
  _cachedStateByPlaylistId = <String, _PlaylistInspectCacheEntry>{};
  bool _isLoadingSongs = false;
  String? _errorMessage;
  List<Map<String, dynamic>> _songs = [];
  String? _playlistCreator;
  int? _playlistSongCount;
  int _playlistDurationSeconds = 0;
  String? _resolvedPlaylistTitle;
  String? _currentlyLoadingVideoId;
  String _songSearchQuery = '';
  late final TextEditingController _songSearchController;
  late final PlaybackModel _playback;

  List<Map<String, dynamic>> get _filteredSongs {
    final query = _songSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _songs;
    }

    return _songs.where((song) {
      final title = (song['title'] as String?) ?? '';
      final artist = (song['artist'] as String?) ?? '';
      return title.toLowerCase().contains(query) ||
          artist.toLowerCase().contains(query);
    }).toList();
  }

  int _sourceSongIndex(Map<String, dynamic> song) {
    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isNotEmpty) {
      final byVideoId = _songs.indexWhere(
        (item) => (item['videoId'] as String?) == videoId,
      );
      if (byVideoId >= 0) {
        return byVideoId;
      }
    }

    return _songs.indexOf(song);
  }

  String get _playlistTitle =>
      (widget.extra?['playlistTitle'] as String?) ?? 'Playlist';

  String get _displayPlaylistTitle => _resolvedPlaylistTitle ?? _playlistTitle;

  String? get _playlistId => widget.extra?['playlistId'] as String?;

  void _handleBack() {
    final onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    Navigator.of(context).maybePop();
  }

  String _resolvePlaylistId(String playlistIdOrUrl) {
    final resolved = PlaylistId.parsePlaylistId(playlistIdOrUrl);
    if (resolved != null && resolved.isNotEmpty) {
      return resolved;
    }
    if (playlistIdOrUrl.isNotEmpty) {
      return playlistIdOrUrl;
    }
    throw Exception('Invalid playlist id or url.');
  }

  Future<Map<String, dynamic>> _fetchPlaylistDataWithYoutubeExplode(
    String playlistIdOrUrl,
  ) async {
    final youtube = YoutubeExplode();
    try {
      final playlistId = _resolvePlaylistId(playlistIdOrUrl);
      final playlist = await youtube.playlists.get(playlistId);
      final songs = <Map<String, dynamic>>[];
      var totalDurationSeconds = 0;

      await for (final video in youtube.playlists.getVideos(playlistId)) {
        final videoId = video.id.value;
        if (videoId.isEmpty) {
          continue;
        }

        final durationSeconds = video.duration?.inSeconds ?? 0;
        totalDurationSeconds += durationSeconds;

        final title = video.title.trim().isEmpty ? 'Unknown song' : video.title;
        final artist = video.author.trim().isEmpty
            ? 'Unknown artist'
            : video.author;

        songs.add(<String, dynamic>{
          'title': title,
          'artist': artist,
          'artistId': video.channelId.value,
          'videoId': videoId,
          'thumbnailUrl': video.thumbnails.highResUrl,
          'durationSeconds': durationSeconds,
        });
      }

      return <String, dynamic>{
        'title': playlist.title,
        'creator': playlist.author,
        'songCount': playlist.videoCount ?? songs.length,
        'durationSeconds': totalDurationSeconds,
        'songs': songs,
      };
    } finally {
      youtube.close();
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

  Widget _buildPinButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final playlistId = _playlistId;
    return Consumer<PlaylistPinProvider>(
      builder: (context, pins, _) {
        final isPinned = playlistId != null && pins.isPinned(playlistId);
        return IconButton(
          onPressed: playlistId == null
              ? null
              : () => pins.togglePin(playlistId),
          icon: Icon(
            isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            color: isPinned ? colorScheme.primary : colorScheme.onSurface,
          ),
        );
      },
    );
  }

  Widget _buildMetadataRow() {
    final colorScheme = Theme.of(context).colorScheme;
    final creatorLabel = _playlistCreator ?? 'Unknown creator';
    final songCountLabel = (_playlistSongCount ?? _songs.length).toString();
    final durationLabel = _formatDuration(_playlistDurationSeconds);

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          creatorLabel,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '$songCountLabel songs',
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
        Text(
          durationLabel,
          style: TextStyle(color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildControlButtons() {
    final colorScheme = Theme.of(context).colorScheme;
    final needsPlaybackState =
        widget.onPlayPauseToggle == null ||
        widget.onShuffleToggle == null ||
        widget.onLoopToggle == null;
    final playbackState = needsPlaybackState
        ? context.select<PlaybackModel, (bool, bool, bool)>(
            (playback) =>
                (playback.isPlaying, playback.isShuffled, playback.isLooped),
          )
        : null;
    final isPlaying = widget.onPlayPauseToggle != null
        ? widget.isPlaying
        : playbackState!.$1;
    final isShuffled = widget.onShuffleToggle != null
        ? widget.isShuffled
        : playbackState!.$2;
    final isLooped = widget.onLoopToggle != null
        ? widget.isLooped
        : playbackState!.$3;

    return Row(
      children: [
        IconButton(
          onPressed: () async {
            if (isPlaying) {
              final onPlayPauseToggle = widget.onPlayPauseToggle;
              if (onPlayPauseToggle != null) {
                onPlayPauseToggle();
                return;
              }
              await _playback.togglePlayPause();
              return;
            }

            if (_songs.isEmpty) {
              return;
            }

            final targetIndex = isShuffled
                ? Random().nextInt(_songs.length)
                : 0;
            await _playYouTubeSongAtIndex(targetIndex, _songs[targetIndex]);
          },
          icon: isPlaying
              ? Icon(Icons.pause_circle_rounded, color: colorScheme.primary)
              : Icon(Icons.play_circle_rounded, color: colorScheme.primary),
        ),
        IconButton(
          onPressed: () {
            final onShuffleToggle = widget.onShuffleToggle;
            if (onShuffleToggle != null) {
              onShuffleToggle();
              return;
            }
            _playback.toggleShuffle();
          },
          icon: isShuffled
              ? Icon(Icons.shuffle_on_rounded, color: colorScheme.primary)
              : Icon(Icons.shuffle_rounded, color: colorScheme.primary),
        ),
        IconButton(
          onPressed: () {
            final onLoopToggle = widget.onLoopToggle;
            if (onLoopToggle != null) {
              onLoopToggle();
              return;
            }
            _playback.toggleLoop();
          },
          icon: isLooped
              ? Icon(Icons.repeat_one_on_rounded, color: colorScheme.primary)
              : Icon(Icons.repeat_one_rounded, color: colorScheme.primary),
        ),
        if (_songs.isNotEmpty) _buildDownloadPlaylistButton(),
      ],
    );
  }

  Widget _buildDownloadPlaylistButton() {
    final colorScheme = Theme.of(context).colorScheme;
    final downloads = context.watch<DownloadsProvider>();
    final videoIds = _songs
        .map((s) => (s['videoId'] as String?) ?? '')
        .where((id) => id.isNotEmpty);
    final allDownloaded =
        videoIds.isNotEmpty && videoIds.every(downloads.isDownloaded);
    final anyDownloading = videoIds.any(downloads.isDownloading);

    if (anyDownloading) {
      return IconButton(
        onPressed: downloads.cancelAllDownloads,
        icon: SizedBox(
          width: 20,
          height: 20,
          child: Stack(
            alignment: Alignment.center,
            children: [
              const CircularProgressIndicator(strokeWidth: 2),
              Icon(
                Icons.stop_rounded,
                size: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      );
    }

    return IconButton(
      onPressed: allDownloaded
          ? null
          : () => downloads.downloadTracks([
              for (final s in _songs)
                {
                  'videoId': s['videoId'],
                  'songName': s['title'],
                  'artistName': s['artist'],
                  'artistId': s['artistId'],
                  'durationSeconds': s['durationSeconds'],
                },
            ]),
      icon: Icon(
        allDownloaded ? Icons.download_done_rounded : Icons.download_rounded,
        color: allDownloaded ? colorScheme.primary : colorScheme.primary,
      ),
    );
  }

  Future<void> _loadSongs({bool forceRefresh = false}) async {
    final playlistId = _playlistId;
    if (playlistId == null || playlistId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoadingSongs = false;
        _errorMessage = 'Missing playlist id.';
        _songs = [];
      });
      return;
    }

    if (!forceRefresh && _cachedStateByPlaylistId.containsKey(playlistId)) {
      final cached = _cachedStateByPlaylistId[playlistId]!;
      if (!mounted) return;
      setState(() {
        _songs = List<Map<String, dynamic>>.from(cached.songs);
        _playlistCreator = cached.playlistCreator;
        _playlistSongCount = cached.playlistSongCount;
        _playlistDurationSeconds = cached.playlistDurationSeconds;
        _resolvedPlaylistTitle = cached.resolvedPlaylistTitle;
        _errorMessage = cached.errorMessage;
        _isLoadingSongs = false;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingSongs = true;
      _errorMessage = null;
      _playlistCreator = null;
      _playlistSongCount = null;
      _playlistDurationSeconds = 0;
      _resolvedPlaylistTitle = null;
    });

    try {
      Map<String, dynamic> playlistData;
      try {
        playlistData = await YoutubePlaylistService.fetchPlaylistSongs(
          playlistId,
        );
      } catch (apiError) {
        debugPrint(
          'Authenticated playlist fetch failed, falling back to public scrape: $apiError',
        );
        playlistData = await _fetchPlaylistDataWithYoutubeExplode(playlistId);
      }
      final songsWithDurations =
          (playlistData['songs'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((song) => Map<String, dynamic>.from(song))
              .toList() ??
          <Map<String, dynamic>>[];
      final totalDurationSeconds =
          (playlistData['durationSeconds'] as int?) ??
          songsWithDurations
              .map((song) => song['durationSeconds'])
              .whereType<int>()
              .fold<int>(0, (sum, secs) => sum + secs);

      if (!mounted) return;
      setState(() {
        _songs = songsWithDurations;
        _playlistCreator = playlistData['creator'] as String?;
        _playlistSongCount =
            (playlistData['songCount'] as int?) ?? songsWithDurations.length;
        _playlistDurationSeconds = totalDurationSeconds;
        final resolvedTitle = playlistData['title'] as String?;
        if (resolvedTitle != null && resolvedTitle.isNotEmpty) {
          _resolvedPlaylistTitle = resolvedTitle;
        }
      });

      final playback = context.read<PlaybackModel>();
      for (final song in songsWithDurations.take(5)) {
        final videoId = (song['videoId'] as String?) ?? '';
        if (videoId.isEmpty) continue;
        playback.prefetchYouTubeVideoById(videoId);
      }

      _cachedStateByPlaylistId[playlistId] = _PlaylistInspectCacheEntry(
        songs: List<Map<String, dynamic>>.from(songsWithDurations),
        playlistCreator: _playlistCreator,
        playlistSongCount: _playlistSongCount,
        playlistDurationSeconds: _playlistDurationSeconds,
        resolvedPlaylistTitle: _resolvedPlaylistTitle,
        errorMessage: null,
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Failed to load songs from YouTube.\n$error';
      });

      _cachedStateByPlaylistId[playlistId] = _PlaylistInspectCacheEntry(
        songs: List<Map<String, dynamic>>.from(_songs),
        playlistCreator: _playlistCreator,
        playlistSongCount: _playlistSongCount,
        playlistDurationSeconds: _playlistDurationSeconds,
        resolvedPlaylistTitle: _resolvedPlaylistTitle,
        errorMessage: _errorMessage,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSongs = false;
        });
      }
    }
  }

  Future<void> _playYouTubeSongAtIndex(
    int? index,
    Map<String, dynamic> song, {
    bool syncQueue = true,
  }) async {
    if (_currentlyLoadingVideoId != null) return;

    final playback = _playback;
    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) {
      if (!mounted) return;
      AppFlushbar.error(context, 'This song has no playable video id.');
      return;
    }

    setState(() {
      _currentlyLoadingVideoId = videoId;
    });

    try {
      final title = (song['title'] as String?) ?? 'Unknown song';
      final artist = (song['artist'] as String?) ?? 'Unknown artist';
      final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
      final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
      final coverBytes = await _downloadImageBytes(thumbnailUrl);

      playback.setSongName(title);
      playback.setArtist(artist);
      playback.setArtistId(song['artistId'] as String?);
      playback.setCurrentSongPath('yt:$videoId');
      playback.setCoverImageBytes(coverBytes);

      if (durationSeconds > 0) {
        playback.setDuration(Duration(seconds: durationSeconds));
      } else {
        playback.setDuration(Duration.zero);
      }

      await playback.playYouTubeVideoById(videoId);
      await playback.applyVolume(playback.currentSliderValue);

      if (index != null && index >= 0 && index < _songs.length) {
        if (syncQueue) {
          playback.setPlaylistQueue(_songs, startIndex: index);
          playback.setSourcePlaylist(
            id: _playlistId,
            title: _displayPlaylistTitle,
          );
          _registerQueueHandlersForSongs(
            List<Map<String, dynamic>>.from(_songs),
          );
        } else {
          playback.markCurrentSourceIndex(index);
        }
      }
    } catch (error) {
      debugPrint('YouTube audio playback failed for $videoId: $error');
      if (!mounted) return;
      AppFlushbar.error(context, 'Failed to play audio: $error');
    } finally {
      if (mounted) {
        setState(() {
          _currentlyLoadingVideoId = null;
        });
      }
    }
  }

  void _addYouTubeSongToQueue(Map<String, dynamic> song) {
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

  void _registerQueueHandlersForSongs(List<Map<String, dynamic>> songs) {
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

  @override
  void initState() {
    super.initState();
    _songSearchController = TextEditingController();
    _playback = context.read<PlaybackModel>();
    _loadSongs();
  }

  @override
  void dispose() {
    _songSearchController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlaylistInspectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPlaylistId = oldWidget.extra?['playlistId'] as String?;
    final newPlaylistId = _playlistId;
    if (oldPlaylistId != newPlaylistId) {
      _playback.clearPlaylistQueue();
      _songSearchController.clear();
      setState(() {
        _songSearchQuery = '';
      });
      _loadSongs();
    }
  }

  Widget _buildPlaylistInspectContent() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoadingSongs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 16),
        ),
      );
    }

    if (_songs.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _handleBack,
                icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
              ),
              Expanded(
                child: Text(
                  _displayPlaylistTitle,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _buildPinButton(),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _loadSongs(forceRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colorScheme.primaryContainer,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMetadataRow(),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: Text(
                'No songs found in this playlist.',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton(
              onPressed: _handleBack,
              icon: Icon(
                Icons.arrow_back_rounded,
                color: colorScheme.onSurface,
              ),
            ),
            Expanded(
              child: Text(
                _displayPlaylistTitle,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _buildPinButton(),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _loadSongs(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMetadataRow(),
        const SizedBox(height: 8),
        _buildControlButtons(),
        const SizedBox(height: 8),
        TextField(
          controller: _songSearchController,
          onChanged: (value) {
            setState(() {
              _songSearchQuery = value;
            });
          },
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search songs...',
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            suffixIcon: _songSearchQuery.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      _songSearchController.clear();
                      setState(() {
                        _songSearchQuery = '';
                      });
                    },
                  ),
            filled: true,
            fillColor: colorScheme.onSurface.withValues(alpha: 0.26),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
          ),
        ),

        const SizedBox(height: 12),
        Expanded(
          child: _filteredSongs.isEmpty
              ? Center(
                  child: Text(
                    'No songs match your search.',
                    style: TextStyle(
                      color: colorScheme.onSurfaceVariant,
                      fontSize: 16,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredSongs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final song = _filteredSongs[index];
                    final sourceIndex = _sourceSongIndex(song);
                    if (sourceIndex < 0) {
                      return const SizedBox.shrink();
                    }
                    final title = (song['title'] as String?) ?? 'Unknown song';
                    final artist =
                        (song['artist'] as String?) ?? 'Unknown artist';
                    final artistId = (song['artistId'] as String?) ?? '';
                    final thumbnailUrl =
                        (song['thumbnailUrl'] as String?) ?? '';
                    final durationSeconds =
                        (song['durationSeconds'] as int?) ?? 0;
                    final songDurationLabel = _formatDuration(durationSeconds);
                    final videoId = (song['videoId'] as String?) ?? '';
                    final isLoadingThisSong =
                        videoId.isNotEmpty &&
                        _currentlyLoadingVideoId == videoId;

                    return Builder(
                      builder: (context) {
                        final isCurrentSong = context
                            .select<PlaybackModel, bool>(
                              (playback) =>
                                  playback.currentSongPath == 'yt:$videoId',
                            );
                        final downloads = context.watch<DownloadsProvider>();
                        final isDownloaded = downloads.isDownloaded(videoId);
                        final isDownloadingThisSong = downloads.isDownloading(
                          videoId,
                        );
                        final likedSongs = context.watch<LikedSongsProvider>();
                        final isLiked = likedSongs.isLiked(videoId);

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
                                value: isDownloaded
                                    ? 'remove_download'
                                    : 'download',
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
                          ),
                          onItemSelected: (value) {
                            if (value == 'play_next') {
                              _addYouTubeSongToQueue(song);
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
                            } else if (value == 'edit_trim') {
                              if (videoId.isEmpty) {
                                AppFlushbar.error(
                                  context,
                                  'This song is unavailable.',
                                );
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
                                          errorBuilder:
                                              (context, error, stackTrace) =>
                                                  Icon(
                                                    Icons.music_note_rounded,
                                                    color:
                                                        colorScheme.onSurface,
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
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                subtitle:
                                    (artistId.isNotEmpty &&
                                        widget.onOpenArtist != null)
                                    ? MouseRegion(
                                        cursor: SystemMouseCursors.click,
                                        child: GestureDetector(
                                          onTap: () => widget.onOpenArtist!(
                                            artistId,
                                            artist,
                                          ),
                                          child: Text(
                                            artist,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                              decoration:
                                                  TextDecoration.underline,
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
                                      onPressed: videoId.isEmpty
                                          ? null
                                          : () => likedSongs.toggleLike({
                                              'videoId': videoId,
                                              'title': title,
                                              'artist': artist,
                                              'artistId': artistId,
                                              'thumbnailUrl': thumbnailUrl,
                                              'durationSeconds':
                                                  durationSeconds,
                                            }),
                                      icon: Icon(
                                        isLiked
                                            ? Icons.favorite_rounded
                                            : Icons.favorite_border_rounded,
                                        color: isLiked
                                            ? colorScheme.onSurface
                                            : colorScheme.onSurfaceVariant,
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
                                            onPressed: () => downloads
                                                .cancelDownload(videoId),
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
                                                    color: colorScheme
                                                        .onSurfaceVariant,
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : Text(
                                            songDurationLabel,
                                            style: TextStyle(
                                              color:
                                                  colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                  ],
                                ),
                                onTap: () =>
                                    _playYouTubeSongAtIndex(sourceIndex, song),
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildPlaylistInspectContent(),
    );
  }
}
