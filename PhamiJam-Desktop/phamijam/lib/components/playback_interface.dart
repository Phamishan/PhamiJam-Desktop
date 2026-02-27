import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marquee/marquee.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';

class PlaybackInterface extends StatefulWidget {
  final Duration progress;
  final Duration? duration;
  final bool isPlaying;
  final bool isMuted;
  final double currentSliderValue;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPauseToggle;
  final VoidCallback onPrevious;
  final VoidCallback onForward;
  final ValueChanged<double> onVolumeChange;
  final String artist;
  final String songName;

  const PlaybackInterface({
    super.key,
    required this.progress,
    required this.duration,
    required this.isPlaying,
    required this.isMuted,
    required this.currentSliderValue,
    required this.onSeek,
    required this.onPlayPauseToggle,
    required this.onPrevious,
    required this.onForward,
    required this.onVolumeChange,
    required this.artist,
    required this.songName,
  });

  @override
  State<PlaybackInterface> createState() => _PlaybackInterfaceState();
}

class _PlaybackInterfaceState extends State<PlaybackInterface> {
  double? oldVolume;
  late final TextEditingController _volumeController;
  late final FocusNode _volumeFocusNode;

  @override
  void initState() {
    super.initState();
    _volumeController = TextEditingController(
      text: widget.currentSliderValue.round().toString(),
    );
    _volumeFocusNode = FocusNode();
  }

  @override
  void didUpdateWidget(covariant PlaybackInterface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldValue = oldWidget.currentSliderValue.round();
    final newValue = widget.currentSliderValue.round();
    if (oldValue != newValue && !_volumeFocusNode.hasFocus) {
      _volumeController.text = newValue.toString();
    }
  }

  @override
  void dispose() {
    _volumeController.dispose();
    _volumeFocusNode.dispose();
    super.dispose();
  }

  bool _shouldMarquee(String text) => text.trim().length > 28;

  void handleToggleVolume() {
    if (widget.currentSliderValue > 0) {
      oldVolume = widget.currentSliderValue;
      widget.onVolumeChange(0);
    } else {
      final restoredVolume = (oldVolume != null && oldVolume! > 0)
          ? oldVolume!
          : 20.0;
      widget.onVolumeChange(restoredVolume);
    }
  }

  void handleSliderChange(double value) {
    widget.onVolumeChange(value);
    if (!_volumeFocusNode.hasFocus) {
      _volumeController.text = value.round().toString();
    }
    if (value > 0) oldVolume = value;
  }

  void _applyTypedVolume() {
    final parsed = double.tryParse(_volumeController.text.trim());
    final clamped = (parsed ?? widget.currentSliderValue).clamp(0, 100);
    final value = clamped.toDouble();
    _volumeController.text = value.round().toString();
    widget.onVolumeChange(value);
    if (value > 0) oldVolume = value;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      width: MediaQuery.of(context).size.width,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 10),
            child: ProgressBar(
              progress: widget.progress,
              total: widget.duration ?? Duration.zero,
              thumbGlowRadius: 25,
              thumbRadius: 10,
              thumbColor: Color(0xFF121212),
              baseBarColor: Color(0xFFece1d4),
              onSeek: widget.onSeek,
            ),
          ),
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Song info (left)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(left: 10),
                    child: SizedBox(
                      width: 220,
                      child: Tooltip(
                        message: '${widget.songName}\n${widget.artist}',
                        waitDuration: const Duration(milliseconds: 500),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 22,
                              child: _shouldMarquee(widget.songName)
                                  ? Marquee(
                                      text: widget.songName,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      scrollAxis: Axis.horizontal,
                                      blankSpace: 36,
                                      velocity: 26,
                                      pauseAfterRound: const Duration(
                                        milliseconds: 900,
                                      ),
                                      startPadding: 8,
                                      accelerationDuration: const Duration(
                                        milliseconds: 600,
                                      ),
                                      accelerationCurve: Curves.linear,
                                      decelerationDuration: const Duration(
                                        milliseconds: 450,
                                      ),
                                      decelerationCurve: Curves.easeOut,
                                    )
                                  : Text(
                                      widget.songName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            Text(
                              widget.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Control buttons (center)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: widget.onPrevious,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: Colors.black,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onPlayPauseToggle,
                      icon: widget.isPlaying
                          ? Icon(
                              Icons.pause_circle_outline_rounded,
                              color: Colors.black,
                            )
                          : Icon(Icons.play_arrow_rounded, color: Colors.black),
                    ),
                    IconButton(
                      onPressed: widget.onForward,
                      icon: Icon(Icons.skip_next_rounded, color: Colors.black),
                    ),
                  ],
                ),
                // Volume controls (right)
                Align(
                  alignment: Alignment.centerRight,
                  child: Padding(
                    padding: EdgeInsets.only(right: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: handleToggleVolume,
                          icon: !widget.isMuted
                              ? Icon(
                                  Icons.volume_up_rounded,
                                  color: Colors.black,
                                )
                              : Icon(
                                  Icons.volume_off_rounded,
                                  color: Colors.black,
                                ),
                        ),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            thumbColor: Color(0xFF121212),
                            value: widget.currentSliderValue,
                            max: 100,
                            onChanged: handleSliderChange,
                          ),
                        ),
                        SizedBox(
                          width: 44,
                          child: TextField(
                            controller: _volumeController,
                            focusNode: _volumeFocusNode,
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(3),
                            ],
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Colors.white70,
                                ),
                              ),
                            ),
                            onSubmitted: (_) => _applyTypedVolume(),
                            onTapOutside: (_) {
                              _applyTypedVolume();
                              _volumeFocusNode.unfocus();
                            },
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Text(
                          '%',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
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
