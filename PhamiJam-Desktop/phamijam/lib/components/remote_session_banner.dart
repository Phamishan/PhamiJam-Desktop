import 'package:flutter/material.dart';
import 'package:phamijam/components/playback_model.dart';
import 'package:provider/provider.dart';

class RemoteSessionBanner extends StatelessWidget {
  const RemoteSessionBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final playback = context.watch<PlaybackModel>();
    if (!playback.shouldShowRemoteBanner) return const SizedBox.shrink();

    final session = playback.remoteSession;
    if (session == null) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final track = session.currentTrack;

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.headphones_rounded, color: colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Playing on ${session.deviceName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                Text(
                  (track?['songName'] as String?) ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: playback.resumeRemoteSessionLocally,
            child: const Text('Resume'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            onPressed: playback.enterRemoteControl,
            child: const Text('Control'),
          ),
          IconButton(
            onPressed: playback.dismissRemoteBanner,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colorScheme.onSurfaceVariant,
            ),
            splashRadius: 16,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}
