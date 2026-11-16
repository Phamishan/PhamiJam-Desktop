import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:phamijam/components/audio_player.dart';

class CrossfadeController {
  AppAudioPlayer? _fadePlayer;
  Timer? _timer;
  bool _active = false;
  Future<void> Function(double volume0to100)? _restoreMainVolume;
  double _targetVolume = 100;
  static const Duration _rampSafetyMargin = Duration(milliseconds: 150);

  bool get isActive => _active;

  Future<void> begin({
    required Future<void> Function(AppAudioPlayer fadePlayer) load,
    required Duration crossfadeDuration,
    required double targetVolume,
    required Duration Function() remainingOnMain,
    required Future<void> Function(double volume0to100) setMainVolume,
    required Future<void> Function(Duration startAt) onComplete,
    Future<void> Function(Duration startHint)? prepareMain,
    Future<void> Function(Duration position)? startMain,
    void Function(Duration position)? onProgress,
  }) async {
    cancel();
    debugPrint('[crossfade] begin: opening next track on fade player');
    final fadePlayer = AppAudioPlayer();
    _fadePlayer = fadePlayer;
    _active = true;
    _restoreMainVolume = setMainVolume;
    _targetVolume = targetVolume;

    final loadStopwatch = Stopwatch()..start();
    try {
      await fadePlayer.setVolume(0);
      await load(fadePlayer).timeout(const Duration(seconds: 12));
    } catch (error, stackTrace) {
      debugPrint(
        '[crossfade] load FAILED after ${loadStopwatch.elapsedMilliseconds}ms: $error\n$stackTrace',
      );
      if (identical(_fadePlayer, fadePlayer)) {
        _active = false;
        _fadePlayer = null;
        _restoreMainVolume = null;
      }
      try {
        await fadePlayer.stop();
      } catch (_) {}
      unawaited(_safeDispose(fadePlayer));
      return;
    }
    if (!_active || !identical(_fadePlayer, fadePlayer)) {
      debugPrint('[crossfade] cancelled during load, aborting');
      return;
    }
    debugPrint(
      '[crossfade] load complete in ${loadStopwatch.elapsedMilliseconds}ms',
    );

    final remaining = remainingOnMain();
    final cappedMs = (remaining - _rampSafetyMargin).inMilliseconds;
    final totalMs =
        (crossfadeDuration.inMilliseconds < cappedMs
                ? crossfadeDuration.inMilliseconds
                : cappedMs)
            .clamp(1, 1 << 30);
    debugPrint(
      '[crossfade] remainingOnMain=$remaining nominalDuration=$crossfadeDuration -> rampMs=$totalMs',
    );

    final stopwatch = Stopwatch()..start();
    final completer = Completer<void>();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!_active || !identical(_fadePlayer, fadePlayer)) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
        return;
      }
      final t = (stopwatch.elapsedMilliseconds / totalMs).clamp(0.0, 1.0);
      final fadeIn = sin(t * pi / 2);
      final fadeOut = cos(t * pi / 2);
      unawaited(_safeSetVolume(fadePlayer, fadeIn * targetVolume / 100));
      unawaited(setMainVolume(fadeOut * targetVolume));
      onProgress?.call(fadePlayer.position);
      if (t >= 1.0) {
        timer.cancel();
        if (!completer.isCompleted) completer.complete();
      }
    });
    await completer.future;

    if (!_active || !identical(_fadePlayer, fadePlayer)) {
      debugPrint('[crossfade] cancelled during ramp, aborting handoff');
      return;
    }
    final startAt = fadePlayer.position;
    debugPrint(
      '[crossfade] ramp complete in ${stopwatch.elapsedMilliseconds}ms, handing off at $startAt',
    );

    if (prepareMain != null && startMain != null) {
      final seamless = await _seamlessHandoff(
        fadePlayer: fadePlayer,
        targetVolume: targetVolume,
        setMainVolume: setMainVolume,
        prepareMain: prepareMain,
        startMain: startMain,
        onProgress: onProgress,
      );
      if (seamless) return;
      if (!_active || !identical(_fadePlayer, fadePlayer)) {
        debugPrint('[crossfade] cancelled during seamless handoff');
        return;
      }
      debugPrint('[crossfade] seamless handoff failed, falling back');
    }

    final fallbackStartAt = fadePlayer.position;
    _fadePlayer = null;
    _restoreMainVolume = null;
    try {
      await fadePlayer.stop();
    } catch (_) {}
    try {
      await onComplete(fallbackStartAt);
      await setMainVolume(targetVolume);
    } catch (error, stackTrace) {
      debugPrint('[crossfade] onComplete FAILED: $error\n$stackTrace');
    } finally {
      _active = false;
    }
    debugPrint('[crossfade] handoff complete');
    unawaited(_safeDispose(fadePlayer));
  }

  static const Duration _seekCompensation = Duration(milliseconds: 120);
  static const Duration _crossRamp = Duration(milliseconds: 150);

  Future<bool> _seamlessHandoff({
    required AppAudioPlayer fadePlayer,
    required double targetVolume,
    required Future<void> Function(double volume0to100) setMainVolume,
    required Future<void> Function(Duration startHint) prepareMain,
    required Future<void> Function(Duration position) startMain,
    void Function(Duration position)? onProgress,
  }) async {
    final progressTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      onProgress?.call(fadePlayer.position);
    });
    final prepareWatch = Stopwatch()..start();
    try {
      await prepareMain(
        fadePlayer.position,
      ).timeout(const Duration(seconds: 12));
    } catch (error, stackTrace) {
      debugPrint(
        '[crossfade] prepareMain FAILED after ${prepareWatch.elapsedMilliseconds}ms: $error\n$stackTrace',
      );
      progressTimer.cancel();
      return false;
    }
    progressTimer.cancel();
    if (!_active || !identical(_fadePlayer, fadePlayer)) return false;
    debugPrint(
      '[crossfade] main prepared in ${prepareWatch.elapsedMilliseconds}ms',
    );

    try {
      await setMainVolume(0);
      await startMain(fadePlayer.position + _seekCompensation);
    } catch (error, stackTrace) {
      debugPrint('[crossfade] startMain FAILED: $error\n$stackTrace');
      return false;
    }
    if (!_active || !identical(_fadePlayer, fadePlayer)) return false;

    final rampWatch = Stopwatch()..start();
    final rampMs = _crossRamp.inMilliseconds;
    while (rampWatch.elapsedMilliseconds < rampMs) {
      if (!_active || !identical(_fadePlayer, fadePlayer)) return true;
      final t = (rampWatch.elapsedMilliseconds / rampMs).clamp(0.0, 1.0);
      unawaited(setMainVolume(sin(t * pi / 2) * targetVolume));
      unawaited(
        _safeSetVolume(fadePlayer, cos(t * pi / 2) * targetVolume / 100),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    await setMainVolume(targetVolume);

    _fadePlayer = null;
    _restoreMainVolume = null;
    try {
      await fadePlayer.stop();
    } catch (_) {}
    _active = false;
    debugPrint('[crossfade] seamless handoff complete');
    unawaited(_safeDispose(fadePlayer));
    return true;
  }

  Future<void> _safeSetVolume(AppAudioPlayer fadePlayer, double volume) async {
    try {
      await fadePlayer.setVolume(volume);
    } catch (_) {}
  }

  Future<void> _safeDispose(AppAudioPlayer fadePlayer) async {
    try {
      await fadePlayer.dispose();
    } catch (_) {}
  }

  void cancel() {
    if (!_active && _fadePlayer == null) return;
    debugPrint('[crossfade] cancel() called');
    _active = false;
    _timer?.cancel();
    _timer = null;

    final restore = _restoreMainVolume;
    final target = _targetVolume;
    _restoreMainVolume = null;
    if (restore != null) {
      unawaited(restore(target));
    }

    final fadePlayer = _fadePlayer;
    _fadePlayer = null;
    if (fadePlayer != null) {
      unawaited(() async {
        try {
          await fadePlayer.stop();
        } catch (_) {}
        try {
          await fadePlayer.dispose();
        } catch (_) {}
      }());
    }
  }

  void dispose() => cancel();
}
