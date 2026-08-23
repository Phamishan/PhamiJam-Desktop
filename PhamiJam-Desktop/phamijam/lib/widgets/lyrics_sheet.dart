import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/services/lyrics_service.dart';
import 'package:provider/provider.dart';

class LyricsSheet extends StatefulWidget {
  const LyricsSheet({super.key});

  @override
  State<LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<LyricsSheet> {
  late final PlaybackModel _playback;
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = {};

  String? _videoId;
  SongLyrics? _lyrics;
  bool _loading = true;
  String? _error;
  int _syncOffsetMs = 0;
  int _lastActiveIndex = -1;
  bool _userScrolling = false;
  bool _isAutoScrolling = false;
  Timer? _resumeAutoScrollTimer;

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackModel>();
    _playback.addListener(_handlePlaybackChanged);
    _load();
  }

  @override
  void dispose() {
    _playback.removeListener(_handlePlaybackChanged);
    _resumeAutoScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (_isAutoScrolling) return false;
    if (notification is ScrollStartNotification) {
      _resumeAutoScrollTimer?.cancel();
      _userScrolling = true;
    } else if (notification is ScrollEndNotification) {
      _resumeAutoScrollTimer?.cancel();
      _resumeAutoScrollTimer = Timer(const Duration(seconds: 4), () {
        _userScrolling = false;
      });
    }
    return false;
  }

  String? get _currentVideoId => _playback.currentYouTubeVideoId;

  void _handlePlaybackChanged() {
    final videoId = _currentVideoId;
    if (videoId != _videoId) {
      _load();
      return;
    }
    _maybeAutoScroll();
  }

  Future<void> _load() async {
    final videoId = _currentVideoId;
    _videoId = videoId;
    _lineKeys.clear();
    setState(() {
      _loading = true;
      _error = null;
      _lyrics = null;
      _lastActiveIndex = -1;
    });

    if (videoId == null || videoId.isEmpty) {
      setState(() {
        _loading = false;
        _error = "This track can't show lyrics.";
      });
      return;
    }

    try {
      final lyrics = await LyricsService.fetchFor(
        videoId,
        title: _playback.songName,
        artist: _playback.artistName,
        durationSeconds: _playback.duration?.inSeconds,
      );
      final offset = await LyricsService.getSyncOffsetMs(videoId);
      if (!mounted || _currentVideoId != videoId) return;
      setState(() {
        _lyrics = lyrics;
        _syncOffsetMs = offset;
        _loading = false;
        _error = (lyrics == null || !lyrics.hasAny)
            ? 'No lyrics found for this song.'
            : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = "Couldn't load lyrics.";
      });
    }
  }

  Duration get _effectivePosition =>
      _playback.progress + Duration(milliseconds: _syncOffsetMs);

  int _activeLineIndex() {
    final synced = _lyrics?.synced;
    if (synced == null || synced.isEmpty) return -1;
    final position = _effectivePosition;
    for (var i = synced.length - 1; i >= 0; i--) {
      if (position >= synced[i].start) return i;
    }
    return -1;
  }

  void _maybeAutoScroll() {
    final synced = _lyrics?.synced;
    if (synced == null || synced.isEmpty) return;
    final index = _activeLineIndex();
    if (index < 0 || index == _lastActiveIndex) return;
    _lastActiveIndex = index;
    if (!mounted) return;
    setState(() {});
    if (_userScrolling) return;
    final lineContext = _lineKeys[index]?.currentContext;
    if (lineContext == null) return;
    _isAutoScrolling = true;
    Scrollable.ensureVisible(
      lineContext,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: 0.4,
    ).then((_) => _isAutoScrolling = false);
  }

  Future<void> _adjustOffset(int deltaMs) async {
    final videoId = _videoId;
    if (videoId == null) return;
    final next = _syncOffsetMs + deltaMs;
    setState(() => _syncOffsetMs = next);
    await LyricsService.setSyncOffsetMs(videoId, next);
  }

  void _seekToLine(LyricLine line) {
    final target = line.start - Duration(milliseconds: _syncOffsetMs);
    _playback.seekTo(target < Duration.zero ? Duration.zero : target);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final onSheet = colorScheme.onInverseSurface;

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playback.songName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: onSheet,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        _playback.artistName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: onSheet.withValues(alpha: 0.7)),
                      ),
                      if ((_lyrics?.source ?? '').isNotEmpty)
                        Text(
                          'Lyrics via ${_lyrics!.source}',
                          style: TextStyle(
                            color: onSheet.withValues(alpha: 0.5),
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: Icon(Icons.close_rounded, color: onSheet),
                ),
              ],
            ),
          ),
          Divider(color: onSheet.withValues(alpha: 0.12), height: 1),
          Expanded(child: _buildBody(context, onSheet)),
          if (_lyrics?.hasSynced == true) _buildSyncControls(onSheet),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, Color onSheet) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lyrics_outlined,
                size: 40,
                color: onSheet.withValues(alpha: 0.5),
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: onSheet.withValues(alpha: 0.7)),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }

    final lyrics = _lyrics;
    if (lyrics == null || !lyrics.hasAny) {
      return const SizedBox.shrink();
    }

    if (lyrics.hasSynced) {
      final synced = lyrics.synced!;
      final activeIndex = _activeLineIndex();
      return NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          itemCount: synced.length,
          itemBuilder: (context, i) {
            final key = _lineKeys.putIfAbsent(i, () => GlobalKey());
            final isActive = i == activeIndex;
            return Padding(
              key: key,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () => _seekToLine(synced[i]),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 200),
                    style: TextStyle(
                      color: isActive
                          ? onSheet
                          : onSheet.withValues(alpha: 0.5),
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 18,
                    ),
                    child: Text(synced[i].text),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Text(
        lyrics.plainText ?? '',
        style: TextStyle(color: onSheet, fontSize: 15, height: 1.5),
      ),
    );
  }

  Widget _buildSyncControls(Color onSheet) {
    final seconds = (_syncOffsetMs / 1000).toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => _adjustOffset(-250),
            icon: Icon(Icons.remove_rounded, color: onSheet),
          ),
          Text(
            _syncOffsetMs == 0
                ? 'Synced'
                : '${_syncOffsetMs > 0 ? '+' : ''}${seconds}s',
            style: TextStyle(color: onSheet.withValues(alpha: 0.7)),
          ),
          IconButton(
            onPressed: () => _adjustOffset(250),
            icon: Icon(Icons.add_rounded, color: onSheet),
          ),
          if (_syncOffsetMs != 0)
            TextButton(
              onPressed: () => _adjustOffset(-_syncOffsetMs),
              child: const Text('Reset'),
            ),
        ],
      ),
    );
  }
}
