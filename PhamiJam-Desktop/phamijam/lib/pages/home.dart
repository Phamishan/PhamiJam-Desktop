import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/playback_interface.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/components/sidebar.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/widgets/playlist_inspect.dart';
import 'package:phamijam/widgets/playlists.dart';
import 'package:phamijam/widgets/liked.dart';
import 'package:phamijam/widgets/settings.dart';
import 'package:phamijam/widgets/local_files.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

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

  final yt.YoutubeExplode _youtubeExplode = yt.YoutubeExplode();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? userDisplayName;
  String _selectedTab = 'home';
  Map<String, dynamic>? _selectedTabExtra;
  final Map<String, _YouTubeResolvedStreams> _resolvedStreamsCache =
      <String, _YouTubeResolvedStreams>{};
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
    _checkCurrentUser();
  }

  Future<List<String>> _resolvePlayableYouTubeStreamUrls(String videoId) async {
    final now = DateTime.now();
    final cached = _resolvedStreamsCache[videoId];
    if (cached != null &&
        cached.expiresAt.isAfter(now) &&
        cached.urls.isNotEmpty) {
      return cached.urls;
    }

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
      expiresAt: now.add(_resolvedStreamsTtl),
    );

    return deduped;
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
    if (!mounted) return;
    setState(() {
      _selectedTab = tab;
      _selectedTabExtra = extra;
    });
  }

  Widget _buildMainContent() {
    if (_selectedTab == 'playlists') {
      return PlaylistsPage(onTabSelected: _onSidebarTabSelected);
    }

    if (_selectedTab == 'liked') {
      return const LikedPage();
    }

    if (_selectedTab == 'settings') {
      return const SettingsPage();
    }

    if (_selectedTab == 'local_files') {
      return const LocalFilesPage();
    }

    if (_selectedTab == 'playlist_inspect') {
      return PlaylistInspectPage(
        extra: _selectedTabExtra,
        onBack: () => _onSidebarTabSelected('playlists'),
      );
    }

    return Center(
      child: Text(
        'Logged in as: ${userDisplayName ?? 'Guest'}',
        style: const TextStyle(color: Colors.white, fontSize: 24),
        textAlign: TextAlign.center,
      ),
    );
  }

  @override
  void dispose() {
    _youtubeExplode.close();
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

  Future<void> _clearLoggedInCache() async {
    try {
      await GoogleAuthService.signOut();
      await _auth.signOut();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Logged-in cache cleared.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to clear cache: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFdba43a),
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
            onPlayPauseToggle: playback.togglePlayPause,
            onPrevious: playback.playPrevious,
            onForward: playback.playNext,
            onVolumeChange: (value) => playback.applyVolume(value),
            duration: playback.duration,
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
                            icon: Icon(Icons.home, color: Colors.white),
                          ),
                          SizedBox(width: 10),
                          SizedBox(
                            width: MediaQuery.of(context).size.width - 465,
                            height: 45,
                            child: TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                hintText: 'Search',
                                hintStyle: TextStyle(
                                  color: Colors.white.withAlpha(200),
                                  fontSize: 15,
                                ),
                                filled: true,
                                fillColor: Color.fromARGB(16, 217, 213, 207),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 14,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.white,
                                    width: 1.0,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.white70,
                                    width: 1.0,
                                  ),
                                ),
                                suffixIcon: IconButton(
                                  icon: Icon(Icons.search, color: Colors.white),
                                  onPressed: () => debugPrint(
                                    'Search: ${_searchController.text}',
                                  ),
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
                            icon: Icon(Icons.settings, color: Colors.white),
                          ),
                          SizedBox(width: 10),
                          IconButton(
                            onPressed: () => _auth.signOut(),
                            icon: CircleAvatar(
                              backgroundImage: NetworkImage(
                                _auth.currentUser?.photoURL ?? '',
                              ),
                              radius: 20,
                            ),
                          ),
                          IconButton(
                            onPressed: _clearLoggedInCache,
                            icon: Icon(Icons.logout, color: Colors.white),
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
                          color: Color(0xFFe2b661),
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
