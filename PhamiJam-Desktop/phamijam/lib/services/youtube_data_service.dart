import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';

class YoutubeDataService {
  YoutubeDataService._();

  static const String _baseUrl = 'https://www.googleapis.com/youtube/v3';

  static Future<String> _getAccessToken({bool forceRefresh = false}) async {
    final accessToken = await GoogleAuthService.ensureAccessToken(
      forceRefresh: forceRefresh,
    );
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Google access token not found. Please sign in again.');
    }
    return accessToken;
  }

  static Future<Map<String, dynamic>> _get(
    String path,
    Map<String, String> query,
  ) async {
    final uri = Uri.parse('$_baseUrl/$path').replace(queryParameters: query);
    var accessToken = await _getAccessToken();
    var response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 401) {
      accessToken = await _getAccessToken(forceRefresh: true);
      response = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('YouTube request failed (${response.statusCode}).');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Map<String, dynamic>? _bestThumbnail(Map<String, dynamic>? snippet) {
    final thumbnails = snippet?['thumbnails'] as Map<String, dynamic>?;
    if (thumbnails == null) return null;
    return (thumbnails['high'] ?? thumbnails['medium'] ?? thumbnails['default'])
        as Map<String, dynamic>?;
  }

  static Future<List<Map<String, dynamic>>> searchVideos(
    String query, {
    int maxResults = 25,
  }) async {
    final data = await _get('search', {
      'part': 'snippet',
      'q': query,
      'type': 'video',
      'maxResults': '$maxResults',
    });
    final items = data['items'] as List? ?? [];
    final results = <Map<String, dynamic>>[];
    for (final item in items) {
      final map = item as Map<String, dynamic>;
      final id = map['id'] as Map<String, dynamic>?;
      final videoId = id?['videoId'] as String? ?? '';
      if (videoId.isEmpty) continue;
      final snippet = map['snippet'] as Map<String, dynamic>?;
      results.add(<String, dynamic>{
        'videoId': videoId,
        'title': snippet?['title'] as String? ?? 'Unknown video',
        'artist': snippet?['channelTitle'] as String? ?? 'YouTube',
        'artistId': snippet?['channelId'] as String? ?? '',
        'thumbnailUrl': _bestThumbnail(snippet)?['url'] as String? ?? '',
      });
    }
    return results;
  }

  static Future<Map<String, dynamic>?> fetchChannelInfo(
    String channelId,
  ) async {
    final data = await _get('channels', {
      'part': 'snippet,statistics',
      'id': channelId,
    });
    final items = data['items'] as List? ?? [];
    if (items.isEmpty) return null;

    final map = items.first as Map<String, dynamic>;
    final snippet = map['snippet'] as Map<String, dynamic>?;
    final statistics = map['statistics'] as Map<String, dynamic>?;
    final hiddenSubscriberCount = statistics?['hiddenSubscriberCount'] == true;

    return <String, dynamic>{
      'id': channelId,
      'name': snippet?['title'] as String? ?? 'Unknown channel',
      'description': (snippet?['description'] as String? ?? '').trim(),
      'thumbnailUrl': _bestThumbnail(snippet)?['url'] as String? ?? '',
      'subscriberCount': hiddenSubscriberCount
          ? ''
          : (statistics?['subscriberCount'] as String? ?? ''),
    };
  }

  static Future<String?> _fetchUploadsPlaylistId(String channelId) async {
    final data = await _get('channels', {
      'part': 'contentDetails',
      'id': channelId,
    });
    final items = data['items'] as List? ?? [];
    if (items.isEmpty) return null;
    final contentDetails =
        (items.first as Map<String, dynamic>)['contentDetails']
            as Map<String, dynamic>?;
    final relatedPlaylists =
        contentDetails?['relatedPlaylists'] as Map<String, dynamic>?;
    return relatedPlaylists?['uploads'] as String?;
  }

  static Future<List<Map<String, dynamic>>> fetchChannelVideos(
    String channelId, {
    int maxItems = 25,
  }) async {
    final uploadsPlaylistId = await _fetchUploadsPlaylistId(channelId);
    if (uploadsPlaylistId == null || uploadsPlaylistId.isEmpty) return [];

    final videos = <Map<String, dynamic>>[];
    String? pageToken;
    while (videos.length < maxItems) {
      final remaining = maxItems - videos.length;
      final data = await _get('playlistItems', {
        'part': 'snippet',
        'playlistId': uploadsPlaylistId,
        'maxResults': '${remaining > 50 ? 50 : remaining}',
        if (pageToken != null) 'pageToken': pageToken,
      });

      final items = data['items'] as List? ?? [];
      for (final item in items) {
        final snippet =
            (item as Map<String, dynamic>)['snippet'] as Map<String, dynamic>?;
        final resourceId = snippet?['resourceId'] as Map<String, dynamic>?;
        final videoId = resourceId?['videoId'] as String? ?? '';
        if (videoId.isEmpty) continue;
        videos.add(<String, dynamic>{
          'videoId': videoId,
          'title': snippet?['title'] as String? ?? 'Unknown video',
          'artist':
              snippet?['videoOwnerChannelTitle'] as String? ??
              snippet?['channelTitle'] as String? ??
              'Unknown channel',
          'thumbnailUrl': _bestThumbnail(snippet)?['url'] as String? ?? '',
        });
        if (videos.length >= maxItems) break;
      }

      pageToken = data['nextPageToken'] as String?;
      if (pageToken == null) break;
    }
    return videos;
  }
}
