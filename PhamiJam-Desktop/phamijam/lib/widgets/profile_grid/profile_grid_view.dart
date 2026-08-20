import 'dart:math';

import 'package:flutter/material.dart' hide GridTile;
import 'package:phamijam/models/grid_tile.dart';
import 'package:phamijam/providers/profile_grid_provider.dart';
import 'package:phamijam/widgets/profile_grid/grid_tile_widget.dart';

double gridLeft(int col, double cellWidth, double gap) =>
    col * (cellWidth + gap);
double gridTop(int row, double cellHeight, double gap) =>
    row * (cellHeight + gap);
double gridWidth(int colSpan, double cellWidth, double gap) =>
    colSpan * cellWidth + (colSpan - 1) * gap;
double gridHeight(int rowSpan, double cellHeight, double gap) =>
    rowSpan * cellHeight + (rowSpan - 1) * gap;

class ProfileGridView extends StatelessWidget {
  const ProfileGridView({
    super.key,
    required this.profileUid,
    this.tiles,
    this.gridProvider,
    this.editable = false,
    this.onTileTap,
    this.onOpenPlaylist,
  }) : assert(
         editable ? gridProvider != null : tiles != null,
         'editable requires a gridProvider; read-only requires tiles',
       );

  final String profileUid;
  final List<GridTile>? tiles;
  final ProfileGridProvider? gridProvider;
  final bool editable;
  final void Function(GridTile tile)? onTileTap;
  final void Function(String playlistId, String title, String? thumbnailUrl)?
  onOpenPlaylist;

  @override
  Widget build(BuildContext context) {
    final provider = gridProvider;
    if (editable && provider != null) {
      return ListenableBuilder(
        listenable: provider,
        builder: (context, _) => _GridCanvas(
          tiles: provider.displayTiles,
          profileUid: profileUid,
          editable: true,
          gridProvider: provider,
          onTileTap: onTileTap,
          onOpenPlaylist: onOpenPlaylist,
        ),
      );
    }
    return _GridCanvas(
      tiles: tiles ?? const [],
      profileUid: profileUid,
      editable: false,
      gridProvider: null,
      onTileTap: onTileTap,
      onOpenPlaylist: onOpenPlaylist,
    );
  }
}

class _GridCanvas extends StatelessWidget {
  const _GridCanvas({
    required this.tiles,
    required this.profileUid,
    required this.editable,
    required this.gridProvider,
    required this.onTileTap,
    this.onOpenPlaylist,
  });

  final List<GridTile> tiles;
  final String profileUid;
  final bool editable;
  final ProfileGridProvider? gridProvider;
  final void Function(GridTile tile)? onTileTap;
  final void Function(String playlistId, String title, String? thumbnailUrl)?
  onOpenPlaylist;

  static const double _maxGridWidth = 720;
  static const double _gap = 10;

  @override
  Widget build(BuildContext context) {
    if (tiles.isEmpty && !editable) {
      return const SizedBox.shrink();
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxGridWidth),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cellWidth =
                (constraints.maxWidth -
                    _gap * (ProfileGridProvider.columns - 1)) /
                ProfileGridProvider.columns;
            final cellHeight = cellWidth;
            final contentRows = tiles.isEmpty
                ? 0
                : tiles.map((t) => t.row + t.rowSpan).reduce(max);
            final totalRows = editable ? contentRows + 1 : contentRows;
            final height = totalRows <= 0
                ? cellHeight
                : gridTop(totalRows, cellHeight, _gap);

            return SizedBox(
              width: constraints.maxWidth,
              height: height,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (editable)
                    _GridLines(
                      tiles: tiles,
                      columns: ProfileGridProvider.columns,
                      rows: totalRows,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      gap: _gap,
                      addSlotRow: gridProvider != null ? contentRows : null,
                    ),
                  if (editable && gridProvider != null)
                    _SnapTargetHighlight(
                      tiles: tiles,
                      gridProvider: gridProvider!,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      gap: _gap,
                    ),
                  for (final tile in tiles)
                    GridTileWidget(
                      key: ValueKey(tile.id),
                      tile: tile,
                      profileUid: profileUid,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      gap: _gap,
                      editable: editable,
                      gridProvider: gridProvider,
                      onTap: onTileTap == null ? null : () => onTileTap!(tile),
                      onOpenPlaylist: onOpenPlaylist,
                    ),
                  if (editable && gridProvider != null)
                    _AddTileSlot(
                      row: contentRows,
                      cellWidth: cellWidth,
                      cellHeight: cellHeight,
                      gap: _gap,
                      gridProvider: gridProvider!,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GridLines extends StatelessWidget {
  const _GridLines({
    required this.tiles,
    required this.columns,
    required this.rows,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    this.addSlotRow,
  });

  final List<GridTile> tiles;
  final int columns;
  final int rows;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final int? addSlotRow;

  bool _isOccupied(int col, int row) {
    if (row == addSlotRow && col < 2) return true;
    for (final tile in tiles) {
      if (col >= tile.col &&
          col < tile.col + tile.colSpan &&
          row >= tile.row &&
          row < tile.row + tile.rowSpan) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (rows <= 0) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      children: [
        for (var row = 0; row < rows; row++)
          for (var col = 0; col < columns; col++)
            if (!_isOccupied(col, row))
              Positioned(
                left: gridLeft(col, cellWidth, gap),
                top: gridTop(row, cellHeight, gap),
                width: cellWidth,
                height: cellHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                    ),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
      ],
    );
  }
}

class _SnapTargetHighlight extends StatelessWidget {
  const _SnapTargetHighlight({
    required this.tiles,
    required this.gridProvider,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
  });

  final List<GridTile> tiles;
  final ProfileGridProvider gridProvider;
  final double cellWidth;
  final double cellHeight;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final int col;
    final int row;
    final int colSpan;
    final int rowSpan;

    final draggingId = gridProvider.draggingTileId;
    final resizingId = gridProvider.resizingTileId;
    final previewCol = gridProvider.previewCol;
    final previewRow = gridProvider.previewRow;
    final previewSize = gridProvider.previewSize;

    if (draggingId != null && previewCol != null && previewRow != null) {
      final index = tiles.indexWhere((t) => t.id == draggingId);
      if (index == -1) return const SizedBox.shrink();
      col = previewCol;
      row = previewRow;
      colSpan = tiles[index].colSpan;
      rowSpan = tiles[index].rowSpan;
    } else if (resizingId != null && previewSize != null) {
      final index = tiles.indexWhere((t) => t.id == resizingId);
      if (index == -1) return const SizedBox.shrink();
      col = tiles[index].col;
      row = tiles[index].row;
      (colSpan, rowSpan) = previewSize;
    } else {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      left: gridLeft(col, cellWidth, gap),
      top: gridTop(row, cellHeight, gap),
      width: gridWidth(colSpan, cellWidth, gap),
      height: gridHeight(rowSpan, cellHeight, gap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colorScheme.primary, width: 2),
        ),
      ),
    );
  }
}

class _AddTileSlot extends StatelessWidget {
  const _AddTileSlot({
    required this.row,
    required this.cellWidth,
    required this.cellHeight,
    required this.gap,
    required this.gridProvider,
  });

  final int row;
  final double cellWidth;
  final double cellHeight;
  final double gap;
  final ProfileGridProvider gridProvider;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Positioned(
      left: gridLeft(0, cellWidth, gap),
      top: gridTop(row, cellHeight, gap),
      width: gridWidth(2, cellWidth, gap),
      height: cellHeight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _showAddTileSheet(context, gridProvider),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: colorScheme.outlineVariant,
                style: BorderStyle.solid,
              ),
            ),
            child: Center(
              child: Icon(
                Icons.add_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

void _showAddTileSheet(BuildContext context, ProfileGridProvider gridProvider) {
  showModalBottomSheet(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add to your profile',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          for (final type in GridWidgetType.values)
            ListTile(
              leading: Icon(type.icon),
              title: Text(type.label),
              onTap: () {
                gridProvider.addTile(type);
                Navigator.of(sheetContext).pop();
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
