import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytmusicapi_dart/models/lyrics.dart' as ytm;
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class LyricLine {
  final String text;
  final Duration start;
  final Duration end;

  const LyricLine({required this.text, required this.start, required this.end});
}

class SongLyrics {
  final List<LyricLine>? synced;
  final String? plainText;
  final String? source;

  const SongLyrics({this.synced, this.plainText, this.source});

  bool get hasSynced => synced != null && synced!.isNotEmpty;
  bool get hasAny =>
      hasSynced || (plainText != null && plainText!.trim().isNotEmpty);
}

class LyricsService {
  LyricsService._();

  static const String _offsetPrefsPrefix = 'phamijam.lyrics_sync_offset.';
  static const Map<String, String> _lrclibHeaders = {
    'User-Agent': 'PhamiJam (https://phamishan.dk)',
  };
  static const int _lrclibDurationToleranceSeconds = 10;
  static const int _lrclibNoArtistDurationToleranceSeconds = 3;

  static final Map<String, SongLyrics?> _cache = {};

  static Future<SongLyrics?> fetchFor(
    String videoId, {
    String? title,
    String? artist,
    int? durationSeconds,
  }) async {
    if (_cache.containsKey(videoId)) return _cache[videoId];

    SongLyrics? result;
    try {
      final ytmusic = await YTMusic.create();
      final watchPlaylist = await ytmusic.getWatchPlaylist(videoId: videoId);
      final browseId = watchPlaylist['lyrics'] as String?;
      if (browseId != null) {
        List<LyricLine>? synced;
        String? source;
        try {
          final timed = await ytmusic.getLyrics(browseId, timestamps: true);
          final rawLines = timed?['lyrics'];
          if (rawLines is List<ytm.LyricLine>) {
            synced = rawLines
                .map(
                  (line) => LyricLine(
                    text: line.text,
                    start: Duration(milliseconds: line.startTime),
                    end: Duration(milliseconds: line.endTime),
                  ),
                )
                .toList();
          }
          source = timed?['source'] as String?;
        } catch (_) {}

        String? plainText;
        try {
          final plain = await ytmusic.getLyrics(browseId);
          plainText = plain?['lyrics'] as String?;
        } catch (_) {}

        if (synced != null || plainText != null) {
          result = SongLyrics(
            synced: synced,
            plainText: plainText,
            source: source,
          );
        }
      }
    } catch (_) {
      result = null;
    }

    if ((result == null || !result.hasAny) &&
        title != null &&
        title.trim().isNotEmpty) {
      try {
        result = await _fetchFromLrclib(
          title: title,
          artist: artist ?? '',
          durationSeconds: durationSeconds,
        );
      } catch (_) {}
    }

    _cache[videoId] = result;
    return result;
  }

  static final RegExp _bracketedNoise = RegExp(
    r'[\(\[][^\)\]]*(official|video|audio|lyrics?|hd|4k|remaster\w*|visualizer|mv)[^\)\]]*[\)\]]',
    caseSensitive: false,
  );

  static final RegExp _featuringSuffix = RegExp(
    r'\s*[\(\[]?\b(?:feat|ft|featuring)\b\.?\s+.*$',
    caseSensitive: false,
  );

  static String _cleanTitle(String title) {
    return title
        .replaceAll(_bracketedNoise, '')
        .replaceAll(_featuringSuffix, '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String _stripLeadingArtist(String title, String artist) {
    if (artist.isEmpty) return title;
    final prefix = RegExp(
      '^${RegExp.escape(artist)}\\s*[-:]\\s*',
      caseSensitive: false,
    );
    return title.replaceFirst(prefix, '').trim();
  }

  static final RegExp _topicSuffix = RegExp(
    r'\s*-\s*Topic$',
    caseSensitive: false,
  );

  static String _cleanArtist(String artist) {
    return artist.replaceFirst(_topicSuffix, '').trim();
  }

  static Future<SongLyrics?> _fetchFromLrclib({
    required String title,
    required String artist,
    int? durationSeconds,
  }) async {
    final cleanedArtist = _cleanArtist(artist);
    final baseTitle = _cleanTitle(title);
    if (baseTitle.isEmpty) return null;

    final dashParts = baseTitle.split(RegExp(r'\s+-\s+'));
    final titleAfterDash = dashParts.length >= 2
        ? dashParts.sublist(1).join(' - ')
        : baseTitle;

    final attempts = <({String track, String artist})>[
      (
        track: _stripLeadingArtist(baseTitle, cleanedArtist),
        artist: cleanedArtist,
      ),
      if (dashParts.length >= 2)
        (track: titleAfterDash, artist: dashParts.first.trim()),
      (track: titleAfterDash, artist: ''),
    ];

    final seen = <String>{};
    for (final attempt in attempts) {
      final track = attempt.track.trim();
      if (track.isEmpty) continue;
      final key = '${track.toLowerCase()}|${attempt.artist.toLowerCase()}';
      if (!seen.add(key)) continue;

      final result = await _searchLrclib(
        trackName: track,
        artistName: attempt.artist,
        durationSeconds: durationSeconds,
        toleranceSeconds: attempt.artist.isEmpty
            ? _lrclibNoArtistDurationToleranceSeconds
            : _lrclibDurationToleranceSeconds,
      );
      if (result != null) return result;
    }
    return null;
  }

  static Future<SongLyrics?> _searchLrclib({
    required String trackName,
    required String artistName,
    int? durationSeconds,
    required int toleranceSeconds,
  }) async {
    final uri = Uri.https('lrclib.net', '/api/search', {
      'track_name': trackName,
      if (artistName.isNotEmpty) 'artist_name': artistName,
    });
    final response = await http
        .get(uri, headers: _lrclibHeaders)
        .timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) return null;

    final results = jsonDecode(response.body);
    if (results is! List || results.isEmpty) return null;

    final candidates = results
        .whereType<Map<String, dynamic>>()
        .where((r) => r['syncedLyrics'] != null || r['plainLyrics'] != null)
        .toList();
    if (candidates.isEmpty) return null;

    Map<String, dynamic> best = candidates.first;
    if (durationSeconds != null && durationSeconds > 0) {
      candidates.sort((a, b) {
        final da = ((a['duration'] as num?)?.toInt() ?? 0) - durationSeconds;
        final db = ((b['duration'] as num?)?.toInt() ?? 0) - durationSeconds;
        return da.abs().compareTo(db.abs());
      });
      best = candidates.first;
      final bestDuration = (best['duration'] as num?)?.toInt() ?? 0;
      if ((bestDuration - durationSeconds).abs() > toleranceSeconds) {
        return null;
      }
    }

    final syncedLyricsRaw = best['syncedLyrics'] as String?;
    final plainLyrics = best['plainLyrics'] as String?;
    final synced = syncedLyricsRaw == null ? null : _parseLrc(syncedLyricsRaw);

    if ((synced == null || synced.isEmpty) &&
        (plainLyrics == null || plainLyrics.trim().isEmpty)) {
      return null;
    }

    return SongLyrics(synced: synced, plainText: plainLyrics, source: 'LRCLIB');
  }

  static final RegExp _lrcLineRegExp = RegExp(
    r'^\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\](.*)$',
  );

  static List<LyricLine>? _parseLrc(String lrc) {
    final rawLines = <({Duration start, String text})>[];
    for (final line in lrc.split('\n')) {
      final match = _lrcLineRegExp.firstMatch(line.trim());
      if (match == null) continue;
      final text = match.group(4)!.trim();
      if (text.isEmpty) continue;
      final minutes = int.parse(match.group(1)!);
      final seconds = int.parse(match.group(2)!);
      final fraction = match.group(3);
      final millis = fraction == null
          ? 0
          : int.parse(fraction.padRight(3, '0').substring(0, 3));
      rawLines.add((
        start: Duration(
          minutes: minutes,
          seconds: seconds,
          milliseconds: millis,
        ),
        text: text,
      ));
    }
    if (rawLines.isEmpty) return null;

    final lines = <LyricLine>[];
    for (var i = 0; i < rawLines.length; i++) {
      final end = i + 1 < rawLines.length
          ? rawLines[i + 1].start
          : rawLines[i].start + const Duration(seconds: 6);
      lines.add(
        LyricLine(text: rawLines[i].text, start: rawLines[i].start, end: end),
      );
    }
    return lines;
  }

  static Future<int> getSyncOffsetMs(String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_offsetPrefsPrefix$videoId') ?? 0;
  }

  static Future<void> setSyncOffsetMs(String videoId, int offsetMs) async {
    final prefs = await SharedPreferences.getInstance();
    if (offsetMs == 0) {
      await prefs.remove('$_offsetPrefsPrefix$videoId');
    } else {
      await prefs.setInt('$_offsetPrefsPrefix$videoId', offsetMs);
    }
  }
}
