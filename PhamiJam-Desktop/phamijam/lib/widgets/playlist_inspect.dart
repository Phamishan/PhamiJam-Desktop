import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/playback_model.dart';
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
  const PlaylistInspectPage({super.key, this.extra, this.onBack});

  final Map<String, dynamic>? extra;
  final VoidCallback? onBack;

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
  int _currentPlaylistIndex = -1;
  late final PlaybackModel _playback;

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

  Widget _buildMetadataRow() {
    final creatorLabel = _playlistCreator ?? 'Unknown creator';
    final songCountLabel = (_playlistSongCount ?? _songs.length).toString();
    final durationLabel = _formatDuration(_playlistDurationSeconds);

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        Text(
          creatorLabel,
          style: const TextStyle(color: Colors.white70),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '$songCountLabel songs',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(durationLabel, style: const TextStyle(color: Colors.white70)),
      ],
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
      final playlistData = await _fetchPlaylistDataWithYoutubeExplode(
        playlistId,
      );
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
    Map<String, dynamic> song,
  ) async {
    if (_currentlyLoadingVideoId != null) return;

    final playback = _playback;
    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This song has no playable video id.')),
      );
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
        _currentPlaylistIndex = index;
      }
    } catch (error) {
      debugPrint('YouTube audio playback failed for $videoId: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to play audio: $error')));
    } finally {
      if (mounted) {
        setState(() {
          _currentlyLoadingVideoId = null;
        });
      }
    }
  }

  void _syncCurrentIndexFromPlaybackPath() {
    if (_currentPlaylistIndex >= 0 || _songs.isEmpty) return;

    final currentPath = _playback.currentSongPath;
    if (currentPath == null || !currentPath.startsWith('yt:')) {
      return;
    }

    final currentVideoId = currentPath.substring(3);
    final resolvedIndex = _songs.indexWhere(
      (song) => (song['videoId'] as String?) == currentVideoId,
    );
    if (resolvedIndex >= 0) {
      _currentPlaylistIndex = resolvedIndex;
    }
  }

  Future<void> _autoplayNextSong() async {
    if (!mounted || _currentlyLoadingVideoId != null) return;
    if (_songs.isEmpty) return;

    _syncCurrentIndexFromPlaybackPath();

    if (_currentPlaylistIndex < 0) return;

    final nextIndex = _currentPlaylistIndex + 1;
    if (nextIndex >= _songs.length) return;

    final nextSong = _songs[nextIndex];
    await _playYouTubeSongAtIndex(nextIndex, nextSong);
  }

  Future<void> _playPreviousSong() async {
    if (!mounted || _currentlyLoadingVideoId != null || _songs.isEmpty) return;
    _syncCurrentIndexFromPlaybackPath();
    if (_currentPlaylistIndex <= 0) return;

    final previousIndex = _currentPlaylistIndex - 1;
    final previousSong = _songs[previousIndex];
    await _playYouTubeSongAtIndex(previousIndex, previousSong);
  }

  Future<void> _playNextSong() async {
    await _autoplayNextSong();
  }

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _playback.setOnPreviousRequested(_playPreviousSong);
    _playback.setOnNextRequested(_playNextSong);
    _loadSongs();
  }

  @override
  void dispose() {
    _playback.setOnPreviousRequested(null);
    _playback.setOnNextRequested(null);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant PlaylistInspectPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldPlaylistId = oldWidget.extra?['playlistId'] as String?;
    final newPlaylistId = _playlistId;
    if (oldPlaylistId != newPlaylistId) {
      _loadSongs();
    }
  }

  Widget _buildPlaylistInspectContent() {
    if (_isLoadingSongs) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.white70, fontSize: 16),
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
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              Expanded(
                child: Text(
                  _displayPlaylistTitle,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _loadSongs(forceRefresh: true),
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildMetadataRow(),
          const SizedBox(height: 16),
          const Expanded(
            child: Center(
              child: Text(
                'No songs found in this playlist.',
                style: TextStyle(color: Colors.white70, fontSize: 16),
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
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            Expanded(
              child: Text(
                _displayPlaylistTitle,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: () => _loadSongs(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _buildMetadataRow(),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            itemCount: _songs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final song = _songs[index];
              final title = (song['title'] as String?) ?? 'Unknown song';
              final artist = (song['artist'] as String?) ?? 'Unknown artist';
              final thumbnailUrl = (song['thumbnailUrl'] as String?) ?? '';
              final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
              final songDurationLabel = _formatDuration(durationSeconds);
              final videoId = (song['videoId'] as String?) ?? '';
              final isLoadingThisSong =
                  videoId.isNotEmpty && _currentlyLoadingVideoId == videoId;
              final playback = context.watch<PlaybackModel>();
              final isCurrentSong = playback.currentSongPath == 'yt:$videoId';

              return Container(
                decoration: BoxDecoration(
                  color: isCurrentSong
                      ? const Color(0xFFb5832e)
                      : const Color(0xFFdba43a),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListTile(
                  leading: thumbnailUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            thumbnailUrl,
                            width: 56,
                            height: 56,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const Icon(
                                  Icons.music_note,
                                  color: Colors.white,
                                ),
                          ),
                        )
                      : const Icon(Icons.music_note, color: Colors.white),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: isLoadingThisSong
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          songDurationLabel,
                          style: const TextStyle(color: Colors.white70),
                        ),
                  onTap: () => _playYouTubeSongAtIndex(index, song),
                ),
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
