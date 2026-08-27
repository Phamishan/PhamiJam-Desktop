import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:phamijam/providers/friends_provider.dart';
import 'package:phamijam/services/liked_songs_service.dart';
import 'package:phamijam/widgets/profile_grid/tiles/private_tile_placeholder.dart';
import 'package:provider/provider.dart';

class LikedSongsTile extends StatelessWidget {
  const LikedSongsTile({super.key, required this.profileUid});

  final String profileUid;

  @override
  Widget build(BuildContext context) {
    final isOwner = profileUid == FirebaseAuth.instance.currentUser?.uid;
    final isFriend = context.watch<FriendsProvider>().isFriend(profileUid);
    if (!isOwner && !isFriend) return const PrivateTilePlaceholder();

    final colorScheme = Theme.of(context).colorScheme;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: LikedSongsService.fetchAllForUid(profileUid),
      builder: (context, snapshot) {
        final songs = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.done && songs.isEmpty) {
          return Center(
            child: Text(
              'No liked songs yet',
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
                'Liked songs',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: songs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    final thumbnailUrl =
                        (song['thumbnailUrl'] as String?) ?? '';
                    final title = (song['title'] as String?) ?? '';
                    return Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: SizedBox(
                            width: 28,
                            height: 28,
                            child: thumbnailUrl.isEmpty
                                ? ColoredBox(
                                    color: colorScheme.surfaceContainerHighest,
                                  )
                                : Image.network(
                                    thumbnailUrl,
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
                            title,
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
