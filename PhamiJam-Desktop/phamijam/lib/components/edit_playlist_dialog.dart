import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/services/playlist_cover_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

Future<void> showEditPlaylistDialog(
  BuildContext context, {
  required String playlistId,
  required String initialTitle,
  required String initialDescription,
  required String initialPrivacyStatus,
  String initialThumbnailUrl = '',
  String? originalThumbnailUrl,
  String? initialCustomCoverUrl,
  required void Function(String title, String description, String privacyStatus)
  onUpdated,
  void Function(String? customCoverUrl)? onCoverChanged,
}) {
  final formKey = GlobalKey<FormState>();
  String title = initialTitle;
  String description = initialDescription;
  String privacyStatus = initialPrivacyStatus;
  String thumbnailUrl = initialThumbnailUrl;
  String? customCoverUrl = initialCustomCoverUrl;
  bool isSaving = false;
  bool isUploadingCover = false;

  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (innerContext, setState) {
          final colorScheme = Theme.of(innerContext).colorScheme;

          Future<void> pickCover() async {
            final picked = await ImagePicker().pickImage(
              source: ImageSource.gallery,
              maxWidth: 1024,
              maxHeight: 1024,
              imageQuality: 85,
            );
            if (picked == null) return;
            setState(() => isUploadingCover = true);
            try {
              final url = await PlaylistCoverService.upload(
                playlistId,
                File(picked.path),
              );
              setState(() {
                thumbnailUrl = url;
                customCoverUrl = url;
                isUploadingCover = false;
              });
              onCoverChanged?.call(url);
            } catch (error) {
              setState(() => isUploadingCover = false);
              if (innerContext.mounted) {
                AppFlushbar.error(
                  innerContext,
                  "Couldn't update cover image: $error",
                );
              }
            }
          }

          Future<void> removeCover() async {
            setState(() => isUploadingCover = true);
            try {
              await PlaylistCoverService.remove(playlistId);
              setState(() {
                thumbnailUrl = originalThumbnailUrl ?? initialThumbnailUrl;
                customCoverUrl = null;
                isUploadingCover = false;
              });
              onCoverChanged?.call(null);
            } catch (error) {
              setState(() => isUploadingCover = false);
              if (innerContext.mounted) {
                AppFlushbar.error(
                  innerContext,
                  "Couldn't remove cover image: $error",
                );
              }
            }
          }

          return AlertDialog(
            title: const Text('Edit Playlist'),
            content: SingleChildScrollView(
              child: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: GestureDetector(
                        onTap: isUploadingCover ? null : pickCover,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 96,
                                height: 96,
                                child: thumbnailUrl.isEmpty
                                    ? Container(
                                        color: colorScheme.surfaceContainerHigh,
                                      )
                                    : Image.network(
                                        thumbnailUrl,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, _, _) => Container(
                                          color:
                                              colorScheme.surfaceContainerHigh,
                                        ),
                                      ),
                              ),
                            ),
                            Container(
                              width: 96,
                              height: 96,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                color: Colors.black.withValues(alpha: 0.35),
                              ),
                              alignment: Alignment.center,
                              child: isUploadingCover
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (customCoverUrl != null && customCoverUrl!.isNotEmpty)
                      TextButton(
                        onPressed: isUploadingCover ? null : removeCover,
                        child: const Text('Remove custom cover'),
                      ),
                    const SizedBox(height: 8),
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
                            privacyStatus: privacyStatus == initialPrivacyStatus
                                ? null
                                : privacyStatus,
                          );
                          if (!dialogContext.mounted) return;
                          Navigator.of(dialogContext).pop();

                          onUpdated(
                            title.trim(),
                            description.trim(),
                            privacyStatus,
                          );

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
