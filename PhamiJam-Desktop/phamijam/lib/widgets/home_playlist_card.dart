import 'package:flutter/material.dart';

class HomePlaylistCard extends StatefulWidget {
  final Map<String, dynamic> playlist;
  final double width;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  const HomePlaylistCard({
    super.key,
    required this.playlist,
    required this.onTap,
    this.onPlay,
    this.width = 148,
  });

  @override
  State<HomePlaylistCard> createState() => _HomePlaylistCardState();
}

class _HomePlaylistCardState extends State<HomePlaylistCard> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = (widget.playlist['title'] as String?) ?? 'Untitled playlist';
    final itemCount = (widget.playlist['itemCount'] as int?) ?? 0;
    final thumbnailUrl = (widget.playlist['thumbnailUrl'] as String?) ?? '';

    return MouseRegion(
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
  }
}
