import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:phamijam/components/audio_player.dart';

enum PlaybackEngine { local, youtube }

class PlaybackModel extends ChangeNotifier {
  static const double _volumeBoostFloor = 65.0;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<AppPlayerState>? _playerStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<double>? _volumeSubscription;
  StreamSubscription<bool>? _completedSubscription;
  bool _isBoundToPlayer = false;
  bool _completionHandledForCurrentTrack = false;
  bool _wasPlaying = false;
  PlaybackEngine _engine = PlaybackEngine.local;

  Future<void> Function(String videoId)? _youtubeLoadVideoById;
  Future<void> Function(String videoId)? _youtubePrefetchVideoById;
  Future<void> Function()? _youtubePlay;
  Future<void> Function()? _youtubePause;
  Future<void> Function(Duration position)? _youtubeSeek;
  Future<void> Function(double sliderValue)? _youtubeSetVolume;
  Future<void> _engineTransition = Future<void>.value();
  Future<void> Function()? _onPreviousRequested;
  Future<void> Function()? _onNextRequested;

  String artistName = 'Unknown Artist';
  String songName = 'Unknown Song';
  String? currentSongPath;
  Uint8List? coverImageBytes;
  String? currentYouTubeVideoId;
  Duration progress = Duration.zero;
  Duration? duration;
  bool isPlaying = false;
  bool isMuted = false;
  double currentSliderValue = 20.0;
  bool isSeeking = false;
  Duration seekPreview = Duration.zero;

  Duration get displayedProgress => isSeeking ? seekPreview : progress;
  PlaybackEngine get engine => _engine;

  double get effectiveVolumePercent =>
      _sliderToOutputVolumePercent(currentSliderValue);

  double _sliderToOutputVolumePercent(double sliderValue) {
    final safeSlider = sliderValue.clamp(0, 100).toDouble();
    if (safeSlider <= 0) return 0;
    final boosted =
        _volumeBoostFloor + ((100 - _volumeBoostFloor) * (safeSlider / 100));
    return boosted.clamp(0, 100).toDouble();
  }

  double _outputToSliderVolumePercent(double outputVolumePercent) {
    final safeOutput = outputVolumePercent.clamp(0, 100).toDouble();
    if (safeOutput <= 0) return 0;
    final slider =
        ((safeOutput - _volumeBoostFloor) / (100 - _volumeBoostFloor)) * 100;
    return slider.clamp(0, 100).toDouble();
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
    await playNext();
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
  }

  void setOnPreviousRequested(Future<void> Function()? callback) {
    _onPreviousRequested = callback;
  }

  void setOnNextRequested(Future<void> Function()? callback) {
    _onNextRequested = callback;
  }

  Future<void> playPrevious() async {
    final callback = _onPreviousRequested;
    if (callback != null) {
      await callback();
    }
  }

  Future<void> playNext() async {
    final callback = _onNextRequested;
    if (callback != null) {
      await callback();
    }
  }

  Future<void> seekTo(Duration value) async {
    setProgress(value);
    if (_engine == PlaybackEngine.youtube) {
      await _youtubeSeek?.call(value);
      return;
    }
    await player.seek(value);
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
  }

  void setSongName(String name) {
    songName = name;
    notifyListeners();
  }

  void setCurrentSongPath(String? path) {
    currentSongPath = path;
    _completionHandledForCurrentTrack = false;
    notifyListeners();
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
  }

  void setDuration(Duration? value) {
    duration = value;
    notifyListeners();
  }

  void setIsPlaying(bool value) {
    isPlaying = value;
    notifyListeners();
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
    _positionSubscription?.cancel();
    _playerStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _volumeSubscription?.cancel();
    _completedSubscription?.cancel();
    super.dispose();
  }
}
