import 'package:flutter/services.dart' show rootBundle;

class ChangelogEntry {
  final String version;
  final String date;
  final List<String> changes;

  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });
}

class ChangelogService {
  ChangelogService._();

  static const String _assetPath = 'assets/CHANGELOG.md';
  static final RegExp _versionHeaderPattern = RegExp(r'^-\s+(\S+)\s*-\s*(.+)$');
  static final RegExp _subBulletPattern = RegExp(r'^\s+-\s+(.+)$');

  static List<ChangelogEntry>? _cache;

  static Future<List<ChangelogEntry>> load() async {
    final cached = _cache;
    if (cached != null) return cached;
    final raw = await rootBundle.loadString(_assetPath);
    final entries = _parse(raw);
    _cache = entries;
    return entries;
  }

  static List<ChangelogEntry> _parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final sectionStart = lines.indexWhere(
      (line) => line.trim().toLowerCase() == '## version history',
    );
    if (sectionStart == -1) return const [];

    final entries = <ChangelogEntry>[];
    String? currentVersion;
    String? currentDate;
    var currentChanges = <String>[];

    void flush() {
      final version = currentVersion;
      if (version == null) return;
      entries.add(
        ChangelogEntry(
          version: version,
          date: currentDate ?? '',
          changes: List.unmodifiable(currentChanges),
        ),
      );
    }

    for (var i = sectionStart + 1; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('## ')) break;

      final headerMatch = _versionHeaderPattern.firstMatch(line);
      if (headerMatch != null) {
        flush();
        currentVersion = headerMatch.group(1);
        currentDate = headerMatch.group(2)?.trim();
        currentChanges = [];
        continue;
      }

      final subMatch = _subBulletPattern.firstMatch(line);
      if (subMatch != null && currentVersion != null) {
        currentChanges.add(subMatch.group(1)!.trim());
      }
    }
    flush();

    return entries.reversed.toList();
  }
}
