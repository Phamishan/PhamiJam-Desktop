import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytmusicapi_dart/models/lyrics.dart' as ytm;
import 'package:ytmusicapi_dart/navigation.dart';
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

  static final Map<String, SongLyrics?> _cache = {};

  static Future<SongLyrics?> fetchFor(String videoId) async {
    if (_cache.containsKey(videoId)) return _cache[videoId];

    SongLyrics? result;
    try {
      final ytmusic = await YTMusic.create();
      final browseId = await _fetchLyricsBrowseId(ytmusic, videoId);
      if (browseId != null) {
        List<LyricLine>? synced;
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
        } catch (_) {}

        String? plainText;
        String? source;
        try {
          final plain = await ytmusic.getLyrics(browseId);
          plainText = plain?['lyrics'] as String?;
          source = plain?['source'] as String?;
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

    _cache[videoId] = result;
    return result;
  }

  static Future<String?> _fetchLyricsBrowseId(
    YTMusic ytmusic,
    String videoId,
  ) async {
    final body = <String, dynamic>{
      'enablePersistentPlaylistPanel': true,
      'isAudioOnly': true,
      'tunerSettingValue': 'AUTOMIX_SETTING_NORMAL',
      'videoId': videoId,
      'watchEndpointMusicSupportedConfigs': {
        'watchEndpointMusicConfig': {
          'hasPersistentPlaylistPanel': true,
          'musicVideoType': 'MUSIC_VIDEO_TYPE_ATV',
        },
      },
    };
    final response = await ytmusic.sendRequest('next', body);
    final watchNextRenderer =
        nav(response, [
              'contents',
              'singleColumnMusicWatchNextResultsRenderer',
              'tabbedRenderer',
              'watchNextTabbedResultsRenderer',
            ], nullIfAbsent: true)
            as Map?;
    final tabs = watchNextRenderer?['tabs'];
    if (tabs is! List || tabs.length < 2) return null;
    final tabRenderer = (tabs[1] as Map?)?['tabRenderer'] as Map?;
    if (tabRenderer == null || tabRenderer.containsKey('unselectable')) {
      return null;
    }
    final endpoint = tabRenderer['endpoint'] as Map?;
    final browseEndpoint = endpoint?['browseEndpoint'] as Map?;
    return browseEndpoint?['browseId'] as String?;
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
