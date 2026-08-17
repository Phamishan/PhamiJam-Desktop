import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/widgets/scrim_icon_button.dart';

class RecentTrackCard extends StatefulWidget {
  final PlayEvent event;
  final bool isActive;
  final double width;
  final VoidCallback onTap;
  final bool isLiked;
  final VoidCallback? onToggleLike;
  final bool isDownloaded;
  final VoidCallback? onToggleDownload;
  final List<({String value, IconData icon, String label})> menuEntries;
  final ValueChanged<String>? onMenuSelected;

  const RecentTrackCard({
    super.key,
    required this.event,
    required this.onTap,
    this.isActive = false,
    this.isLiked = false,
    this.onToggleLike,
    this.isDownloaded = false,
    this.onToggleDownload,
    this.menuEntries = const [],
    this.onMenuSelected,
    this.width = 140,
  });

  @override
  State<RecentTrackCard> createState() => _RecentTrackCardState();
}

class _RecentTrackCardState extends State<RecentTrackCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeColor = widget.isActive
        ? colorScheme.primary
        : colorScheme.onSurface;

    final card = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: widget.width,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? colorScheme.primary.withValues(alpha: _hovering ? 0.16 : 0.12)
                : _hovering
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
                      child: widget.event.thumbnailUrl.isNotEmpty
                          ? Image.network(
                              widget.event.thumbnailUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                color: colorScheme.surfaceContainerHigh,
                                child: Icon(
                                  Icons.music_note_rounded,
                                  color: colorScheme.onSurface,
                                  size: 32,
                                ),
                              ),
                            )
                          : Container(
                              color: colorScheme.surfaceContainerHigh,
                              child: Icon(
                                Icons.music_note_rounded,
                                color: colorScheme.onSurface,
                                size: 32,
                              ),
                            ),
                    ),
                  ),
                  if (widget.onToggleLike != null)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: ScrimIconButton(
                        icon: widget.isLiked
                            ? Icons.favorite_rounded
                            : Icons.favorite_border_rounded,
                        onTap: widget.onToggleLike!,
                      ),
                    ),
                  if (widget.menuEntries.isNotEmpty)
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
                          onSelected: widget.onMenuSelected,
                          itemBuilder: (context) => [
                            for (final entry in widget.menuEntries)
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
                  if (widget.onToggleDownload != null)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: ScrimIconButton(
                        icon: widget.isDownloaded
                            ? Icons.download_done_rounded
                            : Icons.download_rounded,
                        onTap: widget.onToggleDownload!,
                      ),
                    ),
                  AnimatedOpacity(
                    opacity: _hovering || widget.isActive ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: colorScheme.primary,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.45),
                              blurRadius: 8,
                            ),
                          ],
                        ),
                        child: Icon(
                          widget.isActive
                              ? Icons.graphic_eq_rounded
                              : Icons.play_arrow_rounded,
                          color: colorScheme.onPrimary,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                widget.event.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: activeColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                widget.event.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );

    if (widget.menuEntries.isEmpty) return card;

    return ContextMenuRegion<String>(
      contextMenu: ContextMenu(
        borderRadius: BorderRadius.circular(12),
        entries: [
          for (final entry in widget.menuEntries)
            MenuItem<String>(
              value: entry.value,
              icon: Icon(entry.icon),
              label: Text(entry.label),
            ),
        ],
      ),
      onItemSelected: (value) {
        if (value != null) widget.onMenuSelected?.call(value);
      },
      child: card,
    );
  }
}
