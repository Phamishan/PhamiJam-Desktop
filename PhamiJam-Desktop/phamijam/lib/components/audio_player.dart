import 'dart:async';

import 'package:media_kit/media_kit.dart';

class AppPlayerState {
  const AppPlayerState({required this.playing});

  final bool playing;
}

class AppAudioPlayer {
  final _player = Player();

  Player get mediaKitPlayer => _player;

  Stream<Duration> createPositionStream({
    Duration? minPeriod,
    Duration? maxPeriod,
  }) {
    final period = maxPeriod ?? minPeriod ?? const Duration(milliseconds: 80);
    return Stream<Duration>.periodic(
      period,
      (_) => _player.state.position,
    ).asBroadcastStream();
  }

  Stream<AppPlayerState> get playerStateStream => _player.stream.playing
      .map((playing) => AppPlayerState(playing: playing))
      .asBroadcastStream();

  Stream<Duration?> get durationStream => _player.stream.duration
      .map((duration) => duration == Duration.zero ? null : duration)
      .asBroadcastStream();

  Stream<double> get volumeStream => _player.stream.volume
      .map((volume) => (volume / 100).clamp(0, 1).toDouble())
      .asBroadcastStream();

  Stream<bool> get completedStream =>
      _player.stream.completed.asBroadcastStream();

  Future<void> setUrl(String url, {Map<String, String>? headers}) async {
    await _player.open(Media(url, httpHeaders: headers), play: false);
  }

  Future<void> setFilePath(String path) async {
    await _player.open(Media(path), play: false);
  }

  Future<void> stop() => _player.stop();

  Future<void> play() => _player.play();

  Future<void> pause() => _player.pause();

  Future<void> seek(Duration position) => _player.seek(position);

  Future<void> setVolume(double volume) {
    final scaled = (volume * 100).clamp(0, 100).toDouble();
    return _player.setVolume(scaled);
  }
}

final AppAudioPlayer player = AppAudioPlayer();
