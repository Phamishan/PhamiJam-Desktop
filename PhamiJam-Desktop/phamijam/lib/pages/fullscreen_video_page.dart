import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:phamijam/components/audio_player.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';
import 'package:provider/provider.dart';

class FullscreenVideoPage extends StatefulWidget {
  const FullscreenVideoPage({super.key});

  @override
  State<FullscreenVideoPage> createState() => _FullscreenVideoPageState();
}

class _FullscreenVideoPageState extends State<FullscreenVideoPage> {
  late final VideoController _videoController;
  bool _controlsVisible = true;
  Timer? _hideTimer;
  double? _preMuteVolume;

  static const _autoHideDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _videoController = VideoController(player.mediaKitPlayer);
    _scheduleAutoHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _scheduleAutoHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_autoHideDelay, () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _toggleControls() {
    setState(() => _controlsVisible = !_controlsVisible);
    if (_controlsVisible) {
      _scheduleAutoHide();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _keepAlive() {
    if (!_controlsVisible) {
      setState(() => _controlsVisible = true);
    }
    _scheduleAutoHide();
  }

  void _toggleMute(PlaybackModel playback) {
    if (playback.currentSliderValue > 0) {
      _preMuteVolume = playback.currentSliderValue;
      playback.applyVolume(0);
    } else {
      final restored = (_preMuteVolume != null && _preMuteVolume! > 0)
          ? _preMuteVolume!
          : 60.0;
      playback.applyVolume(restored);
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString();
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackModel>();
    final hasVideo =
        playback.engine == PlaybackEngine.youtube &&
        (playback.currentYouTubeVideoId ?? '').isNotEmpty;
    final total = playback.duration ?? Duration.zero;
    final progressMs = total.inMilliseconds > 0
        ? playback.progress.inMilliseconds
              .clamp(0, total.inMilliseconds)
              .toDouble()
        : 0.0;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Focus(
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is KeyDownEvent &&
                event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).maybePop();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            child: Stack(
              children: [
                if (hasVideo)
                  Center(
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: Video(
                        controller: _videoController,
                        controls: NoVideoControls,
                      ),
                    ),
                  )
                else
                  const Center(
                    child: Text(
                      'No video playing',
                      style: TextStyle(color: Colors.white70),
                    ),
                  ),
                IgnorePointer(
                  ignoring: !_controlsVisible,
                  child: AnimatedOpacity(
                    opacity: _controlsVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.55),
                            Colors.transparent,
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.65),
                          ],
                          stops: const [0, 0.2, 0.7, 1],
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(8),
                            child: Row(
                              children: [
                                ScrimIconButton(
                                  icon: Icons.fullscreen_exit_rounded,
                                  onTap: () => Navigator.of(context).maybePop(),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    '${playback.songName} — ${playback.artistName}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                            child: Row(
                              children: [
                                Text(
                                  _formatDuration(playback.progress),
                                  style: const TextStyle(color: Colors.white),
                                ),
                                Expanded(
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: 0.3),
                                      thumbColor: Colors.white,
                                      trackHeight: 3,
                                    ),
                                    child: Slider(
                                      value: progressMs,
                                      max: total.inMilliseconds > 0
                                          ? total.inMilliseconds.toDouble()
                                          : 1,
                                      onChanged: (value) {
                                        _keepAlive();
                                        playback.seekTo(
                                          Duration(milliseconds: value.round()),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatDuration(total),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 16, 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  onPressed: () {
                                    _keepAlive();
                                    playback.toggleShuffle();
                                  },
                                  icon: Icon(
                                    Icons.shuffle_rounded,
                                    color: playback.isShuffled
                                        ? Colors.white
                                        : Colors.white54,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _keepAlive();
                                    playback.playPrevious();
                                  },
                                  iconSize: 34,
                                  icon: const Icon(
                                    Icons.skip_previous_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () {
                                    _keepAlive();
                                    playback.togglePlayPause();
                                  },
                                  child: Container(
                                    width: 56,
                                    height: 56,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: Icon(
                                      playback.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      color: Colors.black,
                                      size: 30,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  onPressed: () {
                                    _keepAlive();
                                    playback.playNext();
                                  },
                                  iconSize: 34,
                                  icon: const Icon(
                                    Icons.skip_next_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () {
                                    _keepAlive();
                                    playback.cycleRepeatMode();
                                  },
                                  icon: Icon(
                                    playback.repeatMode == PlayerRepeatMode.one
                                        ? Icons.repeat_one_rounded
                                        : Icons.repeat_rounded,
                                    color:
                                        playback.repeatMode ==
                                            PlayerRepeatMode.off
                                        ? Colors.white54
                                        : Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 20),
                                IconButton(
                                  onPressed: () {
                                    _keepAlive();
                                    _toggleMute(playback);
                                  },
                                  icon: Icon(
                                    playback.currentSliderValue <= 0
                                        ? Icons.volume_off_rounded
                                        : playback.currentSliderValue < 50
                                        ? Icons.volume_down_rounded
                                        : Icons.volume_up_rounded,
                                    color: Colors.white,
                                  ),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: SliderTheme(
                                    data: SliderTheme.of(context).copyWith(
                                      activeTrackColor: Colors.white,
                                      inactiveTrackColor: Colors.white
                                          .withValues(alpha: 0.3),
                                      thumbColor: Colors.white,
                                      trackHeight: 3,
                                    ),
                                    child: Slider(
                                      value: playback.currentSliderValue
                                          .clamp(0, 100)
                                          .toDouble(),
                                      max: 100,
                                      onChanged: (value) {
                                        _keepAlive();
                                        playback.applyVolume(value);
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
