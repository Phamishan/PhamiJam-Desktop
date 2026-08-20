import 'package:flutter/material.dart';
import 'package:phamijam/services/profile_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

class FeaturedPlaylistsTile extends StatelessWidget {
  const FeaturedPlaylistsTile({
    super.key,
    required this.profileUid,
    this.onOpenPlaylist,
  });

  final String profileUid;
  final void Function(String playlistId, String title, String? thumbnailUrl)?
  onOpenPlaylist;

  static Future<List<Map<String, dynamic>>> _fetchPublicFeatured(
    String uid,
  ) async {
    final ids = await ProfileService.fetchProfilePlaylistIds(uid);
    final playlists = await Future.wait(
      ids.map((id) async {
        try {
          return await YoutubePlaylistService.fetchPlaylistMetadata(id);
        } catch (_) {
          return null;
        }
      }),
    );
    return playlists
        .whereType<Map<String, dynamic>>()
        .where((p) => p['privacyStatus'] != 'private')
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchPublicFeatured(profileUid),
      builder: (context, snapshot) {
        final playlists = snapshot.data ?? const [];
        final colorScheme = Theme.of(context).colorScheme;

        if (snapshot.connectionState == ConnectionState.done &&
            playlists.isEmpty) {
          return Center(
            child: Text(
              'No public playlists yet',
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
                'Playlists',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: ListView.separated(
                  itemCount: playlists.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (context, index) {
                    final playlist = playlists[index];
                    final playlistId = playlist['playlistId'] as String? ?? '';
                    final title = playlist['title'] as String? ?? 'Playlist';
                    final thumbnailUrl =
                        playlist['thumbnailUrl'] as String? ?? '';
                    final onTap = onOpenPlaylist == null || playlistId.isEmpty
                        ? null
                        : () =>
                              onOpenPlaylist!(playlistId, title, thumbnailUrl);
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: onTap,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: SizedBox(
                                  width: 40,
                                  height: 40,
                                  child: thumbnailUrl.isEmpty
                                      ? ColoredBox(
                                          color: colorScheme
                                              .surfaceContainerHighest,
                                        )
                                      : Image.network(
                                          thumbnailUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => ColoredBox(
                                            color: colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: colorScheme.onSurface,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
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
