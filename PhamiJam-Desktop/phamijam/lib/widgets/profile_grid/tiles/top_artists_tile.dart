import 'package:flutter/material.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';

class TopArtistsTile extends StatelessWidget {
  const TopArtistsTile({super.key, required this.profileUid});

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
        final artists = stats?.topArtists ?? const [];
        if (snapshot.connectionState == ConnectionState.done &&
            artists.isEmpty) {
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
                'Top artists',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: artists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final artist = artists[index];
                    return Row(
                      children: [
                        SizedBox(
                          width: 16,
                          child: Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            artist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Text(
                          '${artist.plays}',
                          style: TextStyle(
                            color: colorScheme.onSurfaceVariant,
                            fontSize: 11,
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
