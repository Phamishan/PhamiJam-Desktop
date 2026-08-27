import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:media_kit_video/media_kit_video.dart';
import 'package:phamijam/components/add_to_playlist_dialog.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/edit_song_dialog.dart';
import 'package:phamijam/components/playback_interface.dart';
import 'package:phamijam/pages/friend_profile_page.dart';
import 'package:phamijam/pages/friends_page.dart';
import 'package:phamijam/pages/fullscreen_video_page.dart';
import 'package:phamijam/pages/search_profiles_page.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/components/remote_session_banner.dart';
import 'package:phamijam/components/sidebar.dart';
import 'package:phamijam/components/sleep_timer_dialog.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/providers/liked_songs_provider.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/providers/profile_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/deep_link_service.dart';
import 'package:phamijam/services/download_service.dart';
import 'package:phamijam/services/drive_folder_service.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/services/google_drive_auth_service.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:phamijam/services/youtube_data_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:phamijam/widgets/converter.dart';
import 'package:phamijam/widgets/home_playlist_card.dart';
import 'package:phamijam/widgets/music_browse_pages.dart';
import 'package:phamijam/widgets/playlist_inspect.dart';
import 'package:phamijam/widgets/playlists.dart';
import 'package:phamijam/widgets/liked.dart';
import 'package:phamijam/widgets/profile.dart';
import 'package:phamijam/widgets/recent_artists_row.dart';
import 'package:phamijam/widgets/recent_track_card.dart';
import 'package:phamijam/widgets/settings.dart';
import 'package:phamijam/widgets/local_files.dart';
import 'package:phamijam/widgets/lyrics_sheet.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:provider/provider.dart';
import 'package:windows_taskbar/windows_taskbar.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class _YouTubeResolvedStreams {
  const _YouTubeResolvedStreams({required this.urls, required this.expiresAt});

  final List<String> urls;
  final DateTime expiresAt;
}

class Home extends StatefulWidget {
  const Home({super.key, this.pendingDeepLink});

  final DeepLinkTarget? pendingDeepLink;

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  late final TextEditingController _searchController;
  late final PlaybackModel _playback;
  late final DownloadsProvider _downloads;
  late final SettingsProvider _settings;
  late final VideoController _sidebarVideoController;
  Future<YTMusic>? _ytmusicFuture;
  YTMusic? _ytmusic;

  final yt.YoutubeExplode _youtubeExplode = yt.YoutubeExplode();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  String? userDisplayName;
  bool _avatarLoadFailed = false;
  String _selectedTab = 'home';
  Map<String, dynamic>? _selectedTabExtra;
  final Map<String, _YouTubeResolvedStreams> _resolvedStreamsCache =
      <String, _YouTubeResolvedStreams>{};
  final Map<String, Future<List<String>>> _resolvingStreamsByVideoId =
      <String, Future<List<String>>>{};
  List<PlayEvent> _recentlyPlayedTracks = <PlayEvent>[];
  List<Map<String, dynamic>> _myPlaylists = <Map<String, dynamic>>[];
  bool _isLoadingHomeDashboard = false;
  bool _showingSkipSuggestion = false;
  String? _homeDashboardError;
  String? _currentlyLoadingRecentVideoId;
  bool? _taskbarHasTrack;
  bool? _taskbarIsPlaying;
  StreamSubscription<DeepLinkTarget>? _deepLinkSubscription;
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
    _downloads = context.read<DownloadsProvider>();
    _downloads.resolveStreamUrls = _resolvePlayableYouTubeStreamUrls;
    _sidebarVideoController = VideoController(player.mediaKitPlayer);
    _searchController = TextEditingController();
    _bindYouTubeEngineToPlayback();
    _playback.bindEditedSongsLookup(
      context.read<EditedSongsProvider>().trimFor,
    );
    _playback.bindAutoplay(
      isEnabled: () => context.read<SettingsProvider>().autoplayEnabled,
      ensureYtMusic: _ensureYtMusic,
    );
    _settings = context.read<SettingsProvider>();
    _playback.setDiscordRichPresenceEnabled(
      _settings.discordRichPresenceEnabled,
    );
    _settings.addListener(_handleSettingsChanged);
    _checkCurrentUser();
    unawaited(_loadHomeDashboardData());
    unawaited(context.read<LikedSongsProvider>().refresh());
    unawaited(context.read<PlaylistPinProvider>().refresh());
    unawaited(context.read<EditedSongsProvider>().refresh());
    unawaited(context.read<SavedPlaylistsProvider>().refresh());
    unawaited(context.read<ProfileProvider>().refresh());
    context.read<FriendsProvider>().start();
    unawaited(context.read<SettingsProvider>().refreshHiddenPlaylists());
    final pendingDeepLink = widget.pendingDeepLink;
    if (pendingDeepLink != null && FirebaseAuth.instance.currentUser != null) {
      unawaited(_handleDeepLink(pendingDeepLink));
    }
    _deepLinkSubscription = DeepLinkService.incomingLinks.listen((target) {
      if (FirebaseAuth.instance.currentUser != null) {
        unawaited(_handleDeepLink(target));
      }
    });
    _playback.addListener(_handlePlaybackChanged);
    if (Platform.isWindows) {
      _playback.addListener(_updateTaskbarThumbnailToolbar);
      _updateTaskbarThumbnailToolbar();
    }
  }

  void _handlePlaybackChanged() {
    final song = _playback.suggestedRemovalSong;
    final playlistId = _playback.suggestedRemovalPlaylistId;
    if (song == null || playlistId == null || _showingSkipSuggestion) return;
    if (!context.read<SettingsProvider>().suggestRemovingSkippedSongs) {
      _playback.dismissSkipSuggestion();
      return;
    }
    _showingSkipSuggestion = true;
    _showSkipSuggestionDialog(
      song,
      playlistId,
      _playback.suggestedRemovalPlaylistTitle ?? 'this playlist',
    ).whenComplete(() {
      _showingSkipSuggestion = false;
    });
  }

  void _updateTaskbarThumbnailToolbar() {
    final hasTrack = (_playback.currentSongPath ?? '').isNotEmpty;
    final isPlaying = _playback.isPlaying;
    if (_taskbarHasTrack == hasTrack && _taskbarIsPlaying == isPlaying) {
      return;
    }
    _taskbarHasTrack = hasTrack;
    _taskbarIsPlaying = isPlaying;

    if (!hasTrack) {
      WindowsTaskbar.resetThumbnailToolbar();
      return;
    }

    WindowsTaskbar.setThumbnailToolbar([
      ThumbnailToolbarButton(
        ThumbnailToolbarAssetIcon('assets/icons/taskbar/previous.ico'),
        'Previous',
        () => _playback.playPrevious(),
      ),
      ThumbnailToolbarButton(
        ThumbnailToolbarAssetIcon(
          isPlaying
              ? 'assets/icons/taskbar/pause.ico'
              : 'assets/icons/taskbar/play.ico',
        ),
        isPlaying ? 'Pause' : 'Play',
        () => _handlePlayPauseToggle(),
      ),
      ThumbnailToolbarButton(
        ThumbnailToolbarAssetIcon('assets/icons/taskbar/next.ico'),
        'Next',
        () => _playback.playNext(),
      ),
    ]);
  }

  Future<void> _showSkipSuggestionDialog(
    Map<String, dynamic> song,
    String playlistId,
    String playlistTitle,
  ) async {
    final title = (song['title'] as String?) ?? 'This song';
    final remove = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Skipping this a lot?'),
        content: Text(
          'You\'ve skipped "$title" early several times in "$playlistTitle". '
          'Remove it from the playlist?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    await _playback.dismissSkipSuggestion();
    if (remove != true || !mounted) return;

    final videoId = (song['videoId'] as String?) ?? '';
    if (videoId.isEmpty) return;
    try {
      final itemIds = await YoutubePlaylistService.fetchPlaylistItemIds(
        playlistId,
      );
      final itemId = itemIds[videoId];
      if (itemId == null) {
        throw Exception('This song is no longer in the playlist.');
      }
      await YoutubePlaylistService.removeVideoFromPlaylist(itemId);
      if (mounted) AppFlushbar.success(context, 'Removed "$title"');
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't remove track: $error");
      }
    }
  }

  Future<void> _loadHomeDashboardData({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() {
      _isLoadingHomeDashboard = true;
      _homeDashboardError = null;
    });

    try {
      final since = DateTime.now().subtract(const Duration(days: 180));
      final results = await Future.wait([
        ListeningHistoryService.eventsSince(since),
        YoutubePlaylistService.fetchMyPlaylists(),
      ]);
      final events = results[0] as List<PlayEvent>;
      final playlists = results[1] as List<Map<String, dynamic>>;

      final seen = <String>{};
      final recent = <PlayEvent>[];
      for (final event in events.reversed) {
        if (!seen.add(event.videoId)) continue;
        recent.add(event);
        if (recent.length >= 15) break;
      }

      if (!mounted) return;
      setState(() {
        _recentlyPlayedTracks = recent;
        _myPlaylists = playlists;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _homeDashboardError = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingHomeDashboard = false;
        });
      }
    }
  }

  Future<void> _playRecentlyPlayedTrack(int index) async {
    if (index < 0 || index >= _recentlyPlayedTracks.length) return;
    if (_currentlyLoadingRecentVideoId != null) return;
    final event = _recentlyPlayedTracks[index];
    if (event.videoId.isEmpty) return;

    setState(() => _currentlyLoadingRecentVideoId = event.videoId);
    try {
      await _playYouTubeSelection(
        videoId: event.videoId,
        title: event.title,
        artist: event.artist,
        thumbnailUrl: event.thumbnailUrl,
        artistId: event.channelId ?? '',
      );
      _playback.setPlaylistQueue([
        for (final e in _recentlyPlayedTracks) _playEventToSongMap(e),
      ], startIndex: index);
      _registerRecentlyPlayedQueueHandlers();
    } finally {
      if (mounted) setState(() => _currentlyLoadingRecentVideoId = null);
    }
  }

  Map<String, dynamic> _playEventToSongMap(PlayEvent event) => {
    'videoId': event.videoId,
    'title': event.title,
    'artist': event.artist,
    'artistId': event.channelId,
    'thumbnailUrl': event.thumbnailUrl,
    'durationSeconds': 0,
  };

  void _handleRecentTrackMenuSelection(String value, PlayEvent event) {
    if (event.videoId.isEmpty) {
      AppFlushbar.error(context, 'This song is unavailable.');
      return;
    }
    switch (value) {
      case 'play_next':
        _playback.addToQueue(_playEventToSongMap(event));
        AppFlushbar.info(context, '"${event.title}" will play next.');
      case 'add_to_queue':
        _playback.appendToQueue(_playEventToSongMap(event));
        AppFlushbar.info(context, '"${event.title}" added to queue.');
      case 'add_to_playlist':
        showAddToPlaylistDialog(
          context,
          videoId: event.videoId,
          songTitle: event.title,
        );
      case 'download':
        _downloads.download(
          videoId: event.videoId,
          songName: event.title,
          artistName: event.artist,
          artistId: event.channelId,
        );
      case 'remove_download':
        _downloads.remove(event.videoId);
      case 'edit_trim':
        showEditSongDialog(
          context,
          videoId: event.videoId,
          title: event.title,
          artist: event.artist,
          thumbnailUrl: event.thumbnailUrl,
        );
      case 'share':
        ShareLinkService.shareSong(context, event.videoId);
    }
  }

  void _handleVideoPreviewMenuSelection(String value) {
    final videoId = _playback.currentYouTubeVideoId;
    if (videoId == null || videoId.isEmpty) {
      AppFlushbar.error(context, 'This song is unavailable.');
      return;
    }
    final title = _playback.songName;
    final artist = _playback.artistName;
    switch (value) {
      case 'toggle_like':
        context.read<LikedSongsProvider>().toggleLike({
          'videoId': videoId,
          'title': title,
          'artist': artist,
          'artistId': _playback.currentArtistId,
          'thumbnailUrl': 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        });
      case 'add_to_playlist':
        showAddToPlaylistDialog(context, videoId: videoId, songTitle: title);
      case 'download':
        _downloads.download(
          videoId: videoId,
          songName: title,
          artistName: artist,
          artistId: _playback.currentArtistId,
        );
      case 'remove_download':
        _downloads.remove(videoId);
      case 'edit_trim':
        showEditSongDialog(
          context,
          videoId: videoId,
          title: title,
          artist: artist,
          thumbnailUrl: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
        );
      case 'share':
        ShareLinkService.shareSong(context, videoId);
    }
  }

  void _registerRecentlyPlayedQueueHandlers() {
    final songs = [
      for (final e in _recentlyPlayedTracks) _playEventToSongMap(e),
    ];
    _playback.setQueueHandlers(
      playAtSourceIndex: (sourceIndex) async {
        if (sourceIndex < 0 || sourceIndex >= songs.length) return;
        final song = songs[sourceIndex];
        final videoId = (song['videoId'] as String?) ?? '';
        if (videoId.isEmpty) return;
        await _playYouTubeSelection(
          videoId: videoId,
          title: (song['title'] as String?) ?? 'Unknown song',
          artist: (song['artist'] as String?) ?? 'Unknown artist',
          thumbnailUrl: (song['thumbnailUrl'] as String?) ?? '',
          artistId: (song['artistId'] as String?) ?? '',
        );
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
    bool detachFromQueue = false,
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

    if (detachFromQueue) {
      _playback.setPlaylistQueue([
        {
          'videoId': videoId,
          'title': title,
          'artist': artist,
          'artistId': artistId,
          'thumbnailUrl': thumbnailUrl,
        },
      ], startIndex: 0);
    }
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
      if (_playback.hasRestorableQueue) {
        try {
          await _playback.resumeRestoredQueue();
        } catch (error) {
          if (mounted) {
            AppFlushbar.error(context, "Couldn't resume the last played song.");
          }
        }
      } else {
        await _resumeRestoredSong();
      }
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

  Future<void> _openDownloadedFile(String path) async {
    final start = _playback.trimStart;
    await player.setFilePath(
      path,
      start: start != null && start > Duration.zero ? start : null,
    );
    final effectivePercent = _playback.effectiveVolumePercent;
    await player.setVolume(effectivePercent / 100);
    _playback.setIsMuted(_playback.currentSliderValue == 0);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await player.play();
  }

  Future<void> _openYouTubeStream(
    String streamUrl, {
    Map<String, String>? headers,
  }) async {
    final start = _playback.trimStart;
    await player.setUrl(
      streamUrl,
      headers: headers,
      start: start != null && start > Duration.zero ? start : null,
    );

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

        final localPath = _downloads.localPathFor(videoId);
        if (localPath != null) {
          await _openDownloadedFile(localPath);
          return;
        }

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

  Future<void> _handleDeepLink(DeepLinkTarget target) async {
    try {
      if (target.type == DeepLinkType.song) {
        final video = await YoutubeDataService.fetchVideoById(target.id);
        if (video == null || !mounted) return;
        await _playYouTubeSelection(
          videoId: target.id,
          title: video['title'] as String? ?? '',
          artist: video['artist'] as String? ?? '',
          thumbnailUrl: video['thumbnailUrl'] as String? ?? '',
          artistId: video['artistId'] as String? ?? '',
          detachFromQueue: true,
        );
        return;
      }

      if (target.type == DeepLinkType.profile) {
        final resolvedUid = await ProfileService.resolveProfileLinkId(
          target.id,
        );
        if (!mounted) return;
        final ownUid = FirebaseAuth.instance.currentUser?.uid;
        _onSidebarTabSelected(
          resolvedUid == ownUid ? 'profile' : 'friend_profile',
          extra: resolvedUid == ownUid ? null : {'uid': resolvedUid},
        );
        return;
      }

      final playlist = await YoutubePlaylistService.fetchPlaylistMetadata(
        target.id,
      );
      if (playlist == null || !mounted) return;
      _onSidebarTabSelected(
        'playlist_inspect',
        extra: {
          'playlistId': target.id,
          'playlistTitle': playlist['title'],
          'thumbnailUrl': playlist['thumbnailUrl'],
        },
      );
    } catch (error) {
      if (mounted) {
        AppFlushbar.error(context, "Couldn't open the shared link.");
      }
    }
  }

  Widget _buildHomeSectionTitle(String title, {VoidCallback? onSeeAll}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: colorScheme.onSurface,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.onSurfaceVariant,
              ),
              child: const Text('See all'),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentArtistsSection() {
    if (_recentlyPlayedTracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeSectionTitle('Recently Played Artists'),
        RecentArtistsRow(
          events: _recentlyPlayedTracks,
          maxArtists: _recentlyPlayedTracks.length,
          onOpenArtist: (channelId, artistName) {
            _onSidebarTabSelected(
              'artist_details',
              extra: {
                'artistId': channelId,
                'artistName': artistName,
                'backTab': 'home',
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildYourPlaylistsSection() {
    final colorScheme = Theme.of(context).colorScheme;
    final pins = context.watch<PlaylistPinProvider>();
    final settings = context.watch<SettingsProvider>();
    final visibleMyPlaylists = _myPlaylists
        .where(
          (p) => !settings.isPlaylistHidden((p['playlistId'] as String?) ?? ''),
        )
        .toList();
    final playlists = pins.sortByPin(visibleMyPlaylists);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeSectionTitle(
          'Your Playlists',
          onSeeAll: () => _onSidebarTabSelected('playlists'),
        ),
        if (playlists.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'No playlists yet.',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          )
        else
          SizedBox(
            height: 240,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: playlists.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final playlist = playlists[index];
                final playlistId = playlist['playlistId'] as String?;
                return HomePlaylistCard(
                  playlist: playlist,
                  isPinned: playlistId != null && pins.isPinned(playlistId),
                  onTogglePin: playlistId == null
                      ? null
                      : () => pins.togglePin(playlistId),
                  onEdited: playlistId == null
                      ? null
                      : (title, description, privacyStatus) {
                          setState(() {
                            playlist['title'] = title;
                            playlist['description'] = description;
                            playlist['privacyStatus'] = privacyStatus;
                          });
                        },
                  onDeleted: playlistId == null
                      ? null
                      : () {
                          setState(() {
                            _myPlaylists.removeWhere(
                              (p) => (p['playlistId'] as String?) == playlistId,
                            );
                          });
                        },
                  onTap: () => _onSidebarTabSelected(
                    'playlist_inspect',
                    extra: {
                      'playlistId': playlist['playlistId'],
                      'playlistTitle': playlist['title'],
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _buildJumpBackInSection() {
    if (_recentlyPlayedTracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHomeSectionTitle('Jump Back In'),
        SizedBox(
          height: 210,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _recentlyPlayedTracks.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final event = _recentlyPlayedTracks[index];
              return Builder(
                builder: (context) {
                  final likedSongs = context.watch<LikedSongsProvider>();
                  final downloads = context.watch<DownloadsProvider>();
                  final isCurrentSong = context.select<PlaybackModel, bool>(
                    (playback) =>
                        playback.currentSongPath == 'yt:${event.videoId}',
                  );
                  final isDownloaded = downloads.isDownloaded(event.videoId);
                  return RecentTrackCard(
                    event: event,
                    isActive: isCurrentSong,
                    onTap: () => _playRecentlyPlayedTrack(index),
                    menuEntries: [
                      (
                        value: 'play_next',
                        icon: Icons.playlist_play_rounded,
                        label: 'Add to play next',
                      ),
                      (
                        value: 'add_to_queue',
                        icon: Icons.queue_music_rounded,
                        label: 'Add to queue',
                      ),
                      (
                        value: 'add_to_playlist',
                        icon: Icons.playlist_add_rounded,
                        label: 'Add to playlist',
                      ),
                      (
                        value: isDownloaded ? 'remove_download' : 'download',
                        icon: isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                        label: isDownloaded ? 'Remove download' : 'Download',
                      ),
                      (
                        value: 'edit_trim',
                        icon: Icons.content_cut_rounded,
                        label: 'Edit song',
                      ),
                      (
                        value: 'share',
                        icon: Icons.share_rounded,
                        label: 'Share',
                      ),
                    ],
                    onMenuSelected: (value) =>
                        _handleRecentTrackMenuSelection(value, event),
                    isLiked: likedSongs.isLiked(event.videoId),
                    onToggleLike: () =>
                        likedSongs.toggleLike(_playEventToSongMap(event)),
                    isDownloaded: isDownloaded,
                    onToggleDownload: () {
                      if (isDownloaded) {
                        downloads.remove(event.videoId);
                      } else {
                        downloads.download(
                          videoId: event.videoId,
                          songName: event.title,
                          artistName: event.artist,
                          artistId: event.channelId,
                        );
                      }
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHomeDashboard() {
    final colorScheme = Theme.of(context).colorScheme;
    final isEmpty = _recentlyPlayedTracks.isEmpty && _myPlaylists.isEmpty;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Welcome back${userDisplayName == null ? '' : ', $userDisplayName'}',
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              IconButton(
                onPressed: _isLoadingHomeDashboard
                    ? null
                    : () => _loadHomeDashboardData(forceRefresh: true),
                icon: Icon(Icons.refresh_rounded, color: colorScheme.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (_isLoadingHomeDashboard && isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_homeDashboardError != null && isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text(
                'Failed to load your home page: $_homeDashboardError',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            )
          else ...[
            _buildRecentArtistsSection(),
            if (_recentlyPlayedTracks.isNotEmpty) const SizedBox(height: 24),
            _buildYourPlaylistsSection(),
            const SizedBox(height: 24),
            _buildJumpBackInSection(),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchEngineToggle(SearchEngine searchEngine) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: SegmentedButton<SearchEngine>(
          segments: const [
            ButtonSegment(
              value: SearchEngine.youtubeMusic,
              label: Text('YouTube Music'),
              icon: Icon(Icons.music_note_rounded),
            ),
            ButtonSegment(
              value: SearchEngine.youtube,
              label: Text('YouTube'),
              icon: Icon(Icons.smart_display_rounded),
            ),
          ],
          selected: {searchEngine},
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.12),
            foregroundColor: colorScheme.onSurfaceVariant,
            selectedBackgroundColor: colorScheme.primary,
            selectedForegroundColor: colorScheme.onPrimary,
          ),
          onSelectionChanged: (selection) =>
              context.read<SettingsProvider>().setSearchEngine(selection.first),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    final searchEngine = context.watch<SettingsProvider>().searchEngine;

    if (_selectedTab == 'music_search') {
      final query = (_selectedTabExtra?['query'] as String?) ?? '';
      if (query.trim().isEmpty) {
        return _buildHomeDashboard();
      }

      final resultsPage = searchEngine == SearchEngine.youtube
          ? YoutubeSearchResultsPage(
              query: query,
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
                      detachFromQueue: true,
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
            )
          : MusicSearchResultsPage(
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
                      detachFromQueue: true,
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

      return Column(
        children: [
          _buildSearchEngineToggle(searchEngine),
          Expanded(child: resultsPage),
        ],
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

      if (searchEngine == SearchEngine.youtube) {
        return YoutubeChannelDetailsPage(
          channelId: artistId,
          channelName: artistName,
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
                  detachFromQueue: true,
                );
              },
        );
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
                detachFromQueue: true,
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
                  detachFromQueue: true,
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
      return LikedPage(
        onOpenArtist: (artistId, artistName) {
          _onSidebarTabSelected(
            'artist_details',
            extra: {
              'artistId': artistId,
              'artistName': artistName,
              'backTab': 'liked',
            },
          );
        },
      );
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
      return ProfilePage(onTabSelected: _onSidebarTabSelected);
    }

    if (_selectedTab == 'friends') {
      return FriendsPage(onTabSelected: _onSidebarTabSelected);
    }

    if (_selectedTab == 'friend_profile') {
      final uid = (_selectedTabExtra?['uid'] as String?) ?? '';
      return FriendProfilePage(uid: uid, onTabSelected: _onSidebarTabSelected);
    }

    if (_selectedTab == 'search_profiles') {
      return SearchProfilesPage(onTabSelected: _onSidebarTabSelected);
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
    _deepLinkSubscription?.cancel();
    _playback.removeListener(_handlePlaybackChanged);
    if (Platform.isWindows) {
      _playback.removeListener(_updateTaskbarThumbnailToolbar);
      WindowsTaskbar.resetThumbnailToolbar();
    }
    _settings.removeListener(_handleSettingsChanged);
    _youtubeExplode.close();
    _ytmusic?.close();
    _searchController.dispose();
    context.read<FriendsProvider>().stop();
    super.dispose();
  }

  void _handleSettingsChanged() {
    _playback.setDiscordRichPresenceEnabled(
      _settings.discordRichPresenceEnabled,
    );
  }

  Future<void> _checkCurrentUser() async {
    final user = _auth.currentUser;
    if (user != null && mounted) {
      setState(() {
        userDisplayName = user.displayName ?? user.email;
        _avatarLoadFailed = false;
      });
    }
  }

  Future<void> _logout() async {
    try {
      await _playback.switchToLocalEngine().timeout(const Duration(seconds: 5));
      await player.stop().timeout(const Duration(seconds: 5));
    } catch (_) {}
    _playback.setIsPlaying(false);
    _playback.setProgress(Duration.zero);
    _playback.setDuration(Duration.zero);
    _playback.setCurrentSongPath(null);
    _playback.clearPlaylistQueue();

    try {
      await GoogleAuthService.signOut().timeout(const Duration(seconds: 5));
    } catch (_) {}
    try {
      await GoogleDriveAuthService.signOut().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}
    try {
      await DriveFolderService.clearFolderId().timeout(
        const Duration(seconds: 5),
      );
    } catch (_) {}

    try {
      await _auth.signOut();
      PlaylistsPage.resetCache();
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

  void _openLyricsSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.inverseSurface,
      builder: (context) => const LyricsSheet(),
    );
  }

  void _openQueueSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSheet = colorScheme.onInverseSurface;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.inverseSurface,
      builder: (context) {
        return Consumer<PlaybackModel>(
          builder: (context, playback, _) {
            final remote = playback.isRemoteControlling
                ? playback.remoteSession
                : null;
            final queue = remote != null ? remote.queue : playback.queue;
            final canRemove = remote == null;
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.6,
                child: queue.isEmpty
                    ? Center(
                        child: Text(
                          'Queue is empty',
                          style: TextStyle(
                            color: onSheet.withValues(alpha: 0.7),
                          ),
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
                                            color: onSheet.withValues(
                                              alpha: 0.7,
                                            ),
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
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Up Next',
                                    style: TextStyle(
                                      color: onSheet,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (canRemove && queue.length > 1)
                                  TextButton.icon(
                                    onPressed: () {
                                      playback.clearUpNextQueue();
                                      AppFlushbar.success(
                                        context,
                                        'Queue cleared',
                                      );
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor: onSheet,
                                    ),
                                    icon: const Icon(
                                      Icons.playlist_remove_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Clear'),
                                  ),
                              ],
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
                          else if (canRemove)
                            ReorderableListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              buildDefaultDragHandles: false,
                              itemCount: queue.length - 1,
                              onReorderItem: (oldIndex, newIndex) {
                                playback.reorderQueue(
                                  oldIndex + 1,
                                  newIndex + 1,
                                );
                              },
                              itemBuilder: (context, offset) {
                                final index = offset + 1;
                                final item = queue[index];
                                final subtitle = _queueSubtitle(item);
                                return Column(
                                  key: ValueKey('queue-item-$index'),
                                  children: [
                                    Material(
                                      type: MaterialType.transparency,
                                      child: ListTile(
                                        leading: Text(
                                          '$index',
                                          style: TextStyle(
                                            color: onSheet.withValues(
                                              alpha: 0.54,
                                            ),
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
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(
                                                Icons.close_rounded,
                                                color: onSheet.withValues(
                                                  alpha: 0.7,
                                                ),
                                              ),
                                              onPressed: () => playback
                                                  .removeFromQueue(index),
                                            ),
                                            ReorderableDragStartListener(
                                              index: offset,
                                              child: Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 4,
                                                    ),
                                                child: Icon(
                                                  Icons.drag_handle_rounded,
                                                  color: onSheet.withValues(
                                                    alpha: 0.7,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
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
                              },
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
                                          color: onSheet.withValues(
                                            alpha: 0.54,
                                          ),
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
          final remote = playback.isRemoteControlling
              ? playback.remoteSession
              : null;
          final remoteTrack = remote?.currentTrack;
          final artistId = remote != null
              ? (remoteTrack?['artistId'] as String?)
              : playback.currentArtistId;

          return PlaybackInterface(
            artist: remote != null
                ? (remoteTrack?['artistName'] as String? ?? '')
                : playback.artistName,
            songName: remote != null
                ? (remoteTrack?['songName'] as String? ?? '')
                : playback.songName,
            progress: remote?.position ?? playback.progress,
            isPlaying: remote?.isPlaying ?? playback.isPlaying,
            isMuted: playback.isMuted,
            currentSliderValue: remote != null
                ? (remote.volume * 100).clamp(0, 100).toDouble()
                : playback.currentSliderValue,
            onSeek: (duration) => playback.seekTo(duration),
            onPlayPauseToggle: _handlePlayPauseToggle,
            isShuffled: remote?.shuffle ?? playback.isShuffled,
            repeatMode: remote != null
                ? PlayerRepeatMode.values.firstWhere(
                    (mode) => mode.name == remote.repeatMode,
                    orElse: () => PlayerRepeatMode.off,
                  )
                : playback.repeatMode,
            onPrevious: playback.playPrevious,
            onForward: playback.playNext,
            onVolumeChange: (value) => playback.applyVolume(value),
            duration: remote != null
                ? Duration(
                    seconds: remoteTrack?['durationSeconds'] as int? ?? 0,
                  )
                : playback.duration,
            onShuffle: playback.toggleShuffle,
            onUnshuffle: playback.toggleShuffle,
            onCycleRepeat: playback.cycleRepeatMode,
            queue: remote != null ? remote.queue : playback.queue,
            onQueuePressed: () => _openQueueSheet(context),
            onLyricsPressed:
                (remote != null ||
                    (playback.currentYouTubeVideoId ?? '').isEmpty)
                ? null
                : () => _openLyricsSheet(context),
            onArtistTap: (artistId == null || artistId.isEmpty)
                ? null
                : () => _onSidebarTabSelected(
                    'artist_details',
                    extra: {
                      'artistId': artistId,
                      'artistName': remote != null
                          ? (remoteTrack?['artistName'] as String? ?? '')
                          : playback.artistName,
                      'backTab': _selectedTab,
                      'backExtra': _selectedTabExtra,
                    },
                  ),
            onSleepTimerPressed: remote != null
                ? null
                : () => showSleepTimerDialog(context),
            onSharePressed:
                (remote != null ||
                    (playback.currentYouTubeVideoId ?? '').isEmpty)
                ? null
                : () => ShareLinkService.shareSong(
                    context,
                    playback.currentYouTubeVideoId!,
                  ),
            onSharePlaylistPressed:
                (remote != null ||
                    playback.sourcePlaylistId == null ||
                    playback.isSourcePlaylistPrivate)
                ? null
                : () => ShareLinkService.sharePlaylist(
                    context,
                    playback.sourcePlaylistId!,
                  ),
            hasSleepTimer: playback.hasSleepTimer,
          );
        },
      ),
      body: Row(
        children: [
          Align(
            alignment: Alignment.topLeft,
            child: Sidebar(
              onTabSelected: _onSidebarTabSelected,
              videoCover: Consumer<DownloadsProvider>(
                builder: (context, downloads, child) {
                  final isDownloaded = downloads.isDownloaded(
                    _playback.currentYouTubeVideoId ?? '',
                  );
                  final isLiked = context.watch<LikedSongsProvider>().isLiked(
                    _playback.currentYouTubeVideoId ?? '',
                  );
                  return ContextMenuRegion<String>(
                    contextMenu: ContextMenu(
                      borderRadius: BorderRadius.circular(12),
                      entries: [
                        MenuItem<String>(
                          value: 'toggle_like',
                          icon: Icon(
                            isLiked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                          ),
                          label: Text(
                            isLiked
                                ? 'Remove from Liked Songs'
                                : 'Add to Liked Songs',
                          ),
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
                          label: Text(
                            isDownloaded ? 'Remove download' : 'Download',
                          ),
                        ),
                        MenuItem<String>(
                          value: 'edit_trim',
                          icon: const Icon(Icons.content_cut_rounded),
                          label: const Text('Edit song'),
                        ),
                        MenuItem<String>(
                          value: 'share',
                          icon: const Icon(Icons.share_rounded),
                          label: const Text('Share'),
                        ),
                      ],
                    ),
                    onItemSelected: (value) {
                      if (value != null) {
                        _handleVideoPreviewMenuSelection(value);
                      }
                    },
                    child: child,
                  );
                },
                child: Video(
                  controller: _sidebarVideoController,
                  controls: NoVideoControls,
                ),
              ),
              onOpenFullscreenVideo: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FullscreenVideoPage(),
                  fullscreenDialog: true,
                ),
              ),
            ),
          ),
          Padding(padding: EdgeInsets.all(10)),
          Expanded(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Padding(
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
                            Expanded(
                              child: SizedBox(
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
                            Consumer<FriendsProvider>(
                              builder: (context, friendsProvider, _) {
                                final icon = Icon(
                                  Icons.people_alt_rounded,
                                  color: colorScheme.onSurface,
                                );
                                return IconButton(
                                  onPressed: () => setState(() {
                                    _selectedTab = 'friends';
                                  }),
                                  icon: friendsProvider.received.isNotEmpty
                                      ? Badge(child: icon)
                                      : icon,
                                );
                              },
                            ),
                            SizedBox(width: 10),
                            IconButton(
                              onPressed: () => setState(() {
                                _selectedTab = 'profile';
                              }),
                              icon: Builder(
                                builder: (context) {
                                  final photoUrl = _auth.currentUser?.photoURL;
                                  final showPhoto =
                                      photoUrl != null &&
                                      photoUrl.isNotEmpty &&
                                      !_avatarLoadFailed;
                                  return CircleAvatar(
                                    radius: 20,
                                    backgroundImage: showPhoto
                                        ? NetworkImage(photoUrl)
                                        : null,
                                    onBackgroundImageError: showPhoto
                                        ? (error, stackTrace) {
                                            if (!mounted) return;
                                            setState(
                                              () => _avatarLoadFailed = true,
                                            );
                                          }
                                        : null,
                                    child: showPhoto
                                        ? null
                                        : Icon(
                                            Icons.person_rounded,
                                            color: colorScheme.onSurface,
                                          ),
                                  );
                                },
                              ),
                            ),
                            SizedBox(width: 10),
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
                    ),
                  ],
                ),
                const RemoteSessionBanner(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Padding(
                        padding: EdgeInsets.all(10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.all(Radius.circular(10)),
                          ),
                          width: MediaQuery.of(context).size.width - 260,
                          child: _buildMainContent(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
