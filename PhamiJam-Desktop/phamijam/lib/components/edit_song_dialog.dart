import 'dart:async';

import 'package:flutter/material.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/providers/edited_songs_provider.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:provider/provider.dart';

Future<void> showEditSongDialog(
  BuildContext context, {
  required String videoId,
  required String title,
  required String artist,
  String thumbnailUrl = '',
  int durationSeconds = 0,
}) async {
  if (videoId.isEmpty) return;
  final existing = context.read<EditedSongsProvider>().trimFor(videoId);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => _EditSongDialog(
      videoId: videoId,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl,
      durationSeconds: durationSeconds,
      existing: existing,
    ),
  );
}

class _EditSongDialog extends StatefulWidget {
  const _EditSongDialog({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.durationSeconds,
    this.existing,
  });

  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int durationSeconds;
  final EditedSongTrim? existing;

  @override
  State<_EditSongDialog> createState() => _EditSongDialogState();
}

class _EditSongDialogState extends State<_EditSongDialog> {
  late double _startSeconds;
  late double _endSeconds;
  int _durationSeconds = 0;
  bool _loadingDuration = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _durationSeconds = widget.durationSeconds;
    _initRange();
    if (_durationSeconds <= 0) {
      _loadingDuration = true;
      unawaited(_fetchDuration());
    }
  }

  void _initRange() {
    final total = _durationSeconds > 0 ? _durationSeconds.toDouble() : 0.0;
    final existing = widget.existing;
    _startSeconds = existing != null ? existing.startMs / 1000 : 0;
    _endSeconds = existing != null ? existing.endMs / 1000 : total;
    if (_endSeconds <= _startSeconds) {
      _endSeconds = total > _startSeconds ? total : _startSeconds + 1;
    }
  }

  Future<void> _fetchDuration() async {
    try {
      final seconds = await YoutubePlaylistService.fetchVideoDurationSeconds(
        widget.videoId,
      );
      if (!mounted) return;
      setState(() {
        _durationSeconds = seconds;
        _loadingDuration = false;
        _initRange();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingDuration = false);
    }
  }

  String _formatSeconds(double seconds) {
    final duration = Duration(seconds: seconds.round());
    final minutes = duration.inMinutes;
    final secs = duration.inSeconds % 60;
    return '$minutes:${secs.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final trim = EditedSongTrim(
      videoId: widget.videoId,
      startMs: (_startSeconds * 1000).round(),
      endMs: (_endSeconds * 1000).round(),
      title: widget.title,
      artist: widget.artist,
      thumbnailUrl: widget.thumbnailUrl,
    );
    try {
      await context.read<EditedSongsProvider>().saveTrim(trim);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save trim: $error')));
    }
  }

  Future<void> _remove() async {
    setState(() => _saving = true);
    try {
      await context.read<EditedSongsProvider>().removeTrim(widget.videoId);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to reset trim: $error')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasDuration = _durationSeconds > 0;
    return AlertDialog(
      title: const Text('Edit song'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              widget.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (_loadingDuration)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (hasDuration) ...[
              Text(
                'Plays from ${_formatSeconds(_startSeconds)} to '
                '${_formatSeconds(_endSeconds)}',
              ),
              RangeSlider(
                values: RangeValues(_startSeconds, _endSeconds),
                min: 0,
                max: _durationSeconds.toDouble(),
                divisions: _durationSeconds,
                labels: RangeLabels(
                  _formatSeconds(_startSeconds),
                  _formatSeconds(_endSeconds),
                ),
                onChanged: _saving
                    ? null
                    : (values) {
                        setState(() {
                          _startSeconds = values.start;
                          _endSeconds = values.end;
                        });
                      },
              ),
            ] else
              const Text(
                "This song's duration couldn't be found, so trimming isn't "
                'available.',
              ),
          ],
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _saving ? null : _remove,
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Reset'),
          ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: (_saving || _loadingDuration || !hasDuration)
              ? null
              : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
