import 'package:flutter/material.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';

class TopTracksTile extends StatelessWidget {
  const TopTracksTile({super.key, required this.profileUid});

  final String profileUid;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return FutureBuilder<List<PlayEvent>>(
      future: ListeningHistoryService.eventsSinceForUid(
        profileUid,
        DateTime(now.year),
      ),
      builder: (context, snapshot) {
        final events = snapshot.data;
        final stats = events == null ? null : WrappedStats.fromEvents(events);
        final tracks = stats?.topTracks ?? const [];
        if (snapshot.connectionState == ConnectionState.done &&
            tracks.isEmpty) {
          return Center(
            child: Text(
              'No listening activity yet',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Top tracks',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: tracks.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: track.thumbnailUrl.isEmpty
                                ? ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                  )
                                : Image.network(
                                    track.thumbnailUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => ColoredBox(
                                      color:
                                          colorScheme.surfaceContainerHighest,
                                    ),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            track.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
