import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:provider/provider.dart';

class ListenAlongBanner extends StatelessWidget {
  const ListenAlongBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackModel>();
    if (!playback.isListeningAlong) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final friendName = playback.listenAlongFriendName ?? 'a friend';

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_alt_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Listening along with $friendName',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colorScheme.onPrimaryContainer,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: colorScheme.onPrimaryContainer,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: playback.stopListenAlong,
            child: const Text('Stop'),
          ),
        ],
      ),
    );
  }
}
