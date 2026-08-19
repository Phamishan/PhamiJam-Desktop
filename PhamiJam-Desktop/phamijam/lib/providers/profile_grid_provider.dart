import 'dart:math';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';
import 'package:phamijam/models/grid_tile.dart';

class ProfileGridProvider extends ChangeNotifier {
  ProfileGridProvider(List<GridTile> initialTiles)
    : _original = List.unmodifiable(initialTiles),
      tiles = List.of(initialTiles);

  static const int columns = 4;

  final List<GridTile> _original;
  List<GridTile> tiles;

  String? draggingTileId;
  int? previewCol;
  int? previewRow;
  Offset _dragPixelOffset = Offset.zero;
  GridTile? _dragOrigin;

  String? resizingTileId;
  (int, int)? previewSize;
  Offset _resizePixelOffset = Offset.zero;
  GridTile? _resizeOrigin;

  bool get isDirty => !_sameTiles(tiles, _original);

  void revert() {
    tiles = List.of(_original);
    _clearDragState();
    _clearResizeState();
    notifyListeners();
  }

  void beginDrag(String tileId) {
    final tile = tiles.where((t) => t.id == tileId).firstOrNull;
    if (tile == null) return;
    draggingTileId = tileId;
    _dragOrigin = tile;
    _dragPixelOffset = Offset.zero;
    previewCol = tile.col;
    previewRow = tile.row;
    notifyListeners();
  }

  void updateDragPreview(Offset delta, double cellWidth, double cellHeight) {
    final origin = _dragOrigin;
    if (origin == null || cellWidth <= 0 || cellHeight <= 0) return;
    _dragPixelOffset += delta;
    final maxCol = max(0, columns - origin.colSpan);
    final newCol = (origin.col + (_dragPixelOffset.dx / cellWidth).round())
        .clamp(0, maxCol);
    final newRow = max(
      0,
      origin.row + (_dragPixelOffset.dy / cellHeight).round(),
    );
    if (newCol != previewCol || newRow != previewRow) {
      previewCol = newCol;
      previewRow = newRow;
      notifyListeners();
    }
  }

  void endDrag() {
    final id = draggingTileId;
    final col = previewCol;
    final row = previewRow;
    _clearDragState();
    if (id != null && col != null && row != null) {
      _moveTile(id, col, row);
    }
    notifyListeners();
  }

  void _clearDragState() {
    draggingTileId = null;
    previewCol = null;
    previewRow = null;
    _dragPixelOffset = Offset.zero;
    _dragOrigin = null;
  }

  void _moveTile(String id, int col, int row) {
    final index = tiles.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final moved = tiles[index].copyWith(col: col, row: row);
    final updated = [...tiles];
    updated[index] = moved;
    tiles = _resolveCollisions(updated, movedId: id);
  }

  void beginResize(String tileId) {
    final tile = tiles.where((t) => t.id == tileId).firstOrNull;
    if (tile == null) return;
    resizingTileId = tileId;
    _resizeOrigin = tile;
    _resizePixelOffset = Offset.zero;
    previewSize = (tile.colSpan, tile.rowSpan);
    notifyListeners();
  }

  void updateResizePreview(Offset delta, double cellWidth, double cellHeight) {
    final origin = _resizeOrigin;
    if (origin == null || cellWidth <= 0 || cellHeight <= 0) return;
    _resizePixelOffset += delta;
    final rawColSpan =
        origin.colSpan + (_resizePixelOffset.dx / cellWidth).round();
    final rawRowSpan =
        origin.rowSpan + (_resizePixelOffset.dy / cellHeight).round();
    final nearest = _nearestVariant(origin.widgetType, rawColSpan, rawRowSpan);
    if (nearest != previewSize) {
      previewSize = nearest;
      notifyListeners();
    }
  }

  void endResize() {
    final id = resizingTileId;
    final size = previewSize;
    final origin = _resizeOrigin;
    resizingTileId = null;
    previewSize = null;
    _resizePixelOffset = Offset.zero;
    _resizeOrigin = null;
    if (id != null &&
        size != null &&
        origin != null &&
        size != (origin.colSpan, origin.rowSpan)) {
      _resizeTile(id, size);
    }
    notifyListeners();
  }

  void _clearResizeState() {
    resizingTileId = null;
    previewSize = null;
    _resizePixelOffset = Offset.zero;
    _resizeOrigin = null;
  }

  void _resizeTile(String id, (int, int) size) {
    final index = tiles.indexWhere((t) => t.id == id);
    if (index == -1) return;
    final (colSpan, rowSpan) = size;
    final maxCol = max(0, columns - colSpan);
    final resized = tiles[index].copyWith(
      colSpan: colSpan,
      rowSpan: rowSpan,
      col: min(tiles[index].col, maxCol),
    );
    final updated = [...tiles];
    updated[index] = resized;
    tiles = _resolveCollisions(updated, movedId: id);
  }

  (int, int) _nearestVariant(
    GridWidgetType type,
    int rawColSpan,
    int rawRowSpan,
  ) {
    final variants = type.sizeVariants;
    var best = variants.first;
    var bestDistance = double.infinity;
    for (final variant in variants) {
      final dc = variant.$1 - rawColSpan;
      final dr = variant.$2 - rawRowSpan;
      final distance = dc * dc + dr * dr.toDouble();
      if (distance < bestDistance) {
        bestDistance = distance.toDouble();
        best = variant;
      }
    }
    return best;
  }

  void addTile(GridWidgetType type) {
    final (colSpan, rowSpan) = type.defaultSize;
    final row = tiles.isEmpty
        ? 0
        : tiles.map((t) => t.row + t.rowSpan).reduce(max);
    tiles = [
      ...tiles,
      GridTile(
        id: _generateId(),
        widgetType: type,
        col: 0,
        row: row,
        colSpan: colSpan,
        rowSpan: rowSpan,
      ),
    ];
    notifyListeners();
  }

  void removeTile(String id) {
    tiles = tiles.where((t) => t.id != id).toList();
    notifyListeners();
  }

  static String _generateId() {
    final random = Random();
    return '${DateTime.now().microsecondsSinceEpoch}-${random.nextInt(1 << 32)}';
  }

  static bool _sameTiles(List<GridTile> a, List<GridTile> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final ta = a[i];
      final tb = b[i];
      if (ta.id != tb.id ||
          ta.widgetType != tb.widgetType ||
          ta.col != tb.col ||
          ta.row != tb.row ||
          ta.colSpan != tb.colSpan ||
          ta.rowSpan != tb.rowSpan) {
        return false;
      }
    }
    return true;
  }
}

bool _overlaps(GridTile a, GridTile b) {
  final aRight = a.col + a.colSpan;
  final bRight = b.col + b.colSpan;
  final aBottom = a.row + a.rowSpan;
  final bBottom = b.row + b.rowSpan;
  return a.col < bRight && aRight > b.col && a.row < bBottom && aBottom > b.row;
}

List<GridTile> _resolveCollisions(
  List<GridTile> tiles, {
  required String movedId,
}) {
  final movedIndex = tiles.indexWhere((t) => t.id == movedId);
  if (movedIndex == -1) return tiles;
  final moved = tiles[movedIndex];

  final others = tiles.where((t) => t.id != movedId).toList()
    ..sort((a, b) {
      final rowCompare = a.row.compareTo(b.row);
      if (rowCompare != 0) return rowCompare;
      return a.col.compareTo(b.col);
    });

  final placed = <GridTile>[moved];
  for (final tile in others) {
    var candidate = tile;
    var changed = true;
    while (changed) {
      changed = false;
      for (final p in placed) {
        if (_overlaps(candidate, p)) {
          final newRow = p.row + p.rowSpan;
          if (newRow != candidate.row) {
            candidate = candidate.copyWith(row: newRow);
            changed = true;
          }
        }
      }
    }
    placed.add(candidate);
  }

  final byId = {for (final t in placed) t.id: t};
  return tiles.map((t) => byId[t.id] ?? t).toList();
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
