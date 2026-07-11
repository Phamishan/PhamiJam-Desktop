import 'dart:async';
import 'dart:math';
import 'dart:typed_data';
import 'package:dart_discord_presence/dart_discord_presence.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:phamijam/components/audio_player.dart';

enum PlaybackEngine { local, youtube }

class PlaybackModel extends ChangeNotifier {
  static const int _queueAheadCount = 4;
  static const Duration _discordPresenceDebounce = Duration(milliseconds: 50);
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

  String artistName = 'Unknown Artist';
  String songName = 'Unknown Song';
  String? currentSongPath;
  Uint8List? coverImageBytes;
  String? currentYouTubeVideoId;
  Duration progress = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  bool isMuted = false;
  bool isShuffled = false;
  bool isLooped = false;
  double currentSliderValue = 20.0;
  bool isSeeking = false;
  Duration seekPreview = Duration.zero;
  List<dynamic> queue = [];

  List<dynamic> _playlistItems = [];
  List<int> _playOrder = [];
  int _currentOrderIndex = -1;

  Duration get displayedProgress => isSeeking ? seekPreview : progress;
  PlaybackEngine get engine => _engine;

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
    final total = duration;
    if (total == null || total <= Duration.zero) return false;

    final current = progress;
    if (current <= Duration.zero) return false;

    final remaining = total - current;
    return remaining <= const Duration(milliseconds: 800);
  }

  Future<void> _triggerTrackCompletedIfNeeded() async {
    if (_completionHandledForCurrentTrack) return;
    if (!_isNearTrackEnd()) return;

    _completionHandledForCurrentTrack = true;
    if (isLooped) {
      await _restartCurrentTrack();
      unawaited(
        Future<void>.delayed(const Duration(milliseconds: 150), () {
          return _syncDiscordPresence(force: true);
        }),
      );
      return;
    }
    await playNext(wrapAround: true);
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
    setProgress(Duration.zero);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSeek?.call(Duration.zero);
      await _youtubePlay?.call();
      _completionHandledForCurrentTrack = false;
      return;
    }

    await player.seek(Duration.zero);
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
      shouldNotify = true;
    }

    if (totalDuration != null && duration != totalDuration) {
      duration = totalDuration;
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
        .listen(setProgress);

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
      state: artist,
      timestamps: _buildProgressTimestamps(),
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

  void clearPlaylistQueue() {
    _playlistItems = [];
    _playOrder = [];
    _currentOrderIndex = -1;
    queue = [];
    notifyListeners();
  }

  void setPlaylistQueue(List<dynamic> items, {required int startIndex}) {
    if (items.isEmpty || startIndex < 0 || startIndex >= items.length) {
      _playlistItems = [];
      _playOrder = [];
      _currentOrderIndex = -1;
      queue = [];
      notifyListeners();
      return;
    }

    _playlistItems = List<dynamic>.from(items);
    _rebuildPlayOrder(startIndex: startIndex);
    _currentOrderIndex = 0;
    _refreshQueueWindow();
    unawaited(_prefetchAhead());
    notifyListeners();
  }

  void addToQueue(dynamic item) {
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
  }

  Future<void> playQueueIndex(int queueIndex) async {
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    if (_currentOrderIndex < 0) return;

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

  Future<void> playPrevious() async {
    if (_playOrder.isNotEmpty) {
      final previousOrderIndex = _normalizeOrderIndex(_currentOrderIndex - 1);
      if (previousOrderIndex == null) {
        return;
      }

      _currentOrderIndex = previousOrderIndex;
      _refreshQueueWindow();
      notifyListeners();

      await _playBySourceIndex(_playOrder[previousOrderIndex]);
      _forceDiscordPresenceRefreshAfterTrackChange();
      unawaited(_prefetchAhead());
    }
  }

  Future<void> playNext({bool wrapAround = false}) async {
    if (_playOrder.isNotEmpty) {
      final nextOrderIndex = _normalizeOrderIndex(
        _currentOrderIndex + 1,
        wrapAround: wrapAround,
      );
      if (nextOrderIndex == null) {
        return;
      }

      _currentOrderIndex = nextOrderIndex;
      _refreshQueueWindow();
      notifyListeners();

      await _playBySourceIndex(_playOrder[nextOrderIndex]);
      _forceDiscordPresenceRefreshAfterTrackChange();
      unawaited(_prefetchAhead());
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
    setProgress(value);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSeek?.call(value);
    } else {
      await player.seek(value);
    }
    _scheduleDiscordPresenceSync();
  }

  Future<void> togglePlayPause() async {
    if (_engine == PlaybackEngine.youtube) {
      if (isPlaying) {
        await _youtubePause?.call();
        setIsPlaying(false);
      } else {
        await _youtubePlay?.call();
        setIsPlaying(true);
      }
      return;
    }

    if (isPlaying) {
      await player.pause();
    } else {
      await player.play();
    }
  }

  void toggleShuffle() {
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
  }

  void toggleLoop() {
    isLooped = !isLooped;
    if (_playlistItems.isNotEmpty) {
      _refreshQueueWindow();
    }
    notifyListeners();
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
    final endOffset = _queueAheadCount;
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

  Future<void> applyVolume(double sliderValue) async {
    setCurrentSliderValue(sliderValue);
    setIsMuted(sliderValue == 0);
    final effectivePercent = _sliderToOutputVolumePercent(sliderValue);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSetVolume?.call(effectivePercent);
      return;
    }
    await player.setVolume(effectivePercent / 100);
  }

  void setArtist(String artist) {
    artistName = artist;
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void setSongName(String name) {
    songName = name;
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void setCurrentSongPath(String? path) {
    currentSongPath = path;
    _completionHandledForCurrentTrack = false;
    notifyListeners();
    _scheduleDiscordPresenceSync(allowReconnect: true);
  }

  void setCoverImageBytes(Uint8List? bytes) {
    coverImageBytes = bytes;
    notifyListeners();
  }

  void setProgress(Duration value) {
    if (isSeeking) return;
    progress = value;
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
  }

  void setDuration(Duration? value) {
    duration = value;
    notifyListeners();
    _scheduleDiscordPresenceSync();
  }

  void setIsPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
    _scheduleDiscordPresenceSync();
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
    _discordPresenceTimer?.cancel();
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _completedSubscription?.cancel();
    unawaited(_discordRpc?.clearPresence());
    unawaited(_discordRpc?.dispose());
    super.dispose();
  }
}
