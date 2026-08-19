import 'package:flutter/material.dart' hide GridTile;
import 'package:phamijam/models/grid_tile.dart';
import 'package:phamijam/providers/profile_grid_provider.dart';
import 'package:phamijam/widgets/profile_grid/profile_grid_view.dart';
import 'package:phamijam/widgets/profile_grid/tiles/bio_header_tile.dart';
import 'package:phamijam/widgets/profile_grid/tiles/featured_playlists_tile.dart';
import 'package:phamijam/widgets/profile_grid/tiles/jamstats_highlights_tile.dart';
import 'package:phamijam/widgets/profile_grid/tiles/recently_played_tile.dart';

class GridTileWidget extends StatelessWidget {
  const GridTileWidget({
    super.key,
    required this.tile,
    required this.profileUid,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.editable,
    required this.gridProvider,
    this.onTap,
  });

  final GridTile tile;
  final String profileUid;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final bool editable;
  final ProfileGridProvider? gridProvider;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final provider = gridProvider;
    final isDragging = editable && provider?.draggingTileId == tile.id;
    final isResizing = editable && provider?.resizingTileId == tile.id;

    final col = isDragging ? provider!.previewCol ?? tile.col : tile.col;
    final row = isDragging ? provider!.previewRow ?? tile.row : tile.row;
    final (colSpan, rowSpan) = isResizing
        ? provider!.previewSize ?? (tile.colSpan, tile.rowSpan)
        : (tile.colSpan, tile.rowSpan);

    final left = gridLeft(col, cellWidth, gap);
    final top = gridTop(row, cellHeight, gap);
    final width = gridWidth(colSpan, cellWidth, gap);
    final height = gridHeight(rowSpan, cellHeight, gap);

    return AnimatedPositioned(
      duration: (isDragging || isResizing)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      left: left,
      top: top,
      width: width,
      height: height,
      child: _TileSurface(
        tile: tile,
        profileUid: profileUid,
        editable: editable,
        isDragging: isDragging,
        onTap: editable ? null : onTap,
        onDragPanStart: editable ? (_) => provider!.beginDrag(tile.id) : null,
        onDragPanUpdate: editable
            ? (details) => provider!.updateDragPreview(
                details.delta,
                cellWidth,
                cellHeight,
              )
            : null,
        onDragPanEnd: editable ? (_) => provider!.endDrag() : null,
        onResizePanStart: editable && tile.widgetType.sizeVariants.length > 1
            ? (_) => provider!.beginResize(tile.id)
            : null,
        onResizePanUpdate: editable && tile.widgetType.sizeVariants.length > 1
            ? (details) => provider!.updateResizePreview(
                details.delta,
                cellWidth,
                cellHeight,
              )
            : null,
        onResizePanEnd: editable && tile.widgetType.sizeVariants.length > 1
            ? (_) => provider!.endResize()
            : null,
        onRemove: editable ? () => provider!.removeTile(tile.id) : null,
      ),
    );
  }
}

class _TileSurface extends StatelessWidget {
  const _TileSurface({
    required this.tile,
    required this.profileUid,
    required this.editable,
    required this.isDragging,
    this.onTap,
    this.onDragPanStart,
    this.onDragPanUpdate,
    this.onDragPanEnd,
    this.onResizePanStart,
    this.onResizePanUpdate,
    this.onResizePanEnd,
    this.onRemove,
  });

  final GridTile tile;
  final String profileUid;
  final bool editable;
  final bool isDragging;
  final VoidCallback? onTap;
  final GestureDragStartCallback? onDragPanStart;
  final GestureDragUpdateCallback? onDragPanUpdate;
  final GestureDragEndCallback? onDragPanEnd;
  final GestureDragStartCallback? onResizePanStart;
  final GestureDragUpdateCallback? onResizePanUpdate;
  final GestureDragEndCallback? onResizePanEnd;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Widget content = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          border: isDragging
              ? Border.all(color: colorScheme.primary, width: 2)
              : null,
        ),
        child: _buildTileContent(tile, profileUid),
      ),
    );

    if (onTap != null) {
      content = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: content,
        ),
      );
    }

    if (!editable) return content;

    return GestureDetector(
      onPanStart: onDragPanStart,
      onPanUpdate: onDragPanUpdate,
      onPanEnd: onDragPanEnd,
      child: Opacity(
        opacity: isDragging ? 0.85 : 1,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              left: 6,
              top: 6,
              child: _HandleIcon(icon: Icons.drag_indicator_rounded),
            ),
            if (onRemove != null)
              Positioned(
                right: 6,
                top: 6,
                child: GestureDetector(
                  onTap: onRemove,
                  child: const _HandleIcon(icon: Icons.close_rounded),
                ),
              ),
            if (onResizePanStart != null)
              Positioned(
                right: 6,
                bottom: 6,
                child: GestureDetector(
                  onPanStart: onResizePanStart,
                  onPanUpdate: onResizePanUpdate,
                  onPanEnd: onResizePanEnd,
                  child: const _HandleIcon(
                    icon: Icons.open_in_full_rounded,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _HandleIcon extends StatelessWidget {
  const _HandleIcon({required this.icon, this.size = 16});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

Widget _buildTileContent(GridTile tile, String profileUid) {
  return switch (tile.widgetType) {
    GridWidgetType.bioHeader => BioHeaderTile(profileUid: profileUid),
    GridWidgetType.featuredPlaylists => FeaturedPlaylistsTile(
      profileUid: profileUid,
    ),
    GridWidgetType.jamstatsHighlights => JamstatsHighlightsTile(
      profileUid: profileUid,
    ),
    GridWidgetType.recentlyPlayed => RecentlyPlayedTile(profileUid: profileUid),
  };
}
