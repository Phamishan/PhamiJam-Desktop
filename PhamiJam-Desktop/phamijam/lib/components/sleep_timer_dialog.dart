import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:provider/provider.dart';

const List<int> _sleepTimerPresetMinutes = [5, 10, 15, 30, 45, 60];

void showSleepTimerDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => const _SleepTimerDialog(),
  );
}

class _SleepTimerDialog extends StatelessWidget {
  const _SleepTimerDialog();

  String _remainingLabel(DateTime endsAt) {
    final remaining = endsAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Ending soon';
    final minutes = remaining.inMinutes;
    final seconds = remaining.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')} remaining';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Consumer<PlaybackModel>(
      builder: (context, playback, _) {
        final endsAt = playback.sleepTimerEndsAt;
        final endOfTrack = playback.isSleepTimerEndOfTrackScheduled;
        return AlertDialog(
          title: const Text('Sleep Timer'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (endsAt != null || endOfTrack) ...[
                  Text(
                    endOfTrack
                        ? 'Stopping at the end of this track'
                        : _remainingLabel(endsAt!),
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final minutes in _sleepTimerPresetMinutes)
                      ChoiceChip(
                        label: Text('$minutes min'),
                        selected: false,
                        onSelected: (_) {
                          playback.startSleepTimer(Duration(minutes: minutes));
                          Navigator.of(context).pop();
                        },
                      ),
                    ChoiceChip(
                      label: const Text('End of track'),
                      selected: endOfTrack,
                      onSelected: (_) {
                        playback.startSleepTimerEndOfTrack();
                        Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            if (endsAt != null || endOfTrack)
              TextButton(
                onPressed: () {
                  playback.cancelSleepTimer();
                  Navigator.of(context).pop();
                },
                child: const Text('Turn off'),
              ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
