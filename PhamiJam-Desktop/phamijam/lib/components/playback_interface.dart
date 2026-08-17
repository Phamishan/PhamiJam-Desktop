import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:marquee/marquee.dart';
import 'package:audio_video_progress_bar/audio_video_progress_bar.dart';
import 'package:phamijam/components/playback_model.dart';

class PlaybackInterface extends StatefulWidget {
  final Duration progress;
  final Duration? duration;
  final bool isPlaying;
  final bool isMuted;
  final bool isShuffled;
  final PlayerRepeatMode repeatMode;
  final double currentSliderValue;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onPlayPauseToggle;
  final VoidCallback onPrevious;
  final VoidCallback onForward;
  final ValueChanged<double> onVolumeChange;
  final VoidCallback onCycleRepeat;
  final VoidCallback onShuffle;
  final VoidCallback onUnshuffle;
  final String artist;
  final String songName;
  final List<dynamic> queue;
  final VoidCallback onQueuePressed;
  final VoidCallback? onArtistTap;
  final VoidCallback? onLyricsPressed;
  final VoidCallback? onSleepTimerPressed;
  final VoidCallback? onSharePressed;
  final VoidCallback? onSharePlaylistPressed;
  final bool hasSleepTimer;

  const PlaybackInterface({
    super.key,
    required this.progress,
    required this.duration,
    required this.isPlaying,
    required this.isMuted,
    required this.currentSliderValue,
    required this.onSeek,
    required this.onPlayPauseToggle,
    required this.isShuffled,
    required this.repeatMode,
    required this.onPrevious,
    required this.onForward,
    required this.onVolumeChange,
    required this.onCycleRepeat,
    required this.onShuffle,
    required this.onUnshuffle,
    required this.artist,
    required this.songName,
    required this.queue,
    required this.onQueuePressed,
    this.onArtistTap,
    this.onLyricsPressed,
    this.onSleepTimerPressed,
    this.onSharePressed,
    this.onSharePlaylistPressed,
    this.hasSleepTimer = false,
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

  void toggleShuffled() {
    if (widget.isShuffled) {
      widget.onUnshuffle();
    } else {
      widget.onShuffle();
    }
  }

  Widget _buildShareButton(ColorScheme colorScheme) {
    final shareSong = widget.onSharePressed;
    final sharePlaylist = widget.onSharePlaylistPressed;
    if (shareSong == null && sharePlaylist == null) {
      return const SizedBox.shrink();
    }
    if (sharePlaylist == null) {
      return IconButton(
        onPressed: shareSong,
        tooltip: 'Share song',
        icon: Icon(Icons.share_rounded, color: colorScheme.primary),
      );
    }
    return PopupMenuButton<String>(
      tooltip: 'Share',
      icon: Icon(Icons.share_rounded, color: colorScheme.primary),
      splashRadius: 16,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      onSelected: (value) {
        if (value == 'share_song') {
          shareSong?.call();
        } else if (value == 'share_playlist') {
          sharePlaylist.call();
        }
      },
      itemBuilder: (context) => [
        if (shareSong != null)
          const PopupMenuItem(
            value: 'share_song',
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.music_note_rounded),
              title: Text('Share song'),
            ),
          ),
        const PopupMenuItem(
          value: 'share_playlist',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.queue_music_rounded),
            title: Text('Share playlist'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
              thumbColor: colorScheme.primary,
              baseBarColor: colorScheme.onSurfaceVariant,
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
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
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
                                      style: TextStyle(
                                        color: colorScheme.onSurface,
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                            ),
                            widget.onArtistTap == null
                                ? Text(
                                    widget.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  )
                                : MouseRegion(
                                    cursor: SystemMouseCursors.click,
                                    child: GestureDetector(
                                      onTap: widget.onArtistTap,
                                      child: Text(
                                        widget.artist,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: colorScheme.onSurfaceVariant,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          decoration: TextDecoration.underline,
                                        ),
                                      ),
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
                      onPressed: toggleShuffled,
                      icon: !widget.isShuffled
                          ? Icon(
                              Icons.shuffle_rounded,
                              color: colorScheme.primary,
                            )
                          : Icon(
                              Icons.shuffle_on_rounded,
                              color: colorScheme.primary,
                            ),
                    ),
                    IconButton(
                      onPressed: widget.onPrevious,
                      icon: Icon(
                        Icons.skip_previous_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onPlayPauseToggle,
                      icon: widget.isPlaying
                          ? Icon(
                              Icons.pause_circle_rounded,
                              color: colorScheme.primary,
                            )
                          : Icon(
                              Icons.play_circle_rounded,
                              color: colorScheme.primary,
                            ),
                    ),
                    IconButton(
                      onPressed: widget.onForward,
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: colorScheme.primary,
                      ),
                    ),
                    IconButton(
                      onPressed: widget.onCycleRepeat,
                      icon: Icon(switch (widget.repeatMode) {
                        PlayerRepeatMode.off => Icons.repeat_rounded,
                        PlayerRepeatMode.all => Icons.repeat_on_rounded,
                        PlayerRepeatMode.one => Icons.repeat_one_on_rounded,
                      }, color: colorScheme.primary),
                    ),
                    if (widget.onSleepTimerPressed != null)
                      IconButton(
                        onPressed: widget.onSleepTimerPressed,
                        icon: Icon(
                          widget.hasSleepTimer
                              ? Icons.bedtime_rounded
                              : Icons.bedtime_outlined,
                          color: colorScheme.primary,
                        ),
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
                        _buildShareButton(colorScheme),
                        if (widget.onLyricsPressed != null)
                          IconButton(
                            onPressed: widget.onLyricsPressed,
                            icon: Icon(
                              Icons.lyrics_outlined,
                              color: colorScheme.primary,
                            ),
                          ),
                        IconButton(
                          onPressed: widget.onQueuePressed,
                          icon: Icon(
                            Icons.queue_music_rounded,
                            color: colorScheme.primary,
                          ),
                        ),
                        IconButton(
                          onPressed: handleToggleVolume,
                          icon: !widget.isMuted
                              ? Icon(
                                  Icons.volume_up_rounded,
                                  color: colorScheme.primary,
                                )
                              : Icon(
                                  Icons.volume_off_rounded,
                                  color: colorScheme.primary,
                                ),
                        ),
                        SizedBox(
                          width: 200,
                          child: Slider(
                            thumbColor: colorScheme.primary,
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
                            style: TextStyle(
                              color: colorScheme.primary,
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
                                borderSide: BorderSide(
                                  color: colorScheme.onSurfaceVariant,
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
                        Text(
                          '%',
                          style: TextStyle(
                            color: colorScheme.primary,
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
