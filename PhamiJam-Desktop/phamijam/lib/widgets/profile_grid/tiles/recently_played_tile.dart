import 'package:flutter/material.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/services/listening_history_service.dart';

class RecentlyPlayedTile extends StatelessWidget {
  const RecentlyPlayedTile({super.key, required this.profileUid});

  final String profileUid;

  static Future<List<PlayEvent>> _fetchRecent(String uid) async {
    final since = DateTime.now().subtract(const Duration(days: 180));
    final events = await ListeningHistoryService.eventsSinceForUid(
      uid,
      since,
    );
    final seen = <String>{};
    final recent = <PlayEvent>[];
    for (final event in events.reversed) {
      if (!seen.add(event.videoId)) continue;
      recent.add(event);
      if (recent.length >= 5) break;
    }
    return recent;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<PlayEvent>>(
      future: _fetchRecent(profileUid),
      builder: (context, snapshot) {
        final tracks = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done &&
            tracks.isEmpty) {
          return Center(
            child: Text(
              'Nothing played yet',
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
                'Recently played',
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
                            track.title,
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
