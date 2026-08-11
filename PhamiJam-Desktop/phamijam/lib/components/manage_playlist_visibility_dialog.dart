import 'package:flutter/material.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:provider/provider.dart';

void showManagePlaylistVisibilityDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (dialogContext) => const _ManagePlaylistVisibilityDialog(),
  );
}

class _ManagePlaylistVisibilityDialog extends StatefulWidget {
  const _ManagePlaylistVisibilityDialog();

  @override
  State<_ManagePlaylistVisibilityDialog> createState() =>
      _ManagePlaylistVisibilityDialogState();
}

class _ManagePlaylistVisibilityDialogState
    extends State<_ManagePlaylistVisibilityDialog> {
  late Future<List<Map<String, dynamic>>> _loadFuture;

  @override
  void initState() {
    super.initState();
    _loadFuture = YoutubePlaylistService.fetchMyPlaylists();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Playlist Visibility'),
      content: SizedBox(
        width: 420,
        height: 420,
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _loadFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Text(
                  "Couldn't load your playlists.",
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            final playlists = snapshot.data ?? const [];
            if (playlists.isEmpty) {
              return Center(
                child: Text(
                  "You don't have any playlists yet.",
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Uncheck a playlist to hide it from Home and Playlists.',
                  style: TextStyle(color: colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Consumer<SettingsProvider>(
                    builder: (context, settings, _) {
                      return ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final playlist = playlists[index];
                          final playlistId =
                              (playlist['playlistId'] as String?) ?? '';
                          final title =
                              (playlist['title'] as String?) ??
                              'Untitled playlist';
                          return CheckboxListTile(
                            title: Text(title),
                            value: !settings.isPlaylistHidden(playlistId),
                            onChanged: playlistId.isEmpty
                                ? null
                                : (checked) => settings.setPlaylistHidden(
                                    playlistId,
                                    !(checked ?? true),
                                  ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
