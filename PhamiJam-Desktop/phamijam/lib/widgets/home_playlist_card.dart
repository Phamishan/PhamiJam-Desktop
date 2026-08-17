import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:phamijam/components/delete_playlist_dialog.dart';
import 'package:phamijam/components/edit_playlist_dialog.dart';
import 'package:phamijam/services/share_link_service.dart';

class HomePlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final bool isPinned;
  final VoidCallback? onTogglePin;
  final void Function(String title, String description, String privacyStatus)?
  onEdited;
  final VoidCallback? onDeleted;

  const HomePlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onPlay,
    this.isPinned = false,
    this.onTogglePin,
    this.onEdited,
    this.onDeleted,
    this.width = 148,
  });

  @override
  State<HomePlaylistCard> createState() => _HomePlaylistCardState();
}

class _HomePlaylistCardState extends State<HomePlaylistCard> {
  bool _hovering = false;

  String? get _playlistId => widget.playlist['playlistId'] as String?;

  bool get _canShare =>
      (_playlistId ?? '').isNotEmpty &&
      (widget.playlist['privacyStatus'] as String?) != 'private';

  List<({String value, IconData icon, String label})> _menuEntries() {
    return [
      if (widget.onTogglePin != null)
        (
          value: 'toggle_pin',
          icon: widget.isPinned
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          label: widget.isPinned ? 'Unpin playlist' : 'Pin playlist',
        ),
      if (_canShare)
        (value: 'share', icon: Icons.share_rounded, label: 'Share playlist'),
      if (widget.onEdited != null && (_playlistId ?? '').isNotEmpty)
        (value: 'edit', icon: Icons.edit_rounded, label: 'Edit playlist'),
      if (widget.onDeleted != null && (_playlistId ?? '').isNotEmpty)
        (value: 'delete', icon: Icons.delete_rounded, label: 'Delete playlist'),
    ];
  }

  void _handleMenuSelection(String? value) {
    final playlistId = _playlistId;
    if (value == 'toggle_pin') {
      widget.onTogglePin?.call();
    } else if (value == 'share') {
      if (playlistId != null) {
        ShareLinkService.sharePlaylist(context, playlistId);
      }
    } else if (value == 'edit') {
      if (playlistId == null) return;
      showEditPlaylistDialog(
        context,
        playlistId: playlistId,
        initialTitle: (widget.playlist['title'] as String?) ?? '',
        initialDescription: (widget.playlist['description'] as String?) ?? '',
        initialPrivacyStatus:
            (widget.playlist['privacyStatus'] as String?) ?? 'public',
        onUpdated: (title, description, privacyStatus) {
          widget.onEdited?.call(title, description, privacyStatus);
        },
      );
    } else if (value == 'delete') {
      if (playlistId == null) return;
      confirmDeletePlaylist(
        context,
        playlistId: playlistId,
        playlistTitle: (widget.playlist['title'] as String?) ?? 'Untitled playlist',
        onDeleted: () => widget.onDeleted?.call(),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final menuEntries = _menuEntries();
    final colorScheme = Theme.of(context).colorScheme;
    final title = (widget.playlist['title'] as String?) ?? 'Untitled playlist';
    final itemCount = (widget.playlist['itemCount'] as int?) ?? 0;
    final thumbnailUrl = (widget.playlist['thumbnailUrl'] as String?) ?? '';

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: _hovering
                ? colorScheme.surfaceContainerHighest
                : colorScheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                alignment: Alignment.bottomRight,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: AspectRatio(
                      aspectRatio: 1,
                      child: thumbnailUrl.isNotEmpty
                          ? Image.network(
                              thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: colorScheme.surfaceContainerHigh,
                                child: Icon(
                                  Icons.queue_music_rounded,
                                  color: colorScheme.onSurface,
                                  size: 36,
                                ),
                              ),
                            )
                          : Container(
                              color: colorScheme.surfaceContainerHigh,
                              child: Icon(
                                Icons.queue_music_rounded,
                                color: colorScheme.onSurface,
                                size: 36,
                              ),
                            ),
                    ),
                  ),
                  if (widget.isPinned)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.45),
                              blurRadius: 6,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.push_pin_rounded,
                          color: colorScheme.onPrimary,
                          size: 14,
                        ),
                      ),
                    ),
                  if (menuEntries.isNotEmpty)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        child: PopupMenuButton<String>(
                          splashRadius: 16,
                          borderRadius: BorderRadius.circular(16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          onSelected: _handleMenuSelection,
                          itemBuilder: (context) => [
                            for (final entry in menuEntries)
                              PopupMenuItem(
                                value: entry.value,
                                child: ListTile(
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(entry.icon),
                                  title: Text(entry.label),
                                ),
                              ),
                          ],
                          child: const Padding(
                            padding: EdgeInsets.all(7),
                            child: Icon(
                              Icons.more_vert_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (widget.onPlay != null)
                    AnimatedOpacity(
                      opacity: _hovering ? 1 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: IgnorePointer(
                        ignoring: !_hovering,
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: GestureDetector(
                            onTap: widget.onPlay,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.shadow.withValues(
                                      alpha: 0.45,
                                    ),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: colorScheme.onPrimary,
                                size: 24,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$itemCount videos',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );

    if (menuEntries.isEmpty) return card;

    return ContextMenuRegion<String>(
      contextMenu: ContextMenu(
        borderRadius: BorderRadius.circular(12),
        entries: [
          for (final entry in menuEntries)
            MenuItem<String>(
              value: entry.value,
              icon: Icon(entry.icon),
              label: Text(entry.label),
            ),
        ],
      ),
      onItemSelected: _handleMenuSelection,
      child: card,
    );
  }
}
