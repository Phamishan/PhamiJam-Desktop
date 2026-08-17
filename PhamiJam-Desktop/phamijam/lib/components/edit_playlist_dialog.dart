import 'package:flutter/material.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

Future<void> showEditPlaylistDialog(
  BuildContext context, {
  required String playlistId,
  required String initialTitle,
  required String initialDescription,
  required String initialPrivacyStatus,
  required void Function(String title, String description, String privacyStatus)
  onUpdated,
}) {
  final formKey = GlobalKey<FormState>();
  String title = initialTitle;
  String description = initialDescription;
  String privacyStatus = initialPrivacyStatus;
  bool isSaving = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          final colorScheme = Theme.of(innerContext).colorScheme;
          return AlertDialog(
            title: const Text('Edit Playlist'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextFormField(
                      initialValue: initialTitle,
                      decoration: const InputDecoration(labelText: 'Title'),
                      onChanged: (value) => title = value,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Enter a title'
                          : null,
                    ),
                    TextFormField(
                      initialValue: initialDescription,
                      decoration: const InputDecoration(
                        labelText: 'Description',
                      ),
                      onChanged: (value) => description = value,
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Visibility',
                        style: Theme.of(innerContext).textTheme.labelLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'private',
                          label: Text('Private'),
                          icon: Icon(Icons.lock_rounded),
                        ),
                        ButtonSegment(
                          value: 'unlisted',
                          label: Text('Unlisted'),
                          icon: Icon(Icons.link_rounded),
                        ),
                        ButtonSegment(
                          value: 'public',
                          label: Text('Public'),
                          icon: Icon(Icons.public_rounded),
                        ),
                      ],
                      selected: {privacyStatus},
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) =>
                          setState(() => privacyStatus = selection.first),
                      style: SegmentedButton.styleFrom(
                        backgroundColor: colorScheme.surfaceContainerHigh,
                        foregroundColor: colorScheme.onSurfaceVariant,
                        selectedBackgroundColor: colorScheme.primary,
                        selectedForegroundColor: colorScheme.onPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) {
                          return;
                        }

                        setState(() => isSaving = true);

                        try {
                          await YoutubePlaylistService.updatePlaylist(
                            playlistId: playlistId,
                            title: title.trim(),
                            description: description.trim(),
                            privacyStatus:
                                privacyStatus == initialPrivacyStatus
                                ? null
                                : privacyStatus,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();

                          onUpdated(title.trim(), description.trim(), privacyStatus);

                          if (context.mounted) {
                            AppFlushbar.success(
                              context,
                              'Playlist updated successfully.',
                            );
                          }
                        } catch (e) {
                          if (!context.mounted) return;
                          AppFlushbar.error(context, '$e');
                          setState(() => isSaving = false);
                        }
                      },
                child: isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
