import 'package:phamijam/services/youtube_playlist_service.dart';
import 'package:ytmusicapi_dart/navigation.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class ChartsService {
  ChartsService._();

  static final Map<String, Map<String, dynamic>?> _cache = {};

  static Future<Map<String, dynamic>?> fetchTopPlaylist({
    required String countryCode,
    required String displayTitle,
    int targetSize = 50,
  }) async {
    final cacheKey = '$countryCode:$targetSize';
    if (_cache.containsKey(cacheKey)) return _cache[cacheKey];

    Map<String, dynamic>? result;
    try {
      var songs = <Map<String, dynamic>>[];
      try {
        final ytmusic = await YTMusic.create();
        final playlistId = await _resolveTopVideosPlaylistId(
          ytmusic,
          countryCode,
        );
        if (playlistId != null) {
          final playlistData = await YoutubePlaylistService.fetchPlaylistSongs(
            playlistId,
          );
          songs = ((playlistData['songs'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .take(targetSize)
              .toList();
        }
      } catch (_) {
        songs = [];
      }

      if (songs.length < targetSize) {
        try {
          final regional = await YoutubePlaylistService.fetchRegionalMusicChart(
            countryCode,
            maxResults: targetSize,
          );
          if (regional.length > songs.length) songs = regional;
        } catch (_) {}
      }

      if (songs.length > targetSize) {
        songs = songs.take(targetSize).toList();
      }

      if (songs.isNotEmpty) {
        final totalDurationSeconds = songs
            .map((song) => song['durationSeconds'])
            .whereType<int>()
            .fold<int>(0, (sum, secs) => sum + secs);
        result = <String, dynamic>{
          'playlistId': 'phamijam-chart-$countryCode',
          'title': displayTitle,
          'thumbnailUrl': songs.first['thumbnailUrl'],
          'itemCount': songs.length,
          'songCount': songs.length,
          'durationSeconds': totalDurationSeconds,
          'privacyStatus': 'public',
          'songs': songs,
        };
      }
    } catch (_) {
      result = null;
    }

    _cache[cacheKey] = result;
    return result;
  }

  static Future<String?> _resolveTopVideosPlaylistId(
    YTMusic ytmusic,
    String country,
  ) async {
    final body = <String, dynamic>{'browseId': 'FEmusic_charts'};
    if (country.isNotEmpty) {
      body['formData'] = {
        'selectedValues': [country],
      };
    }
    final response = await ytmusic.sendRequest('browse', body);
    final results =
        nav(response, [...SINGLE_COLUMN_TAB, ...SECTION_LIST]) as List;

    for (final section in results.skip(1)) {
      final contents = nav(section, CAROUSEL_CONTENTS, nullIfAbsent: true);
      if (contents is! List || contents.isEmpty) continue;
      final browseId = nav(contents.first, [
        MTRIR,
        ...TITLE,
        ...NAVIGATION_BROWSE_ID,
      ], nullIfAbsent: true);
      if (browseId is String && browseId.startsWith('VL')) {
        return browseId.substring(2);
      }
    }
    return null;
  }
}
