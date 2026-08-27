import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/services/drive_duration_cache_service.dart';
import 'package:phamijam/services/google_drive_service.dart'
    show driveTrackIdPrefix;
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/playback_session_sync_service.dart';
import 'package:phamijam/services/playback_state_service.dart';
import 'package:phamijam/services/autoplay_service.dart';
import 'package:phamijam/services/skip_tracking_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

enum PlaybackEngine { local, youtube }

enum PlayerRepeatMode { off, all, one }

class PlaybackModel extends ChangeNotifier {
  static const int _queueAheadCount = 4;
  static const int _queueDisplayAheadCount = 20;
  static const Duration _discordPresenceDebounce = Duration(milliseconds: 50);
  static const String _prefsSongNameKey = 'phamijam.last_song_name';
  static const String _prefsArtistNameKey = 'phamijam.last_artist_name';
  static const String _prefsArtistIdKey = 'phamijam.last_artist_id';
  static const String _prefsSongPathKey = 'phamijam.last_song_path';
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<AppPlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<bool>? _completedSubscription;
  Timer? _discordPresenceTimer;
  bool _isBoundToPlayer = false;
  bool _completionHandledForCurrentTrack = false;
  bool _wasPlaying = false;
  PlaybackEngine _engine = PlaybackEngine.local;
  DiscordRPC? _discordRpc;
  bool _discordRpcReady = false;
  bool _discordRichPresenceEnabled = false;
  String? _lastDiscordPresenceSignature;
  Future<void>? _discordReconnectFuture;

  Future<void> Function(String videoId)? _youtubeLoadVideoById;
  Future<void> Function(String videoId)? _youtubePrefetchVideoById;
  Future<void> Function()? _youtubePlay;
  Future<void> Function()? _youtubePause;
  Future<void> Function(Duration position)? _youtubeSeek;
  Future<void> Function(double sliderValue)? _youtubeSetVolume;
  Future<void> _engineTransition = Future<void>.value();
  Future<void> Function(int sourceIndex)? _onPlaySourceIndexRequested;
  Future<void> Function(dynamic item)? _onPrefetchQueueItem;
  EditedSongTrim? Function(String videoId, [String? playlistId])? _trimLookup;
  Duration? _trimStart;
  Duration? _trimEnd;

  String artistName = 'Unknown Artist';
  String? currentArtistId;
  String songName = 'Unknown Song';
  String? currentSongPath;
  Uint8List? coverImageBytes;
  String? currentYouTubeVideoId;
  Duration progress = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  bool isMuted = false;
  bool isShuffled = false;
  PlayerRepeatMode repeatMode = PlayerRepeatMode.off;
  double currentSliderValue = 20.0;
  bool isSeeking = false;
  Duration seekPreview = Duration.zero;
  List<dynamic> queue = [];
  bool needsResumeLoad = false;
  bool _videoTexturePaused = false;
  bool get isVideoTexturePaused => _videoTexturePaused;

  void pauseVideoTexture() {
    if (_videoTexturePaused) return;
    _videoTexturePaused = true;
    notifyListeners();
  }

  void resumeVideoTexture() {
    if (!_videoTexturePaused) return;
    _videoTexturePaused = false;
    notifyListeners();
  }

  List<dynamic> _playlistItems = [];
  List<int> _playOrder = [];
  int _currentOrderIndex = -1;
  String? _sourcePlaylistId;
  String? _sourcePlaylistTitle;
  String? _sourcePlaylistPrivacyStatus;
  String? get sourcePlaylistId => _sourcePlaylistId;
  bool get isSourcePlaylistPrivate => _sourcePlaylistPrivacyStatus == 'private';
  Map<String, dynamic>? suggestedRemovalSong;
  String? suggestedRemovalPlaylistId;
  String? suggestedRemovalPlaylistTitle;
  RemoteSession? _remoteSession;
  bool _isRemoteControlling = false;
  String? _dismissedRemoteKey;
  StreamSubscription<RemoteSession?>? _remoteSessionSub;
  StreamSubscription<List<RemoteCommand>>? _incomingCommandsSub;
  Timer? _sessionHeartbeat;
  Timer? _positionAutosaveTimer;
  Duration? _restoredResumePosition;
  Timer? _sleepTimer;
  DateTime? _sleepTimerEndsAt;
  bool _pauseAtTrackEndScheduled = false;

  PlaybackModel() {
    unawaited(_restoreVolume());
    unawaited(_restoreLastPlayedState());
    _remoteSessionSub = PlaybackSessionSyncService.watchOtherSession().listen((
      session,
    ) {
      _remoteSession = session;
      if (_isRemoteControlling && session == null) {
        _isRemoteControlling = false;
      }
      notifyListeners();
    });
    _incomingCommandsSub = PlaybackSessionSyncService.watchIncomingCommands()
        .listen(_handleIncomingCommands);
    _sessionHeartbeat = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!_isRemoteControlling && isPlaying) _pushSessionIfHosting();
    });
    _positionAutosaveTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (isPlaying) _persistQueueState();
    });
  }

  bool get hasRestorableQueue => needsResumeLoad && _playOrder.isNotEmpty;

  RemoteSession? get remoteSession => _remoteSession;
  bool get isRemoteControlling => _isRemoteControlling;
  bool get shouldShowRemoteBanner {
    if (_isRemoteControlling) return false;
    final session = _remoteSession;
    if (session == null || !session.isLive) return false;
    final key = session.currentTrack?['videoId'] as String?;
    return key != null && key != _dismissedRemoteKey;
  }

  void dismissRemoteBanner() {
    _dismissedRemoteKey = _remoteSession?.currentTrack?['videoId'] as String?;
    notifyListeners();
  }

  Future<void> enterRemoteControl() async {
    if (_remoteSession == null) return;
    if (isPlaying) await _localTogglePlayPause();
    _isRemoteControlling = true;
    notifyListeners();
  }

  void _exitRemoteControl() {
    if (!_isRemoteControlling) return;
    _isRemoteControlling = false;
    notifyListeners();
  }

  Future<void> resumeRemoteSessionLocally() async {
    final session = _remoteSession;
    final track = session?.currentTrack;
    if (session == null || track == null) return;
    _isRemoteControlling = false;
    isShuffled = session.shuffle;
    repeatMode = PlayerRepeatMode.values.firstWhere(
      (mode) => mode.name == session.repeatMode,
      orElse: () => PlayerRepeatMode.off,
    );
    setPlaylistQueue(session.queue, startIndex: session.queueIndex);
    await playQueueIndex(0);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await seekTo(session.position);
  }

  void _pushSessionIfHosting() {
    if (_isRemoteControlling) return;
    if (_currentOrderIndex < 0 || _currentOrderIndex >= _playOrder.length) {
      return;
    }
    final unfiltered = <Map<String, dynamic>>[
      for (final sourceIndex in _playOrder)
        if (_playlistItems[sourceIndex] is Map<String, dynamic>)
          _playlistItems[sourceIndex] as Map<String, dynamic>,
    ];
    if (_currentOrderIndex >= unfiltered.length) return;
    final currentItem = unfiltered[_currentOrderIndex];
    final currentVideoId = currentItem['videoId'] as String?;
    if (currentVideoId == null || currentVideoId.isEmpty) {
      return;
    }

    final syncable = <Map<String, dynamic>>[];
    var syncableIndex = -1;
    for (var i = 0; i < unfiltered.length; i++) {
      final videoId = unfiltered[i]['videoId'] as String?;
      if (videoId == null || videoId.isEmpty) continue;
      if (i == _currentOrderIndex) syncableIndex = syncable.length;
      syncable.add(unfiltered[i]);
    }
    if (syncableIndex < 0) return;

    PlaybackSessionSyncService.pushSession(
      queue: syncable,
      queueIndex: syncableIndex,
      position: displayedProgress,
      isPlaying: isPlaying,
      volume: effectiveVolumePercent / 100,
      shuffle: isShuffled,
      repeatMode: repeatMode.name,
    );
  }

  Future<void> _handleIncomingCommands(List<RemoteCommand> commands) async {
    for (final command in commands) {
      switch (command.type) {
        case RemoteCommandType.play:
          if (!isPlaying) await _localTogglePlayPause();
          break;
        case RemoteCommandType.pause:
          if (isPlaying) await _localTogglePlayPause();
          break;
        case RemoteCommandType.next:
          await _localPlayNext();
          break;
        case RemoteCommandType.previous:
          await _localPlayPrevious();
          break;
        case RemoteCommandType.setVolume:
          final value = command.value;
          if (value != null) await _localApplyVolume(value * 100);
          break;
      }
      await PlaybackSessionSyncService.ackCommand(command.id);
    }
  }

  Future<void> _restoreVolume() async {
    final saved = await PlaybackStateService.loadVolume();
    if (saved == null) return;
    currentSliderValue = saved.clamp(0, 100).toDouble();
    isMuted = currentSliderValue == 0;
    notifyListeners();
    try {
      await player.setVolume(currentSliderValue / 100);
    } catch (_) {}
  }

  Future<void> _fetchAndApplyYouTubeThumbnail(String videoId) async {
    if (videoId.isEmpty) return;
    try {
      final response = await http.get(
        Uri.parse('https://i.ytimg.com/vi/$videoId/hqdefault.jpg'),
      );
      if (response.statusCode == 200) {
        coverImageBytes = response.bodyBytes;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _restoreLastPlayedState() async {
    final savedQueue = await PlaybackStateService.loadQueue();
    if (savedQueue != null) {
      _playlistItems = savedQueue.playlistItems;
      _playOrder = savedQueue.playOrder;
      _currentOrderIndex = savedQueue.currentOrderIndex;
      isShuffled = savedQueue.shuffle;
      repeatMode = PlayerRepeatMode.values.firstWhere(
        (mode) => mode.name == savedQueue.repeatMode,
        orElse: () => PlayerRepeatMode.off,
      );
      _refreshQueueWindow();

      final sourceIndex = _playOrder[_currentOrderIndex];
      final item = _playlistItems[sourceIndex];
      String? restoredVideoId;
      if (item is Map<String, dynamic>) {
        final restoredSongName = (item['songName'] ?? item['title']) as String?;
        final restoredArtistName =
            (item['artistName'] ?? item['artist']) as String?;
        if (restoredSongName != null && restoredSongName.isNotEmpty) {
          songName = restoredSongName;
        }
        if (restoredArtistName != null && restoredArtistName.isNotEmpty) {
          artistName = restoredArtistName;
        }
        currentArtistId = item['artistId'] as String?;

        final durationSeconds = item['durationSeconds'] as int?;
        if (durationSeconds != null && durationSeconds > 0) {
          duration = Duration(seconds: durationSeconds);
        }

        final videoId = (item['videoId'] as String?) ?? '';
        final path = (item['path'] as String?) ?? '';
        if (videoId.isNotEmpty) {
          currentSongPath = 'yt:$videoId';
          restoredVideoId = videoId;
        } else if (path.isNotEmpty) {
          currentSongPath = path;
        }
      }

      needsResumeLoad = true;
      _restoredResumePosition = savedQueue.position;
      notifyListeners();

      if (restoredVideoId != null) {
        await _fetchAndApplyYouTubeThumbnail(restoredVideoId);
      }
      return;
    }

    await _restoreLastPlayedSong();
  }

  Future<void> _restoreLastPlayedSong() async {
    final prefs = await SharedPreferences.getInstance();
    final path = prefs.getString(_prefsSongPathKey);
    if (path == null || path.isEmpty) return;

    songName = prefs.getString(_prefsSongNameKey) ?? songName;
    artistName = prefs.getString(_prefsArtistNameKey) ?? artistName;
    final restoredArtistId = prefs.getString(_prefsArtistIdKey);
    currentArtistId = (restoredArtistId == null || restoredArtistId.isEmpty)
        ? null
        : restoredArtistId;
    currentSongPath = path;
    needsResumeLoad = true;
    notifyListeners();

    if (path.startsWith('yt:')) {
      final videoId = path.substring(3).trim();
      if (videoId.isEmpty) return;
      await _fetchAndApplyYouTubeThumbnail(videoId);
    }
  }

  Future<void> _persistLastPlayedSong() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsSongNameKey, songName);
      await prefs.setString(_prefsArtistNameKey, artistName);
      await prefs.setString(_prefsArtistIdKey, currentArtistId ?? '');
      await prefs.setString(_prefsSongPathKey, currentSongPath ?? '');
    } catch (_) {}
  }

  void _persistQueueState() {
    if (_playlistItems.isEmpty ||
        _playOrder.isEmpty ||
        _currentOrderIndex < 0 ||
        _currentOrderIndex >= _playOrder.length) {
      unawaited(PlaybackStateService.clearQueue());
      return;
    }
    unawaited(
      PlaybackStateService.saveQueue(
        playlistItems: _playlistItems,
        playOrder: _playOrder,
        currentOrderIndex: _currentOrderIndex,
        shuffle: isShuffled,
        repeatMode: repeatMode.name,
        position: displayedProgress,
      ),
    );
  }

  Future<void> resumeRestoredQueue() async {
    if (!hasRestorableQueue) return;
    needsResumeLoad = false;
    final resumePosition = _restoredResumePosition;
    _restoredResumePosition = null;

    await _playBySourceIndex(_playOrder[_currentOrderIndex]);
    _forceDiscordPresenceRefreshAfterTrackChange();
    unawaited(_prefetchAhead());

    if (resumePosition != null && resumePosition > Duration.zero) {
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 400), () {
          return seekTo(resumePosition);
        }),
      );
    }
  }

  Duration get displayedProgress => isSeeking ? seekPreview : progress;
  PlaybackEngine get engine => _engine;

  String? _activePlayId;
  String _activePlayTitle = '';
  String _activePlayArtist = '';
  String _activePlayThumb = '';
  String? _activePlayArtistId;
  DateTime? _activePlayStartedAt;
  int _activePlayMaxProgressMs = 0;
  int _activePlayDurationMs = 0;

  void _finalizeActivePlay() {
    final id = _activePlayId;
    final startedAt = _activePlayStartedAt;
    final listenedMs = max(_activePlayMaxProgressMs, progress.inMilliseconds);
    final durationMs = _activePlayDurationMs;
    final title = _activePlayTitle;
    final artist = _activePlayArtist;
    final thumb = _activePlayThumb;
    final channelId = _activePlayArtistId;
    _activePlayId = null;
    _activePlayStartedAt = null;
    _activePlayMaxProgressMs = 0;
    _activePlayDurationMs = 0;
    _activePlayArtistId = null;
    if (id == null || startedAt == null) return;
    unawaited(
      ListeningHistoryService.logPlay(
        trackId: id,
        title: title,
        artist: artist,
        thumbnailUrl: thumb,
        channelId: channelId,
        trackDuration: Duration(milliseconds: durationMs),
        startedAt: startedAt,
        listened: Duration(milliseconds: listenedMs),
      ),
    );
  }

  void _beginActivePlay(String path) {
    final isYouTube = path.startsWith('yt:');
    final videoId = isYouTube ? path.substring(3) : '';
    _activePlayId = isYouTube ? videoId : path;
    _activePlayTitle = songName;
    _activePlayArtist = artistName;
    _activePlayThumb = isYouTube
        ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
        : '';
    _activePlayArtistId = currentArtistId;
    _activePlayStartedAt = DateTime.now();
    _activePlayMaxProgressMs = 0;
    _activePlayDurationMs = duration?.inMilliseconds ?? 0;
  }

  void _trackActiveProgress(Duration position) {
    if (_activePlayId == null) return;
    final ms = position.inMilliseconds;
    if (ms > _activePlayMaxProgressMs) _activePlayMaxProgressMs = ms;
  }

  void _trackActiveDuration(Duration? value) {
    if (_activePlayId == null || value == null) return;
    final ms = value.inMilliseconds;
    if (ms > _activePlayDurationMs) _activePlayDurationMs = ms;
  }

  double get effectiveVolumePercent =>
      currentSliderValue.clamp(0, 100).toDouble();

  bool get _hasDiscordPresenceTarget {
    return currentSongPath != null && currentSongPath!.trim().isNotEmpty;
  }

  double _sliderToOutputVolumePercent(double sliderValue) {
    return sliderValue.clamp(0, 100).toDouble();
  }

  double _outputToSliderVolumePercent(double outputVolumePercent) {
    return outputVolumePercent.clamp(0, 100).toDouble();
  }

  void bindYouTubeCallbacks({
    required Future<void> Function(String videoId) loadVideoById,
    required Future<void> Function(String videoId) prefetchVideoById,
    required Future<void> Function() play,
    required Future<void> Function() pause,
    required Future<void> Function(Duration position) seek,
    required Future<void> Function(double sliderValue) setVolume,
  }) {
    _youtubeLoadVideoById = loadVideoById;
    _youtubePrefetchVideoById = prefetchVideoById;
    _youtubePlay = play;
    _youtubePause = pause;
    _youtubeSeek = seek;
    _youtubeSetVolume = setVolume;
  }

  Future<void> prefetchYouTubeVideoById(String videoId) async {
    if (videoId.isEmpty) return;
    try {
      await _youtubePrefetchVideoById?.call(videoId);
    } catch (_) {}
  }

  bool _isNearTrackEnd() {
    final total = _trimEnd ?? duration;
    if (total == null || total <= Duration.zero) return false;

    final current = progress;
    if (current <= Duration.zero) return false;

    final remaining = total - current;
    return remaining <= const Duration(milliseconds: 800);
  }

  void _checkTrimEndReached() {
    final end = _trimEnd;
    if (end == null || _completionHandledForCurrentTrack) return;
    if (progress < end - const Duration(milliseconds: 500)) return;
    unawaited(_triggerTrackCompletedIfNeeded());
  }

  Future<void> _triggerTrackCompletedIfNeeded() async {
    if (_completionHandledForCurrentTrack) return;
    if (!_isNearTrackEnd()) return;

    _completionHandledForCurrentTrack = true;
    final playlistId = _sourcePlaylistId;
    if (playlistId != null &&
        _currentOrderIndex >= 0 &&
        _currentOrderIndex < _playOrder.length) {
      final sourceIndex = _playOrder[_currentOrderIndex];
      if (sourceIndex >= 0 && sourceIndex < _playlistItems.length) {
        final item = _playlistItems[sourceIndex];
        if (item is Map<String, dynamic>) {
          final videoId = (item['videoId'] as String?) ?? '';
          if (videoId.isNotEmpty) {
            unawaited(SkipTrackingService.recordCompleted(playlistId, videoId));
          }
        }
      }
    }
    if (_pauseAtTrackEndScheduled) {
      _pauseAtTrackEndScheduled = false;
      if (isPlaying) await _localTogglePlayPause();
      return;
    }
    if (repeatMode == PlayerRepeatMode.one) {
      await _restartCurrentTrack();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          return _syncDiscordPresence(force: true);
        }),
      );
      return;
    }
    await _localPlayNext();
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        return _syncDiscordPresence(force: true);
      }),
    );
  }

  void _forceDiscordPresenceRefreshAfterTrackChange() {
    unawaited(
      Future<void>.delayed(const Duration(milliseconds: 150), () {
        return _syncDiscordPresence(force: true);
      }),
    );
  }

  Future<void> _restartCurrentTrack() async {
    final path = currentSongPath;
    _finalizeActivePlay();
    if (path != null && path.trim().isNotEmpty) _beginActivePlay(path);
    final restartPosition = _trimStart ?? Duration.zero;
    setProgress(restartPosition);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSeek?.call(restartPosition);
      await _youtubePlay?.call();
      _completionHandledForCurrentTrack = false;
      return;
    }

    await player.seek(restartPosition);
    await player.play();
    _completionHandledForCurrentTrack = false;
  }

  Future<void> switchToLocalEngine() async {
    _engineTransition = _engineTransition.catchError((_) {}).then((_) async {
      if (_engine == PlaybackEngine.youtube) {
        await _youtubePause?.call();
      }
      _engine = PlaybackEngine.local;
      currentYouTubeVideoId = null;
      notifyListeners();
    });
    await _engineTransition;
  }

  void _useYouTubeEngine(String videoId) {
    _engine = PlaybackEngine.youtube;
    currentYouTubeVideoId = videoId;
    notifyListeners();
  }

  Future<void> playYouTubeVideoById(String videoId) async {
    final trim = _trimLookup?.call(videoId, _sourcePlaylistId);
    _trimStart = trim != null ? Duration(milliseconds: trim.startMs) : null;
    _trimEnd = trim != null ? Duration(milliseconds: trim.endMs) : null;

    _engineTransition = _engineTransition.catchError((_) {}).then((_) async {
      setDuration(Duration.zero);
      setProgress(Duration.zero);
      currentYouTubeVideoId = videoId;
      notifyListeners();

      try {
        await player.pause();
      } catch (_) {}
      try {
        await player.stop();
      } catch (_) {}
      try {
        await player.seek(Duration.zero);
      } catch (_) {}

      await _youtubeLoadVideoById?.call(videoId);
      _useYouTubeEngine(videoId);

      final start = _trimStart;
      if (start != null && start > Duration.zero) {
        setProgress(start);
      }
    });
    await _engineTransition;
  }

  void syncFromYouTube({
    Duration? position,
    Duration? totalDuration,
    bool? playing,
  }) {
    if (_engine != PlaybackEngine.youtube) return;

    var shouldNotify = false;

    if (position != null && !isSeeking && progress != position) {
      progress = position;
      _trackActiveProgress(position);
      shouldNotify = true;
    }

    if (totalDuration != null && duration != totalDuration) {
      duration = totalDuration;
      _trackActiveDuration(totalDuration);
      shouldNotify = true;
    }

    if (playing != null && isPlaying != playing) {
      isPlaying = playing;
      shouldNotify = true;
    }

    if (shouldNotify) {
      notifyListeners();
    }
  }

  void bindToPlayer() {
    if (_isBoundToPlayer) return;

    _positionSubscription = player
        .createPositionStream(
          minPeriod: const Duration(milliseconds: 16),
          maxPeriod: const Duration(milliseconds: 40),
        )
        .listen((position) {
          setProgress(position);
          _checkTrimEndReached();
        });

    _playerStateSubscription = player.playerStateStream.listen((state) async {
      final wasPlaying = _wasPlaying;
      _wasPlaying = state.playing;
      setIsPlaying(state.playing);

      if (wasPlaying && !state.playing) {
        await _triggerTrackCompletedIfNeeded();
      }
    });

    _durationSubscription = player.durationStream.listen((newDuration) {
      setDuration(newDuration);
      _maybeCacheDriveDuration(newDuration);
    });

    _volumeSubscription = player.volumeStream.listen((volume) {
      final outputVolumePercent = (volume * 100).clamp(0, 100).toDouble();
      final sliderValue = _outputToSliderVolumePercent(outputVolumePercent);
      currentSliderValue = sliderValue;
      isMuted = sliderValue == 0;
      notifyListeners();
    });

    _completedSubscription = player.completedStream.listen((completed) async {
      if (!completed) {
        return;
      }
      await _triggerTrackCompletedIfNeeded();
    });

    player.setVolume(effectiveVolumePercent / 100);
    _isBoundToPlayer = true;
    unawaited(_initializeDiscordPresence());
  }

  Future<void> _initializeDiscordPresence({bool forceReconnect = false}) async {
    if (!_discordRichPresenceEnabled) return;
    if (!DiscordRPC.isAvailable) return;

    final applicationId = dotenv.env['DISCORD_APPLICATION_ID']?.trim();
    if (applicationId == null || applicationId.isEmpty) {
      return;
    }

    if (!forceReconnect &&
        _discordRpcReady &&
        _discordRpc?.isConnected == true) {
      return;
    }

    if (forceReconnect) {
      _discordPresenceTimer?.cancel();
      _discordRpcReady = false;
      final previousRpc = _discordRpc;
      _discordRpc = null;
      if (previousRpc != null) {
        try {
          await previousRpc.dispose();
        } catch (_) {}
      }
    }

    final discordRpc = DiscordRPC();
    try {
      await discordRpc.initialize(applicationId);
      _discordRpc = discordRpc;
      _discordRpcReady = true;
      final connectedUser = discordRpc.connectedUser;
      if (connectedUser != null) {
        debugPrint(
          'Connected to Discord as ${connectedUser.globalName ?? connectedUser.username}',
        );
      } else {
        debugPrint('Connected to Discord presence');
      }
      await _syncDiscordPresence(force: true);
    } catch (error) {
      debugPrint('Discord presence initialization failed: $error');
      await discordRpc.dispose();
    }
  }

  void _scheduleDiscordPresenceSync({bool allowReconnect = false}) {
    if (!_discordRichPresenceEnabled) return;
    final discordRpc = _discordRpc;
    final isConnected = discordRpc?.isConnected == true;

    if (!isConnected) {
      if (allowReconnect && _hasDiscordPresenceTarget) {
        debugPrint('Discord disconnected, retrying on track switch');
        _discordReconnectFuture ??=
            _initializeDiscordPresence(forceReconnect: true).whenComplete(() {
              _discordReconnectFuture = null;
            });
      }
      return;
    }

    _discordPresenceTimer?.cancel();
    _discordPresenceTimer = Timer(_discordPresenceDebounce, () {
      unawaited(_syncDiscordPresence());
    });
  }

  String? _buildThumbnailUrl() {
    final path = currentSongPath?.trim() ?? '';
    if (path.startsWith('yt:')) {
      final videoId = path.substring(3).trim();
      if (videoId.isNotEmpty) {
        return 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
      }
    }
    return null;
  }

  DiscordTimestamps? _buildProgressTimestamps() {
    final totalDuration = duration;
    final currentPosition = displayedProgress;
    if (totalDuration == null || totalDuration <= Duration.zero) return null;
    if (currentPosition < Duration.zero || currentPosition > totalDuration) {
      return null;
    }

    final now = DateTime.now();
    return DiscordTimestamps.range(
      now.subtract(currentPosition),
      now.add(totalDuration - currentPosition),
    );
  }

  DiscordPresence _buildDiscordPresence() {
    final title = songName.trim().isEmpty ? 'Unknown Song' : songName.trim();
    final artist = artistName.trim().isEmpty
        ? 'Unknown Artist'
        : artistName.trim();
    final thumbnailUrl = _buildThumbnailUrl();
    final fallbackImageKey = dotenv.env['DISCORD_LARGE_IMAGE_KEY']?.trim();
    final fallbackImageUrl = dotenv.env['DISCORD_LARGE_IMAGE_URL']?.trim();

    DiscordAsset? largeAsset;
    if (thumbnailUrl != null && thumbnailUrl.isNotEmpty) {
      largeAsset = DiscordAsset.fromUrl(thumbnailUrl);
    } else if (fallbackImageUrl != null && fallbackImageUrl.isNotEmpty) {
      largeAsset = DiscordAsset.fromUrl(fallbackImageUrl);
    } else if (fallbackImageKey != null && fallbackImageKey.isNotEmpty) {
      largeAsset = DiscordAsset.fromKey(fallbackImageKey);
    }

    return DiscordPresence(
      type: DiscordActivityType.listening,
      details: title,
      state: isPlaying ? artist : '$artist (Paused)',
      timestamps: isPlaying ? _buildProgressTimestamps() : null,
      largeAsset: largeAsset,
      statusDisplayType: DiscordStatusDisplayType.details,
    );
  }

  String _presenceSignature(DiscordPresence presence) {
    final timestamps = presence.timestamps;
    final largeAsset = presence.largeAsset;
    return [
      presence.type.value.toString(),
      presence.details ?? '',
      presence.state ?? '',
      timestamps?.start?.toString() ?? '',
      timestamps?.end?.toString() ?? '',
      largeAsset?.url ?? largeAsset?.key ?? '',
    ].join('|');
  }

  Future<void> _syncDiscordPresence({bool force = false}) async {
    final reconnectFuture = _discordReconnectFuture;
    if (reconnectFuture != null) {
      await reconnectFuture;
    }

    final discordRpc = _discordRpc;
    if (discordRpc == null ||
        !_discordRpcReady ||
        discordRpc.isConnected != true) {
      return;
    }

    if (!_hasDiscordPresenceTarget) {
      _lastDiscordPresenceSignature = null;
      try {
        await discordRpc.clearPresence();
      } catch (_) {}
      return;
    }

    final presence = _buildDiscordPresence();
    final signature = _presenceSignature(presence);
    if (!force && signature == _lastDiscordPresenceSignature) {
      return;
    }

    try {
      if (presence.timestamps == null) {
        await discordRpc.clearPresence();
      }
      await discordRpc.setPresence(presence);
      _lastDiscordPresenceSignature = signature;
    } catch (error) {
      debugPrint('Discord presence update failed: $error');
      if (error.toString().contains('Not connected to Discord')) {
        _discordRpcReady = false;
        _discordReconnectFuture ??=
            _initializeDiscordPresence(forceReconnect: true).whenComplete(() {
              _discordReconnectFuture = null;
            });
      }
    }
  }

  void setQueueHandlers({
    required Future<void> Function(int sourceIndex) playAtSourceIndex,
    Future<void> Function(dynamic item)? prefetchQueueItem,
  }) {
    _onPlaySourceIndexRequested = playAtSourceIndex;
    _onPrefetchQueueItem = prefetchQueueItem;
  }

  void bindEditedSongsLookup(
    EditedSongTrim? Function(String videoId, [String? playlistId]) lookup,
  ) {
    _trimLookup = lookup;
  }

  bool Function()? _autoplayEnabledLookup;
  Future<YTMusic> Function()? _ensureYtMusicLookup;
  String? _autoplayAttemptedSeedVideoId;

  void setDiscordRichPresenceEnabled(bool enabled) {
    if (enabled == _discordRichPresenceEnabled) return;
    _discordRichPresenceEnabled = enabled;
    if (enabled) {
      unawaited(_initializeDiscordPresence(forceReconnect: true));
      return;
    }

    _discordPresenceTimer?.cancel();
    _discordReconnectFuture = null;
    _lastDiscordPresenceSignature = null;
    final rpc = _discordRpc;
    _discordRpc = null;
    _discordRpcReady = false;
    if (rpc != null) {
      unawaited(_disconnectDiscordRpc(rpc));
    }
  }

  Future<void> _disconnectDiscordRpc(DiscordRPC rpc) async {
    try {
      await rpc.clearPresence();
    } catch (_) {}
    try {
      await rpc.dispose();
    } catch (_) {}
  }

  void bindAutoplay({
    required bool Function() isEnabled,
    required Future<YTMusic> Function() ensureYtMusic,
  }) {
    _autoplayEnabledLookup = isEnabled;
    _ensureYtMusicLookup = ensureYtMusic;
  }

  Future<bool> _tryAppendAutoplayContinuation() async {
    if (_autoplayEnabledLookup?.call() != true) return false;
    if (_currentOrderIndex < 0 || _currentOrderIndex >= _playOrder.length) {
      return false;
    }
    final sourceIndex = _playOrder[_currentOrderIndex];
    if (sourceIndex < 0 || sourceIndex >= _playlistItems.length) return false;
    final item = _playlistItems[sourceIndex];
    if (item is! Map<String, dynamic>) return false;
    final seedVideoId = item['videoId'] as String?;
    if (seedVideoId == null || seedVideoId.isEmpty) return false;
    if (_autoplayAttemptedSeedVideoId == seedVideoId) return false;
    _autoplayAttemptedSeedVideoId = seedVideoId;

    final ensureYtMusic = _ensureYtMusicLookup;
    if (ensureYtMusic == null) return false;
    try {
      final ytmusic = await ensureYtMusic();
      final excludeIds = _playlistItems
          .whereType<Map>()
          .map((m) => m['videoId'] as String?)
          .whereType<String>()
          .toSet();
      final continuation = await AutoplayService.fetchAutoplayContinuation(
        ytmusic,
        seedVideoId,
        excludeVideoIds: excludeIds,
      );
      if (continuation.isEmpty) return false;
      for (final track in continuation) {
        appendToQueue(track);
      }
      return true;
    } catch (error) {
      debugPrint('PlaybackModel: autoplay continuation failed: $error');
      return false;
    }
  }

  Duration? get trimStart => _trimStart;
  Duration? get trimEnd => _trimEnd;
  bool get hasActiveTrim => _trimEnd != null;

  DateTime? get sleepTimerEndsAt => _sleepTimerEndsAt;
  bool get isSleepTimerEndOfTrackScheduled => _pauseAtTrackEndScheduled;
  bool get hasSleepTimer =>
      _sleepTimerEndsAt != null || _pauseAtTrackEndScheduled;

  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _pauseAtTrackEndScheduled = false;
    _sleepTimerEndsAt = DateTime.now().add(duration);
    _sleepTimer = Timer(duration, () {
      _sleepTimer = null;
      _sleepTimerEndsAt = null;
      if (isPlaying) unawaited(_localTogglePlayPause());
      notifyListeners();
    });
    notifyListeners();
  }

  void startSleepTimerEndOfTrack() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    _pauseAtTrackEndScheduled = true;
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTimerEndsAt = null;
    _pauseAtTrackEndScheduled = false;
    notifyListeners();
  }

  Duration _clampToTrim(Duration value) {
    var result = value;
    final start = _trimStart;
    final end = _trimEnd;
    if (start != null && result < start) result = start;
    if (end != null && result > end) result = end;
    return result;
  }

  void clearPlaylistQueue() {
    _exitRemoteControl();
    _playlistItems = [];
    _playOrder = [];
    _currentOrderIndex = -1;
    _sourcePlaylistId = null;
    _sourcePlaylistTitle = null;
    _sourcePlaylistPrivacyStatus = null;
    suggestedRemovalSong = null;
    suggestedRemovalPlaylistId = null;
    suggestedRemovalPlaylistTitle = null;
    queue = [];
    notifyListeners();
    _persistQueueState();
  }

  void setSourcePlaylist({
    required String? id,
    String? title,
    String? privacyStatus,
  }) {
    _sourcePlaylistId = id;
    _sourcePlaylistTitle = title;
    _sourcePlaylistPrivacyStatus = privacyStatus;
    notifyListeners();
  }

  void setPlaylistQueue(List<dynamic> items, {required int startIndex}) {
    unawaited(_recordPotentialSkip());
    _sourcePlaylistId = null;
    _sourcePlaylistTitle = null;
    _sourcePlaylistPrivacyStatus = null;
    _exitRemoteControl();
    if (items.isEmpty || startIndex < 0 || startIndex >= items.length) {
      _playlistItems = [];
      _playOrder = [];
      _currentOrderIndex = -1;
      queue = [];
      notifyListeners();
      _persistQueueState();
      return;
    }

    _playlistItems = List<dynamic>.from(items);
    _rebuildPlayOrder(startIndex: startIndex);
    _currentOrderIndex = 0;
    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  Future<void> _recordPotentialSkip() async {
    final playlistId = _sourcePlaylistId;
    if (playlistId == null) return;
    if (_currentOrderIndex < 0 || _currentOrderIndex >= _playOrder.length) {
      return;
    }
    final sourceIndex = _playOrder[_currentOrderIndex];
    if (sourceIndex < 0 || sourceIndex >= _playlistItems.length) return;
    final item = _playlistItems[sourceIndex];
    if (item is! Map<String, dynamic>) return;
    final videoId = (item['videoId'] as String?) ?? '';
    if (videoId.isEmpty) return;

    final total = duration;
    if (total == null || total <= Duration.zero) return;
    final playedFraction = progress.inMilliseconds / total.inMilliseconds;
    if (playedFraction >= SkipTrackingService.consideredSkippedBeforeFraction) {
      return;
    }

    final count = await SkipTrackingService.recordSkip(playlistId, videoId);
    if (count >= SkipTrackingService.skipThreshold) {
      suggestedRemovalSong = Map<String, dynamic>.from(item);
      suggestedRemovalPlaylistId = playlistId;
      suggestedRemovalPlaylistTitle = _sourcePlaylistTitle;
      notifyListeners();
    }
  }

  Future<void> dismissSkipSuggestion() async {
    final song = suggestedRemovalSong;
    final playlistId = suggestedRemovalPlaylistId;
    suggestedRemovalSong = null;
    suggestedRemovalPlaylistId = null;
    suggestedRemovalPlaylistTitle = null;
    notifyListeners();
    final videoId = song != null ? (song['videoId'] as String?) : null;
    if (playlistId != null && videoId != null && videoId.isNotEmpty) {
      await SkipTrackingService.clearForTrack(playlistId, videoId);
    }
  }

  void addToQueue(dynamic item) {
    _exitRemoteControl();
    _playlistItems = List<dynamic>.from(_playlistItems)..add(item);
    final sourceIndex = _playlistItems.length - 1;

    if (_playOrder.isEmpty) {
      _playOrder = <int>[sourceIndex];
      _currentOrderIndex = 0;
    } else {
      final insertAt = (_currentOrderIndex + 1).clamp(0, _playOrder.length);
      _playOrder = List<int>.from(_playOrder)..insert(insertAt, sourceIndex);
      if (_currentOrderIndex < 0) {
        _currentOrderIndex = 0;
      }
    }

    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  void appendToQueue(dynamic item) {
    _exitRemoteControl();
    _playlistItems = List<dynamic>.from(_playlistItems)..add(item);
    final sourceIndex = _playlistItems.length - 1;

    if (_playOrder.isEmpty) {
      _playOrder = <int>[sourceIndex];
      _currentOrderIndex = 0;
    } else {
      _playOrder = List<int>.from(_playOrder)..add(sourceIndex);
      if (_currentOrderIndex < 0) {
        _currentOrderIndex = 0;
      }
    }

    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  void reorderQueue(int oldQueueIndex, int newQueueIndex) {
    if (_isRemoteControlling) return;
    if (oldQueueIndex <= 0 || newQueueIndex <= 0) return;
    if (_playOrder.isEmpty || _currentOrderIndex < 0) return;
    final oldOrderIndex = _currentOrderIndex + oldQueueIndex;
    final newOrderIndex = _currentOrderIndex + newQueueIndex;
    if (oldOrderIndex < 0 || oldOrderIndex >= _playOrder.length) return;
    if (newOrderIndex < 0 || newOrderIndex >= _playOrder.length) return;
    if (oldOrderIndex == newOrderIndex) return;
    final updated = List<int>.from(_playOrder);
    final sourceIndex = updated.removeAt(oldOrderIndex);
    updated.insert(newOrderIndex, sourceIndex);
    _playOrder = updated;
    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  void clearUpNextQueue() {
    if (_isRemoteControlling) return;
    if (_playOrder.isEmpty || _currentOrderIndex < 0) return;
    final currentSourceIndex = _playOrder[_currentOrderIndex];
    _playOrder = <int>[currentSourceIndex];
    _currentOrderIndex = 0;
    _refreshQueueWindow();
    notifyListeners();
    _persistQueueState();
  }

  void removeFromQueue(int queueIndex) {
    if (_isRemoteControlling) return;
    if (queueIndex <= 0) return;
    if (_playOrder.isEmpty || _currentOrderIndex < 0) return;
    final orderIndex = _currentOrderIndex + queueIndex;
    if (orderIndex < 0 || orderIndex >= _playOrder.length) return;
    _playOrder = List<int>.from(_playOrder)..removeAt(orderIndex);
    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  void markCurrentSourceIndex(int sourceIndex) {
    if (_playlistItems.isEmpty || sourceIndex < 0) {
      return;
    }

    final foundOrderIndex = _playOrder.indexOf(sourceIndex);
    if (foundOrderIndex < 0) {
      return;
    }

    _currentOrderIndex = foundOrderIndex;
    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
    _persistQueueState();
  }

  Future<void> playQueueIndex(int queueIndex) async {
    if (_isRemoteControlling) return;
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    if (_currentOrderIndex < 0) return;
    await _recordPotentialSkip();

    final targetRawOrderIndex = _currentOrderIndex + queueIndex;
    final targetOrderIndex = _normalizeOrderIndex(targetRawOrderIndex);
    if (targetOrderIndex == null) return;

    _currentOrderIndex = targetOrderIndex;
    _refreshQueueWindow();
    notifyListeners();

    await _playBySourceIndex(_playOrder[targetOrderIndex]);
    _forceDiscordPresenceRefreshAfterTrackChange();
    unawaited(_prefetchAhead());
  }

  static const Duration _previousRestartThreshold = Duration(seconds: 3);

  bool get _pastPreviousRestartThreshold =>
      progress > _previousRestartThreshold;

  Future<void> playPrevious() async {
    if (_isRemoteControlling) {
      await PlaybackSessionSyncService.sendCommand(RemoteCommandType.previous);
      return;
    }
    if (!_pastPreviousRestartThreshold) {
      await _recordPotentialSkip();
    }
    await _localPlayPrevious();
  }

  Future<void> _localPlayPrevious() async {
    if (_playOrder.isEmpty) return;
    final previousOrderIndex = _normalizeOrderIndex(_currentOrderIndex - 1);
    if (_pastPreviousRestartThreshold || previousOrderIndex == null) {
      await seekTo(Duration.zero);
      return;
    }

    _currentOrderIndex = previousOrderIndex;
    _refreshQueueWindow();
    notifyListeners();

    await _playBySourceIndex(_playOrder[previousOrderIndex]);
    _forceDiscordPresenceRefreshAfterTrackChange();
    unawaited(_prefetchAhead());
    _pushSessionIfHosting();
  }

  Future<void> playNext() async {
    if (_isRemoteControlling) {
      await PlaybackSessionSyncService.sendCommand(RemoteCommandType.next);
      return;
    }
    await _recordPotentialSkip();
    await _localPlayNext();
  }

  Future<void> _localPlayNext() async {
    if (_playOrder.isNotEmpty) {
      var nextOrderIndex = _normalizeOrderIndex(_currentOrderIndex + 1);
      if (nextOrderIndex == null) {
        final appended = await _tryAppendAutoplayContinuation();
        if (appended) {
          nextOrderIndex = _normalizeOrderIndex(_currentOrderIndex + 1);
        } else if (repeatMode == PlayerRepeatMode.all) {
          nextOrderIndex = _normalizeOrderIndex(
            _currentOrderIndex + 1,
            wrapAround: true,
          );
        }
        if (nextOrderIndex == null) return;
      }

      _currentOrderIndex = nextOrderIndex;
      _refreshQueueWindow();
      notifyListeners();

      await _playBySourceIndex(_playOrder[nextOrderIndex]);
      _forceDiscordPresenceRefreshAfterTrackChange();
      unawaited(_prefetchAhead());
      _pushSessionIfHosting();
    }
  }

  Future<void> _playBySourceIndex(int sourceIndex) async {
    final playAtSourceIndex = _onPlaySourceIndexRequested;
    if (playAtSourceIndex != null) {
      final expectedItem =
          sourceIndex >= 0 && sourceIndex < _playlistItems.length
          ? _playlistItems[sourceIndex]
          : null;
      final expectedPath = _expectedCurrentSongPath(expectedItem);

      await playAtSourceIndex(sourceIndex);

      if (expectedPath == null || currentSongPath == expectedPath) {
        return;
      }
    }

    if (sourceIndex < 0 || sourceIndex >= _playlistItems.length) {
      return;
    }

    final item = _playlistItems[sourceIndex];
    if (item is! Map<String, dynamic>) {
      return;
    }

    final song = (item['songName'] ?? item['title'] ?? '').toString();
    final artist = (item['artistName'] ?? item['artist'] ?? '').toString();
    if (song.isNotEmpty) setSongName(song);
    if (artist.isNotEmpty) setArtist(artist);
    setArtistId(item['artistId'] as String?);

    final durationSeconds = item['durationSeconds'] as int?;
    if (durationSeconds != null && durationSeconds > 0) {
      setDuration(Duration(seconds: durationSeconds));
    } else {
      setDuration(Duration.zero);
    }

    final videoId = (item['videoId'] as String?) ?? '';
    if (videoId.isNotEmpty) {
      setCurrentSongPath('yt:$videoId');
      await playYouTubeVideoById(videoId);
      await applyVolume(currentSliderValue);
      return;
    }

    final path = (item['path'] as String?) ?? '';
    if (path.isNotEmpty) {
      final localCover = item['coverImageBytes'] as Uint8List?;
      await switchToLocalEngine();
      await player.setFilePath(path);
      await player.seek(Duration.zero);
      await player.play();
      setCurrentSongPath(path);
      setCoverImageBytes(localCover);
      setIsPlaying(true);
      setIsMuted(currentSliderValue == 0);
    }
  }

  String? _expectedCurrentSongPath(dynamic item) {
    if (item is! Map<String, dynamic>) {
      return null;
    }

    final videoId = (item['videoId'] as String?) ?? '';
    if (videoId.isNotEmpty) {
      return 'yt:$videoId';
    }

    final path = (item['path'] as String?) ?? '';
    if (path.isNotEmpty) {
      return path;
    }

    return null;
  }

  Future<void> seekTo(Duration value) async {
    if (_isRemoteControlling) return;
    final clamped = _clampToTrim(value);
    setProgress(clamped);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSeek?.call(clamped);
    } else {
      await player.seek(clamped);
    }
    _scheduleDiscordPresenceSync();
  }

  Future<void> togglePlayPause() async {
    if (_isRemoteControlling) {
      await PlaybackSessionSyncService.sendCommand(
        isPlaying ? RemoteCommandType.pause : RemoteCommandType.play,
      );
      return;
    }
    await _localTogglePlayPause();
  }

  Future<void> _localTogglePlayPause() async {
    if (_engine == PlaybackEngine.youtube) {
      if (isPlaying) {
        await _youtubePause?.call();
        setIsPlaying(false);
      } else {
        await _youtubePlay?.call();
        setIsPlaying(true);
      }
      _pushSessionIfHosting();
      return;
    }

    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
    _pushSessionIfHosting();
  }

  void toggleShuffle() {
    if (_isRemoteControlling) return;
    isShuffled = !isShuffled;
    if (_playlistItems.isNotEmpty) {
      final fallbackSourceIndex =
          _playOrder.isNotEmpty && _currentOrderIndex >= 0
          ? _playOrder[_currentOrderIndex]
          : 0;
      final sourceIndex = _sourceIndexFromCurrentPath() ?? fallbackSourceIndex;
      _rebuildPlayOrder(startIndex: sourceIndex);
      _currentOrderIndex = 0;
      _refreshQueueWindow();
      unawaited(_prefetchAhead());
    }
    notifyListeners();
    _persistQueueState();
  }

  void cycleRepeatMode() {
    if (_isRemoteControlling) return;
    repeatMode = PlayerRepeatMode
        .values[(repeatMode.index + 1) % PlayerRepeatMode.values.length];
    if (_playlistItems.isNotEmpty) {
      _refreshQueueWindow();
    }
    notifyListeners();
    _persistQueueState();
  }

  int? _sourceIndexFromCurrentPath() {
    final currentPath = currentSongPath;
    if (currentPath == null || currentPath.isEmpty) {
      return null;
    }

    for (var i = 0; i < _playlistItems.length; i++) {
      final item = _playlistItems[i];
      if (item is Map<String, dynamic>) {
        final path = item['path'] as String?;
        final videoId = item['videoId'] as String?;
        if (path != null && path == currentPath) return i;
        if (videoId != null && 'yt:$videoId' == currentPath) return i;
      }
    }

    return null;
  }

  void _rebuildPlayOrder({required int startIndex}) {
    final count = _playlistItems.length;
    if (count == 0) {
      _playOrder = [];
      return;
    }

    final safeStart = startIndex.clamp(0, count - 1);
    final allIndices = List<int>.generate(count, (index) => index);

    if (!isShuffled) {
      _playOrder = <int>[
        ...allIndices.skip(safeStart),
        ...allIndices.take(safeStart),
      ];
      return;
    }

    allIndices.remove(safeStart);
    allIndices.shuffle(Random());
    _playOrder = <int>[safeStart, ...allIndices];
  }

  int? _normalizeOrderIndex(int rawIndex, {bool wrapAround = false}) {
    if (_playOrder.isEmpty) return null;

    if (wrapAround) {
      final length = _playOrder.length;
      return ((rawIndex % length) + length) % length;
    }

    if (rawIndex < 0 || rawIndex >= _playOrder.length) {
      return null;
    }
    return rawIndex;
  }

  void _refreshQueueWindow() {
    if (_playOrder.isEmpty || _currentOrderIndex < 0) {
      queue = [];
      return;
    }

    final updatedQueue = <dynamic>[];
    final endOffset = _queueDisplayAheadCount;
    for (var offset = 0; offset <= endOffset; offset++) {
      final orderIndex = _normalizeOrderIndex(_currentOrderIndex + offset);
      if (orderIndex == null) break;
      final sourceIndex = _playOrder[orderIndex];
      updatedQueue.add(_playlistItems[sourceIndex]);
    }
    queue = updatedQueue;
  }

  Future<void> _prefetchAhead() async {
    final prefetchQueueItem = _onPrefetchQueueItem;
    if (queue.length <= 1) {
      return;
    }

    final maxAhead = min(_queueAheadCount, queue.length - 1);
    for (var offset = 1; offset <= maxAhead; offset++) {
      final item = queue[offset];
      if (prefetchQueueItem != null) {
        await prefetchQueueItem(item);
        continue;
      }

      if (item is! Map<String, dynamic>) {
        continue;
      }

      final videoId = (item['videoId'] as String?) ?? '';
      if (videoId.isEmpty) {
        continue;
      }

      await prefetchYouTubeVideoById(videoId);
    }
  }

  Timer? _volumeCommandThrottle;
  double? _pendingVolumeCommandValue;

  Future<void> applyVolume(double sliderValue) async {
    if (_isRemoteControlling) {
      _sendVolumeCommandThrottled((sliderValue.clamp(0, 100) / 100).toDouble());
      return;
    }
    await _localApplyVolume(sliderValue);
  }

  void _sendVolumeCommandThrottled(double value) {
    _pendingVolumeCommandValue = value;
    if (_volumeCommandThrottle != null) return;
    PlaybackSessionSyncService.sendCommand(
      RemoteCommandType.setVolume,
      value: value,
    );
    _volumeCommandThrottle = Timer(const Duration(milliseconds: 150), () {
      _volumeCommandThrottle = null;
      final pending = _pendingVolumeCommandValue;
      if (pending != null) {
        _pendingVolumeCommandValue = null;
        _sendVolumeCommandThrottled(pending);
      }
    });
  }

  Future<void> _localApplyVolume(double sliderValue) async {
    setCurrentSliderValue(sliderValue);
    setIsMuted(sliderValue == 0);
    final effectivePercent = _sliderToOutputVolumePercent(sliderValue);
    unawaited(PlaybackStateService.saveVolume(effectivePercent));
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSetVolume?.call(effectivePercent);
      _pushSessionIfHosting();
      return;
    }
    await player.setVolume(effectivePercent / 100);
    _pushSessionIfHosting();
  }

  void setArtist(String artist) {
    artistName = artist;
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void setArtistId(String? artistId) {
    currentArtistId = artistId;
    notifyListeners();
  }

  void setSongName(String name) {
    songName = name;
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void setCurrentSongPath(String? path) {
    needsResumeLoad = false;
    _finalizeActivePlay();
    if (path != null && path.trim().isNotEmpty) _beginActivePlay(path);
    currentSongPath = path;
    _completionHandledForCurrentTrack = false;
    notifyListeners();
    _scheduleDiscordPresenceSync(allowReconnect: true);
    unawaited(_persistLastPlayedSong());
    _persistQueueState();
  }

  void setCoverImageBytes(Uint8List? bytes) {
    coverImageBytes = bytes;
    notifyListeners();
  }

  void setProgress(Duration value) {
    if (isSeeking) return;
    progress = value;
    _trackActiveProgress(value);
    notifyListeners();
  }

  void startSeeking(Duration value) {
    isSeeking = true;
    seekPreview = value;
    notifyListeners();
  }

  void updateSeekPreview(Duration value) {
    seekPreview = value;
    notifyListeners();
  }

  void endSeeking(Duration value) {
    isSeeking = false;
    progress = value;
    seekPreview = value;
    notifyListeners();
    _scheduleDiscordPresenceSync();
    _persistQueueState();
  }

  void setDuration(Duration? value) {
    duration = value;
    _trackActiveDuration(value);
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void _maybeCacheDriveDuration(Duration? liveDuration) {
    if (liveDuration == null || liveDuration <= Duration.zero) return;
    final path = currentSongPath;
    if (path == null || !path.startsWith(driveTrackIdPrefix)) return;
    final fileId = path.substring(driveTrackIdPrefix.length);
    if (fileId.isEmpty) return;
    unawaited(DriveDurationCacheService.setDuration(fileId, liveDuration));
  }

  void setIsPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
    _scheduleDiscordPresenceSync();
    if (!value) _persistQueueState();
  }

  void setIsMuted(bool value) {
    isMuted = value;
    notifyListeners();
  }

  void setCurrentSliderValue(double value) {
    currentSliderValue = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _finalizeActivePlay();
    _discordPresenceTimer?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _completedSubscription?.cancel();
    _remoteSessionSub?.cancel();
    _incomingCommandsSub?.cancel();
    _sessionHeartbeat?.cancel();
    _positionAutosaveTimer?.cancel();
    _volumeCommandThrottle?.cancel();
    _sleepTimer?.cancel();
    unawaited(_discordRpc?.clearPresence());
    unawaited(_discordRpc?.dispose());
    super.dispose();
  }
}
