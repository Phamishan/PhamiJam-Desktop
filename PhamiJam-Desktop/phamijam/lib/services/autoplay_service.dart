import 'package:flutter/foundation.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class AutoplayService {
  AutoplayService._();

  static Future<List<Map<String, dynamic>>> fetchAutoplayContinuation(
    YTMusic ytmusic,
    String seedVideoId, {
    Set<String> excludeVideoIds = const {},
    int limit = 10,
  }) async {
    try {
      final result = await ytmusic.getWatchPlaylist(
        videoId: seedVideoId,
        radio: true,
        limit: 25,
      );
      final tracks = result['tracks'];
      if (tracks is! List) return [];

      final continuation = <Map<String, dynamic>>[];
      for (final item in tracks) {
        if (item is! Map<String, dynamic>) continue;
        final videoId = item['videoId'];
        if (videoId is! String ||
            videoId.isEmpty ||
            videoId == seedVideoId ||
            excludeVideoIds.contains(videoId)) {
          continue;
        }

        final artists = item['artists'];
        var artistName = 'YouTube Music';
        String? artistId;
        if (artists is List && artists.isNotEmpty) {
          final first = artists.first;
          if (first is Map) {
            final name = first['name']?.toString().trim() ?? '';
            if (name.isNotEmpty) artistName = name;
            final id = first['id']?.toString().trim() ?? '';
            if (id.isNotEmpty) artistId = id;
          }
        }

        final durationSeconds =
            (item['duration_seconds'] as num?)?.toInt() ??
            (item['durationSeconds'] as num?)?.toInt() ??
            0;

        continuation.add({
          'videoId': videoId,
          'songName': item['title']?.toString() ?? 'Unknown song',
          'artistName': artistName,
          'artistId': artistId,
          'durationSeconds': durationSeconds,
        });
        if (continuation.length >= limit) break;
      }
      return continuation;
    } catch (error) {
      debugPrint('AutoplayService: fetchAutoplayContinuation failed: $error');
      return [];
    }
  }
}
