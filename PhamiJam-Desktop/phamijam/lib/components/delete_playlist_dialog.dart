import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

Future<void> confirmDeletePlaylist(
  BuildContext context, {
  required String playlistId,
  required String playlistTitle,
  required VoidCallback onDeleted,
}) async {
  final colorScheme = Theme.of(context).colorScheme;
  final shouldDelete = await showDialog<bool>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        title: const Text('Delete Playlist'),
        content: Text(
          'Delete "$playlistTitle"? This WILL delete the playlist on YouTube as well and cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
            ),
            child: const Text('Delete'),
          ),
        ],
      );
    },
  );

  if (shouldDelete != true || !context.mounted) return;

  try {
    await YoutubePlaylistService.deletePlaylist(playlistId);
    onDeleted();
    if (context.mounted) {
      AppFlushbar.success(context, 'Playlist deleted successfully.');
    }
  } catch (e) {
    if (context.mounted) {
      AppFlushbar.error(context, '$e');
    }
  }
}
