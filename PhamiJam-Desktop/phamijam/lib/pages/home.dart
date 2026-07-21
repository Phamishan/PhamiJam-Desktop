import 'dart:async';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/playback_interface.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/components/sidebar.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/widgets/converter.dart';
import 'package:phamijam/widgets/music_browse_pages.dart';
import 'package:phamijam/widgets/playlist_inspect.dart';
import 'package:phamijam/widgets/playlists.dart';
import 'package:phamijam/widgets/liked.dart';
import 'package:phamijam/widgets/profile.dart';
import 'package:phamijam/widgets/settings.dart';
import 'package:phamijam/widgets/local_files.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class _YouTubeResolvedStreams {
  const _YouTubeResolvedStreams({required this.urls, required this.expiresAt});

  final List<String> urls;
  final DateTime expiresAt;
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final TextEditingController _searchController;
  late final PlaybackModel _playback;
  late final VideoController _sidebarVideoController;
  Future<YTMusic>? _ytmusicFuture;
  YTMusic? _ytmusic;

  final yt.YoutubeExplode _youtubeExplode = yt.YoutubeExplode();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? userDisplayName;
  String _selectedTab = 'home';
  Map<String, dynamic>? _selectedTabExtra;
  final Map<String, _YouTubeResolvedStreams> _resolvedStreamsCache =
      <String, _YouTubeResolvedStreams>{};
  final Map<String, Future<List<String>>> _resolvingStreamsByVideoId =
      <String, Future<List<String>>>{};
  final List<Map<String, dynamic>> _recentPlayedSongs =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _recentPlayedPlaylists =
      <Map<String, dynamic>>[];
  final List<Map<String, String>> _trendingInDenmark = <Map<String, String>>[];
  bool _isLoadingTrendingInDenmark = false;
  String? _trendingInDenmarkError;
  String? _lastTrackedSongPath;
  static const Duration _resolvedStreamsTtl = Duration(minutes: 20);
  static const Map<String, String> _youtubeHttpHeaders = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0 Safari/537.36',
    'Referer': 'https://www.youtube.com/',
  };

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _sidebarVideoController = VideoController(player.mediaKitPlayer);
    _searchController = TextEditingController();
    _bindYouTubeEngineToPlayback();
    _playback.addListener(_onPlaybackChanged);
    _checkCurrentUser();
    unawaited(_loadTrendingInDenmark());
  }

  Future<void> _loadTrendingInDenmark() async {
    if (!mounted) return;
    setState(() {
      _isLoadingTrendingInDenmark = true;
      _trendingInDenmarkError = null;
    });

    try {
      final items = <Map<String, String>>[];
      final searchResult = await _youtubeExplode.search.search(
        'Denmark music trending now',
      );

      for (final video in searchResult) {
        final videoId = video.id.value;
        if (videoId.isEmpty) {
          continue;
        }
        items.add(<String, String>{
          'videoId': videoId,
          'title': video.title,
          'artist': video.author,
          'thumbnailUrl': video.thumbnails.highResUrl,
        });
        if (items.length >= 10) {
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _trendingInDenmark
          ..clear()
          ..addAll(items);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _trendingInDenmarkError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingTrendingInDenmark = false;
        });
      }
    }
  }

  void _pushRecentItem(
    List<Map<String, dynamic>> target,
    Map<String, dynamic> item,
    String dedupeKey,
  ) {
    final value = (item[dedupeKey] ?? '').toString();
    if (value.isEmpty) return;

    target.removeWhere(
      (entry) => ((entry[dedupeKey] ?? '').toString()) == value,
    );
    target.insert(0, item);
    if (target.length > 20) {
      target.removeRange(20, target.length);
    }
  }

  void _trackRecentPlaylist(Map<String, dynamic>? extra) {
    if (extra == null) return;
    final playlistId = (extra['playlistId'] as String?) ?? '';
    final playlistTitle = (extra['playlistTitle'] as String?) ?? '';
    final thumbnailUrl = (extra['thumbnailUrl'] as String?) ?? '';
    if (playlistId.isEmpty || playlistTitle.isEmpty) return;

    setState(() {
      _pushRecentItem(_recentPlayedPlaylists, <String, dynamic>{
        'playlistId': playlistId,
        'playlistTitle': playlistTitle,
        'thumbnailUrl': thumbnailUrl,
      }, 'playlistId');
    });
  }

  Future<Uint8List?> _downloadImageBytes(String imageUrl) async {
    if (imageUrl.isEmpty) return null;
    try {
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode == 200) {
        return response.bodyBytes;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _playYouTubeSelection({
    required String videoId,
    required String title,
    required String artist,
    String thumbnailUrl = '',
    String artistId = '',
  }) async {
    if (videoId.isEmpty) return;

    final cover = await _downloadImageBytes(thumbnailUrl);
    _playback.setSongName(title.isEmpty ? 'Unknown song' : title);
    _playback.setArtist(artist.isEmpty ? 'Unknown artist' : artist);
    _playback.setArtistId(artistId.isEmpty ? null : artistId);
    _playback.setCurrentSongPath('yt:$videoId');
    _playback.setCoverImageBytes(cover);
    await _playback.playYouTubeVideoById(videoId);
    await _playback.applyVolume(_playback.currentSliderValue);
  }

  Future<void> _playLocalSelection({
    required String songPath,
    required String title,
    required String artist,
    Uint8List? coverImageBytes,
  }) async {
    if (songPath.isEmpty) return;

    await _playback.switchToLocalEngine();
    _playback.setDuration(Duration.zero);
    await player.setFilePath(songPath);
    await player.seek(Duration.zero);
    await player.play();

    _playback.setArtist(artist);
    _playback.setArtistId(null);
    _playback.setSongName(title);
    _playback.setCurrentSongPath(songPath);
    _playback.setCoverImageBytes(coverImageBytes);
    _playback.setIsPlaying(true);
    _playback.setIsMuted(_playback.currentSliderValue == 0);
  }

  Future<void> _handlePlayPauseToggle() async {
    if (_playback.needsResumeLoad) {
      await _resumeRestoredSong();
      return;
    }
    _playback.togglePlayPause();
  }

  Future<void> _resumeRestoredSong() async {
    final path = _playback.currentSongPath;
    if (path == null || path.isEmpty) return;

    try {
      if (path.startsWith('yt:')) {
        final videoId = path.substring(3);
        await _playYouTubeSelection(
          videoId: videoId,
          title: _playback.songName,
          artist: _playback.artistName,
          artistId: _playback.currentArtistId ?? '',
          thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        );
        return;
      }

      await _playLocalSelection(
        songPath: path,
        title: _playback.songName,
        artist: _playback.artistName,
        coverImageBytes: _playback.coverImageBytes,
      );
    } catch (error) {
      if (!mounted) return;
      AppFlushbar.error(context, "Couldn't resume the last played song.");
    }
  }

  Future<void> _playRecentSong(Map<String, dynamic> item) async {
    final songPath = (item['songPath'] ?? '').toString();
    final title = (item['songTitle'] ?? 'Unknown song').toString();
    final artist = (item['songArtist'] ?? 'Unknown artist').toString();
    if (songPath.isEmpty) return;

    if (songPath.startsWith('yt:')) {
      final videoId = songPath.substring(3);
      final thumbnailUrl = (item['thumbnailUrl'] ?? '').toString();
      final artistId = (item['artistId'] ?? '').toString();
      await _playYouTubeSelection(
        videoId: videoId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        artistId: artistId,
      );
      return;
    }

    await _playLocalSelection(
      songPath: songPath,
      title: title,
      artist: artist,
      coverImageBytes: item['coverImageBytes'] as Uint8List?,
    );
  }

  Future<YTMusic> _ensureYtMusic() {
    _ytmusicFuture ??= YTMusic.create().then((ytmusic) {
      _ytmusic = ytmusic;
      return ytmusic;
    });
    return _ytmusicFuture!;
  }

  Future<void> _submitSearch() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) return;

    await _ensureYtMusic();
    if (!mounted) return;
    setState(() {
      _selectedTab = 'music_search';
      _selectedTabExtra = {'query': query};
    });
  }

  void _onPlaybackChanged() {
    final currentPath = _playback.currentSongPath;
    if (currentPath == null || currentPath.isEmpty) {
      return;
    }

    if (_lastTrackedSongPath == currentPath) {
      return;
    }

    _lastTrackedSongPath = currentPath;
    final derivedThumbnailUrl = currentPath.startsWith('yt:')
        ? 'https://i.ytimg.com/vi/${currentPath.substring(3)}/hqdefault.jpg'
        : '';
    if (!mounted) return;
    setState(() {
      _pushRecentItem(_recentPlayedSongs, <String, dynamic>{
        'songPath': currentPath,
        'songTitle': _playback.songName,
        'songArtist': _playback.artistName,
        'artistId': _playback.currentArtistId ?? '',
        'thumbnailUrl': derivedThumbnailUrl,
        'coverImageBytes': _playback.coverImageBytes,
      }, 'songPath');
    });
  }

  Future<List<String>> _resolvePlayableYouTubeStreamUrls(String videoId) async {
    final now = DateTime.now();
    final cached = _resolvedStreamsCache[videoId];
    if (cached != null &&
        cached.expiresAt.isAfter(now) &&
        cached.urls.isNotEmpty) {
      return cached.urls;
    }

    final inFlight = _resolvingStreamsByVideoId[videoId];
    if (inFlight != null) {
      return inFlight;
    }

    final resolveFuture = (() async {
      final manifest = await _youtubeExplode.videos.streamsClient.getManifest(
        videoId,
      );

      final candidates = <String>[];

      final mp4AudioOnly = manifest.audioOnly.where(
        (stream) => stream.container.name.toLowerCase() == 'mp4',
      );
      final otherAudioOnly = manifest.audioOnly.where(
        (stream) => stream.container.name.toLowerCase() != 'mp4',
      );
      final mp4Muxed = manifest.muxed.where(
        (stream) => stream.container.name.toLowerCase() == 'mp4',
      );
      final otherMuxed = manifest.muxed.where(
        (stream) => stream.container.name.toLowerCase() != 'mp4',
      );

      if (mp4Muxed.isNotEmpty) {
        candidates.add(mp4Muxed.withHighestBitrate().url.toString());
      }
      if (mp4AudioOnly.isNotEmpty) {
        candidates.add(mp4AudioOnly.withHighestBitrate().url.toString());
      }
      if (otherMuxed.isNotEmpty) {
        candidates.add(otherMuxed.withHighestBitrate().url.toString());
      }
      if (otherAudioOnly.isNotEmpty) {
        candidates.add(otherAudioOnly.withHighestBitrate().url.toString());
      }

      for (final stream in mp4Muxed) {
        candidates.add(stream.url.toString());
      }
      for (final stream in mp4AudioOnly) {
        candidates.add(stream.url.toString());
      }
      for (final stream in otherMuxed) {
        candidates.add(stream.url.toString());
      }
      for (final stream in otherAudioOnly) {
        candidates.add(stream.url.toString());
      }

      final deduped = <String>[];
      for (final candidate in candidates) {
        if (!deduped.contains(candidate)) {
          deduped.add(candidate);
        }
      }

      if (deduped.isEmpty) {
        throw Exception('No playable streams found for this video.');
      }

      _resolvedStreamsCache[videoId] = _YouTubeResolvedStreams(
        urls: deduped,
        expiresAt: DateTime.now().add(_resolvedStreamsTtl),
      );

      return deduped;
    })();

    _resolvingStreamsByVideoId[videoId] = resolveFuture;

    try {
      return await resolveFuture;
    } finally {
      _resolvingStreamsByVideoId.remove(videoId);
    }
  }

  Future<void> _prefetchYouTubeStreamUrls(String videoId) async {
    if (videoId.isEmpty) return;
    await _resolvePlayableYouTubeStreamUrls(videoId);
  }

  Future<void> _openYouTubeStream(
    String streamUrl, {
    Map<String, String>? headers,
  }) async {
    await player.setUrl(streamUrl, headers: headers);

    final effectivePercent = _playback.effectiveVolumePercent;
    await player.setVolume(effectivePercent / 100);
    _playback.setIsMuted(_playback.currentSliderValue == 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await player.play();
  }

  void _bindYouTubeEngineToPlayback() {
    _playback.bindYouTubeCallbacks(
      loadVideoById: (videoId) async {
        try {
          await player.pause();
        } catch (_) {}
        try {
          await player.stop();
        } catch (_) {}

        final streamUrls = await _resolvePlayableYouTubeStreamUrls(videoId);
        Object? lastError;

        for (final streamUrl in streamUrls) {
          try {
            await _openYouTubeStream(streamUrl, headers: _youtubeHttpHeaders);
            return;
          } catch (error) {
            lastError = error;
            try {
              await player.stop();
            } catch (_) {}
          }

          try {
            await _openYouTubeStream(streamUrl);
            return;
          } catch (error) {
            lastError = error;
            try {
              await player.stop();
            } catch (_) {}
          }
        }

        throw Exception(
          'Failed to open any playable stream for this video. $lastError',
        );
      },
      prefetchVideoById: _prefetchYouTubeStreamUrls,
      play: player.play,
      pause: player.pause,
      seek: player.seek,
      setVolume: (sliderValue) async {
        await player.setVolume(sliderValue.clamp(0, 100).toDouble() / 100);
      },
    );
  }

  Future<void> _onSidebarTabSelected(
    String tab, {
    Map<String, dynamic>? extra,
  }) async {
    if (tab == 'playlist_inspect') {
      _trackRecentPlaylist(extra);
    }

    if (!mounted) return;
    setState(() {
      _selectedTab = tab;
      _selectedTabExtra = extra;
    });
  }

  Widget _buildHomeSectionTitle(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRecentlyPlayedPlaylistsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeSectionTitle('Recently Played Playlists'),
        if (_recentPlayedPlaylists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'No playlists played yet.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _recentPlayedPlaylists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final item = _recentPlayedPlaylists[index];
                final title = item['playlistTitle'] ?? 'Playlist';
                final playlistId = item['playlistId'] ?? '';
                final thumbnailUrl = item['thumbnailUrl']?.toString() ?? '';
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: playlistId.isEmpty
                      ? null
                      : () => _onSidebarTabSelected(
                          'playlist_inspect',
                          extra: {
                            'playlistId': playlistId,
                            'playlistTitle': title,
                          },
                        ),
                  child: Container(
                    width: 220,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        thumbnailUrl.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  thumbnailUrl,
                                  width: 48,
                                  height: 48,
                                  cacheWidth: 96,
                                  cacheHeight: 96,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    Icons.queue_music_rounded,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              )
                            : Icon(
                                Icons.queue_music_rounded,
                                color: colorScheme.onSurface,
                              ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: colorScheme.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildRecentlyPlayedSongsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeSectionTitle('Recently Played Songs'),
        if (_recentPlayedSongs.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'No songs played yet.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ..._recentPlayedSongs.take(5).map((item) {
            final title = item['songTitle'] ?? 'Unknown song';
            final artist = item['songArtist'] ?? 'Unknown artist';
            final songPath = (item['songPath'] ?? '').toString();
            final thumbnailUrl = (item['thumbnailUrl'] ?? '').toString();
            final coverBytes = item['coverImageBytes'] as Uint8List?;
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: songPath.startsWith('yt:') && thumbnailUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            thumbnailUrl,
                            width: 56,
                            height: 56,
                            cacheWidth: 112,
                            cacheHeight: 112,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.music_note_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        )
                      : (coverBytes != null && coverBytes.isNotEmpty)
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.memory(
                            coverBytes,
                            width: 56,
                            height: 56,
                            cacheWidth: 112,
                            cacheHeight: 112,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
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
                  subtitle: Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  onTap: () => _playRecentSong(item),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildTrendingInDenmarkSection() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _buildHomeSectionTitle('Trending in Denmark')),
            IconButton(
              onPressed: _isLoadingTrendingInDenmark
                  ? null
                  : () => _loadTrendingInDenmark(),
              icon: Icon(Icons.refresh_rounded, color: colorScheme.onSurface),
              tooltip: 'Refresh trending',
            ),
          ],
        ),
        if (_isLoadingTrendingInDenmark)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_trendingInDenmarkError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'Failed to load trending songs: $_trendingInDenmarkError',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else if (_trendingInDenmark.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              'No trending songs found right now.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          ..._trendingInDenmark.take(5).map((item) {
            final title = item['title'] ?? 'Unknown song';
            final artist = item['artist'] ?? 'Unknown artist';
            final thumbnail = item['thumbnailUrl'] ?? '';
            final videoId = item['videoId'] ?? '';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: ListTile(
                  leading: thumbnail.isEmpty
                      ? Icon(
                          Icons.trending_up_rounded,
                          color: colorScheme.onSurface,
                        )
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            thumbnail,
                            width: 56,
                            height: 56,
                            cacheWidth: 112,
                            cacheHeight: 112,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) => Icon(
                              Icons.trending_up_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                  title: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  onTap: videoId.isEmpty
                      ? null
                      : () => _playYouTubeSelection(
                          videoId: videoId,
                          title: title,
                          artist: artist,
                          thumbnailUrl: thumbnail,
                        ),
                ),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildHomeDashboard() {
    final colorScheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Welcome back${userDisplayName == null ? '' : ', $userDisplayName'}',
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 18),
          _buildRecentlyPlayedPlaylistsSection(),
          const SizedBox(height: 18),
          _buildRecentlyPlayedSongsSection(),
          const SizedBox(height: 18),
          _buildTrendingInDenmarkSection(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    if (_selectedTab == 'music_search') {
      final query = (_selectedTabExtra?['query'] as String?) ?? '';
      if (query.trim().isEmpty) {
        return _buildHomeDashboard();
      }

      return MusicSearchResultsPage(
        query: query,
        ytmusicFuture: _ensureYtMusic(),
        onBack: () => _onSidebarTabSelected('home'),
        onPlaySong:
            ({
              required String videoId,
              required String title,
              required String artist,
              String thumbnailUrl = '',
              String artistId = '',
            }) async {
              await _playYouTubeSelection(
                videoId: videoId,
                title: title,
                artist: artist,
                thumbnailUrl: thumbnailUrl,
                artistId: artistId,
              );
            },
        onOpenArtist: (artistId, artistName) {
          _onSidebarTabSelected(
            'artist_details',
            extra: {
              'artistId': artistId,
              'artistName': artistName,
              'backTab': 'music_search',
              'backExtra': {'query': query},
            },
          );
        },
        onOpenAlbum: (albumId, albumTitle, artistId, artistName) {
          _onSidebarTabSelected(
            'album_details',
            extra: {
              'albumId': albumId,
              'albumTitle': albumTitle,
              'artistId': artistId,
              'artistName': artistName,
              'backTab': 'music_search',
              'backExtra': {'query': query},
            },
          );
        },
      );
    }

    if (_selectedTab == 'artist_details') {
      final artistId = (_selectedTabExtra?['artistId'] as String?) ?? '';
      final artistName =
          (_selectedTabExtra?['artistName'] as String?) ?? 'Artist';
      final backTab = (_selectedTabExtra?['backTab'] as String?) ?? 'home';
      final backExtra =
          _selectedTabExtra?['backExtra'] as Map<String, dynamic>?;

      if (artistId.isEmpty) {
        return _buildHomeDashboard();
      }

      return ArtistDetailsPage(
        artistId: artistId,
        artistName: artistName,
        ytmusicFuture: _ensureYtMusic(),
        onBack: () => _onSidebarTabSelected(backTab, extra: backExtra),
        onPlaySong:
            ({
              required String videoId,
              required String title,
              required String artist,
              String thumbnailUrl = '',
              String artistId = '',
            }) async {
              await _playYouTubeSelection(
                videoId: videoId,
                title: title,
                artist: artist,
                thumbnailUrl: thumbnailUrl,
                artistId: artistId,
              );
            },
        onOpenAlbum: (albumId, albumTitle, nextArtistId, nextArtistName) {
          _onSidebarTabSelected(
            'album_details',
            extra: {
              'albumId': albumId,
              'albumTitle': albumTitle,
              'artistId': nextArtistId,
              'artistName': nextArtistName,
              'backTab': 'artist_details',
              'backExtra': {
                'artistId': artistId,
                'artistName': artistName,
                'backTab': backTab,
                'backExtra': backExtra,
              },
            },
          );
        },
        onOpenArtist: (nextArtistId, nextArtistName) {
          _onSidebarTabSelected(
            'artist_details',
            extra: {
              'artistId': nextArtistId,
              'artistName': nextArtistName,
              'backTab': 'artist_details',
              'backExtra': {
                'artistId': artistId,
                'artistName': artistName,
                'backTab': backTab,
                'backExtra': backExtra,
              },
            },
          );
        },
      );
    }

    if (_selectedTab == 'album_details') {
      final albumId = (_selectedTabExtra?['albumId'] as String?) ?? '';
      final albumTitle =
          (_selectedTabExtra?['albumTitle'] as String?) ?? 'Album';
      final artistId = (_selectedTabExtra?['artistId'] as String?) ?? '';
      final artistName =
          (_selectedTabExtra?['artistName'] as String?) ?? 'Artist';
      final backTab = (_selectedTabExtra?['backTab'] as String?) ?? 'home';
      final backExtra =
          _selectedTabExtra?['backExtra'] as Map<String, dynamic>?;

      if (albumId.isEmpty) {
        return _buildHomeDashboard();
      }

      return AlbumDetailsPage(
        albumId: albumId,
        albumTitle: albumTitle,
        artistId: artistId,
        artistName: artistName,
        ytmusicFuture: _ensureYtMusic(),
        onBack: () {
          if (backTab == 'artist_details') {
            _onSidebarTabSelected('artist_details', extra: backExtra);
            return;
          }
          if (backTab == 'music_search') {
            _onSidebarTabSelected('music_search', extra: backExtra);
            return;
          }
          _onSidebarTabSelected('home');
        },
        onPlaySong:
            ({
              required String videoId,
              required String title,
              required String artist,
              String thumbnailUrl = '',
              String artistId = '',
            }) async {
              unawaited(
                _playYouTubeSelection(
                  videoId: videoId,
                  title: title,
                  artist: artist,
                  thumbnailUrl: thumbnailUrl,
                  artistId: artistId,
                ),
              );
            },
        onOpenArtist: (nextArtistId, nextArtistName) {
          _onSidebarTabSelected(
            'artist_details',
            extra: {
              'artistId': nextArtistId,
              'artistName': nextArtistName,
              'backTab': 'album_details',
              'backExtra': {
                'albumId': albumId,
                'albumTitle': albumTitle,
                'artistId': artistId,
                'artistName': artistName,
                'backTab': backTab,
                'backExtra': backExtra,
              },
            },
          );
        },
      );
    }

    if (_selectedTab == 'playlists') {
      return PlaylistsPage(onTabSelected: _onSidebarTabSelected);
    }

    if (_selectedTab == 'liked') {
      return const LikedPage();
    }

    if (_selectedTab == 'local_files') {
      return const LocalFilesPage();
    }

    if (_selectedTab == 'converter') {
      return const ConverterPage();
    }

    if (_selectedTab == 'settings') {
      return const SettingsPage();
    }

    if (_selectedTab == 'profile') {
      return const ProfilePage();
    }

    if (_selectedTab == 'playlist_inspect') {
      return PlaylistInspectPage(
        extra: _selectedTabExtra,
        onBack: () => _onSidebarTabSelected('playlists'),
        onOpenArtist: (artistId, artistName) {
          _onSidebarTabSelected(
            'artist_details',
            extra: {
              'artistId': artistId,
              'artistName': artistName,
              'backTab': 'playlist_inspect',
              'backExtra': _selectedTabExtra,
            },
          );
        },
      );
    }

    return _buildHomeDashboard();
  }

  @override
  void dispose() {
    _playback.removeListener(_onPlaybackChanged);
    _youtubeExplode.close();
    _ytmusic?.close();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null && mounted) {
      setState(() {
        userDisplayName = user.displayName ?? user.email;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _playback.switchToLocalEngine();
      await player.stop();
      _playback.setIsPlaying(false);
      _playback.setProgress(Duration.zero);
      _playback.setDuration(Duration.zero);
      _playback.setCurrentSongPath(null);
      _playback.clearPlaylistQueue();

      await GoogleAuthService.signOut();
      await _auth.signOut();
      if (!mounted) return;
      AppFlushbar.success(context, 'Logged out successfully.');
    } catch (error) {
      if (!mounted) return;
      AppFlushbar.error(context, 'Failed to log out: $error');
    }
  }

  String _queueTitle(dynamic item) {
    if (item is Map) {
      final v = item['songName'] ?? item['title'] ?? item['name'];
      if (v != null) return v.toString();
    }
    return item.toString();
  }

  String? _queueSubtitle(dynamic item) {
    if (item is Map) {
      final v = item['artistName'] ?? item['artist'] ?? item['author'];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString();
    }
    return null;
  }

  Future<void> _onQueueItemTap(int index) async {
    try {
      final dynamic model = _playback;
      await model.playQueueIndex(index);
    } catch (_) {}
  }

  void _openQueueSheet(BuildContext context, List<dynamic> queue) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSheet = colorScheme.onInverseSurface;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.inverseSurface,
      builder: (context) {
        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: queue.isEmpty
                ? Center(
                    child: Text(
                      'Queue is empty',
                      style: TextStyle(color: onSheet.withValues(alpha: 0.7)),
                    ),
                  )
                : ListView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Now Playing',
                          style: TextStyle(
                            color: onSheet,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final item = queue.first;
                          final subtitle = _queueSubtitle(item);
                          return Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              leading: Icon(
                                Icons.graphic_eq_rounded,
                                color: onSheet.withValues(alpha: 0.7),
                              ),
                              title: Text(
                                _queueTitle(item),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: onSheet),
                              ),
                              subtitle: subtitle == null
                                  ? null
                                  : Text(
                                      subtitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: onSheet.withValues(alpha: 0.7),
                                      ),
                                    ),
                            ),
                          );
                        },
                      ),
                      Divider(
                        color: onSheet.withValues(alpha: 0.12),
                        height: 1,
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Text(
                          'Up Next',
                          style: TextStyle(
                            color: onSheet,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (queue.length <= 1)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: Text(
                            'No songs up next.',
                            style: TextStyle(
                              color: onSheet.withValues(alpha: 0.7),
                            ),
                          ),
                        )
                      else
                        ...List.generate(queue.length - 1, (offset) {
                          final index = offset + 1;
                          final item = queue[index];
                          final subtitle = _queueSubtitle(item);
                          return Column(
                            children: [
                              Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  leading: Text(
                                    '$index',
                                    style: TextStyle(
                                      color: onSheet.withValues(alpha: 0.54),
                                    ),
                                  ),
                                  title: Text(
                                    _queueTitle(item),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(color: onSheet),
                                  ),
                                  subtitle: subtitle == null
                                      ? null
                                      : Text(
                                          subtitle,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            color: onSheet.withValues(
                                              alpha: 0.7,
                                            ),
                                          ),
                                        ),
                                  onTap: () async {
                                    Navigator.of(context).pop();
                                    await _onQueueItemTap(index);
                                  },
                                ),
                              ),
                              Divider(
                                color: onSheet.withValues(alpha: 0.12),
                                height: 1,
                              ),
                            ],
                          );
                        }),
                    ],
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surface,
      bottomNavigationBar: Consumer<PlaybackModel>(
        builder: (context, playback, child) {
          return PlaybackInterface(
            artist: playback.artistName,
            songName: playback.songName,
            progress: playback.progress,
            isPlaying: playback.isPlaying,
            isMuted: playback.isMuted,
            currentSliderValue: playback.currentSliderValue,
            onSeek: (duration) => playback.seekTo(duration),
            onPlayPauseToggle: _handlePlayPauseToggle,
            isShuffled: playback.isShuffled,
            isLooped: playback.isLooped,
            onPrevious: playback.playPrevious,
            onForward: playback.playNext,
            onVolumeChange: (value) => playback.applyVolume(value),
            duration: playback.duration,
            onShuffle: playback.toggleShuffle,
            onUnshuffle: playback.toggleShuffle,
            onLoop: playback.toggleLoop,
            onUnloop: playback.toggleLoop,
            queue: playback.queue,
            onQueuePressed: () => _openQueueSheet(context, playback.queue),
            onArtistTap:
                (playback.currentArtistId == null ||
                    playback.currentArtistId!.isEmpty)
                ? null
                : () => _onSidebarTabSelected(
                    'artist_details',
                    extra: {
                      'artistId': playback.currentArtistId,
                      'artistName': playback.artistName,
                      'backTab': _selectedTab,
                      'backExtra': _selectedTabExtra,
                    },
                  ),
          );
        },
      ),
      body: Row(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Sidebar(
              onTabSelected: _onSidebarTabSelected,
              videoCover: Video(
                controller: _sidebarVideoController,
                controls: NoVideoControls,
              ),
            ),
          ),
          Padding(padding: EdgeInsets.all(10)),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Row(
                        children: [
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedTab = 'home';
                              });
                            },
                            icon: Icon(
                              Icons.home_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(width: 10),
                          SizedBox(
                            width: MediaQuery.of(context).size.width - 465,
                            height: 45,
                            child: TextField(
                              controller: _searchController,
                              textInputAction: TextInputAction.search,
                              onSubmitted: (_) => _submitSearch(),
                              decoration: InputDecoration(
                                hintText: 'Search songs, artists or albums',
                                hintStyle: TextStyle(
                                  color: colorScheme.onSurface.withValues(
                                    alpha: 0.78,
                                  ),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: colorScheme.onSurface.withValues(
                                  alpha: 0.08,
                                ),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: colorScheme.onSurface,
                                    width: 1.0,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: colorScheme.onSurfaceVariant,
                                    width: 1.0,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    Icons.search_rounded,
                                    color: colorScheme.onSurface,
                                  ),
                                  onPressed: _submitSearch,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 10),
                          IconButton(
                            onPressed: () {
                              setState(() {
                                _selectedTab = 'settings';
                              });
                            },
                            icon: Icon(
                              Icons.settings_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(width: 10),
                          IconButton(
                            onPressed: () => setState(() {
                              _selectedTab = 'profile';
                            }),
                            icon: CircleAvatar(
                              backgroundImage: NetworkImage(
                                _auth.currentUser?.photoURL ?? '',
                              ),
                              radius: 20,
                            ),
                          ),
                          IconButton(
                            onPressed: _logout,
                            icon: Icon(
                              Icons.logout_rounded,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          SizedBox(width: 10),
                        ],
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Padding(
                      padding: EdgeInsets.all(10),
                      child: Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.all(Radius.circular(10)),
                        ),
                        width: MediaQuery.of(context).size.width - 260,
                        height: MediaQuery.of(context).size.height - 200,
                        child: _buildMainContent(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
