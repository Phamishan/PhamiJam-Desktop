import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/services/listening_history_service.dart';
import 'package:phamijam/services/wrapped_stats.dart';
import 'package:phamijam/widgets/profile_grid/tiles/private_tile_placeholder.dart';
import 'package:provider/provider.dart';

class JamstatsHighlightsTile extends StatelessWidget {
  const JamstatsHighlightsTile({super.key, required this.profileUid});

  final String profileUid;

  @override
  Widget build(BuildContext context) {
    final isOwner = profileUid == FirebaseAuth.instance.currentUser?.uid;
    final isFriend = context.watch<FriendsProvider>().isFriend(profileUid);
    if (!isOwner && !isFriend) return const PrivateTilePlaceholder();

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
        if (stats == null || stats.isEmpty) {
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
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                '${stats.totalMinutes} min',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                'listened this year',
                style: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              if (stats.topArtists.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Top artist: ${stats.topArtists.first.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}
