import 'package:flutter/material.dart';

enum GridWidgetType {
  bioHeader,
  featuredPlaylists,
  jamstatsHighlights,
  recentlyPlayed,
  likedSongs,
  topArtists,
  topTracks,
}

GridWidgetType? gridWidgetTypeFromString(String? value) {
  for (final type in GridWidgetType.values) {
    if (type.name == value) return type;
  }
  return null;
}

extension GridWidgetTypeMeta on GridWidgetType {
  List<(int, int)> get sizeVariants => switch (this) {
    GridWidgetType.bioHeader => const [(4, 1), (4, 2)],
    GridWidgetType.featuredPlaylists => const [(2, 1), (2, 2), (4, 2)],
    GridWidgetType.jamstatsHighlights => const [(2, 1), (2, 2)],
    GridWidgetType.recentlyPlayed => const [(2, 1), (2, 2), (4, 2)],
    GridWidgetType.likedSongs => const [(2, 1), (2, 2), (4, 2)],
    GridWidgetType.topArtists => const [(2, 1), (2, 2)],
    GridWidgetType.topTracks => const [(2, 1), (2, 2), (4, 2)],
  };

  (int, int) get defaultSize => sizeVariants.first;

  String get label => switch (this) {
    GridWidgetType.bioHeader => 'Bio',
    GridWidgetType.featuredPlaylists => 'Featured playlists',
    GridWidgetType.jamstatsHighlights => 'Jamstats highlights',
    GridWidgetType.recentlyPlayed => 'Recently played',
    GridWidgetType.likedSongs => 'Liked songs',
    GridWidgetType.topArtists => 'Top artists',
    GridWidgetType.topTracks => 'Top tracks',
  };

  IconData get icon => switch (this) {
    GridWidgetType.bioHeader => Icons.badge_rounded,
    GridWidgetType.featuredPlaylists => Icons.queue_music_rounded,
    GridWidgetType.jamstatsHighlights => Icons.auto_graph_rounded,
    GridWidgetType.recentlyPlayed => Icons.history_rounded,
    GridWidgetType.likedSongs => Icons.favorite_rounded,
    GridWidgetType.topArtists => Icons.mic_external_on_rounded,
    GridWidgetType.topTracks => Icons.leaderboard_rounded,
  };
}

class GridTile {
  final String id;
  final GridWidgetType widgetType;
  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;

  const GridTile({
    required this.id,
    required this.widgetType,
    required this.col,
    required this.row,
    required this.colSpan,
    required this.rowSpan,
  });

  GridTile copyWith({int? col, int? row, int? colSpan, int? rowSpan}) =>
      GridTile(
        id: id,
        widgetType: widgetType,
        col: col ?? this.col,
        row: row ?? this.row,
        colSpan: colSpan ?? this.colSpan,
        rowSpan: rowSpan ?? this.rowSpan,
      );

  Map<String, dynamic> toMap() => {
    'id': id,
    'widgetType': widgetType.name,
    'col': col,
    'row': row,
    'colSpan': colSpan,
    'rowSpan': rowSpan,
  };

  static GridTile? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final widgetType = gridWidgetTypeFromString(raw['widgetType'] as String?);
    final col = raw['col'];
    final row = raw['row'];
    final colSpan = raw['colSpan'];
    final rowSpan = raw['rowSpan'];
    if (id is! String ||
        id.isEmpty ||
        widgetType == null ||
        col is! int ||
        row is! int ||
        colSpan is! int ||
        rowSpan is! int) {
      return null;
    }
    return GridTile(
      id: id,
      widgetType: widgetType,
      col: col,
      row: row,
      colSpan: colSpan,
      rowSpan: rowSpan,
    );
  }
}
