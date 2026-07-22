import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';

class YoutubePlaylistService {
  YoutubePlaylistService._();

  static Future<String> _getAccessToken({bool forceRefresh = false}) async {
    final accessToken = await GoogleAuthService.ensureAccessToken(
      forceRefresh: forceRefresh,
    );
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Google access token not found. Please sign in again.');
    }
    return accessToken;
  }

  static Future<http.Response> _getWithAutoRefresh(Uri uri) async {
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
    return response;
  }

  static Future<http.Response> _postWithAutoRefresh(
    Uri uri, {
    required Object body,
  }) async {
    var accessToken = await _getAccessToken();
    var response = await http.post(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 401) {
      accessToken = await _getAccessToken(forceRefresh: true);
      response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );
    }
    return response;
  }

  static String _bestThumbnailUrl(Map<String, dynamic> snippet) {
    final thumbnails = snippet['thumbnails'] as Map? ?? const {};
    for (final key in ['high', 'medium', 'default']) {
      final url = (thumbnails[key] as Map?)?['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return '';
  }

  static Map<String, dynamic> _normalizePlaylistItem(Map rawItem) {
    final item = Map<String, dynamic>.from(rawItem);
    final snippet = Map<String, dynamic>.from(
      item['snippet'] as Map? ?? const <String, dynamic>{},
    );
    final contentDetails = Map<String, dynamic>.from(
      item['contentDetails'] as Map? ?? const <String, dynamic>{},
    );

    return <String, dynamic>{
      'playlistId': item['id'],
      'title': (snippet['title'] as String?) ?? 'Untitled playlist',
      'itemCount': (contentDetails['itemCount'] as num?)?.toInt() ?? 0,
      'thumbnailUrl': _bestThumbnailUrl(snippet),
    };
  }

  static Future<List<Map<String, dynamic>>> fetchMyPlaylists() async {
    final playlists = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/playlists')
          .replace(
            queryParameters: {
              'part': 'snippet,contentDetails',
              'mine': 'true',
              'maxResults': '50',
              'pageToken': ?pageToken,
            },
          );

      final response = await _getWithAutoRefresh(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Failed to load playlists (${response.statusCode}).');
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (payload['items'] as List? ?? const [])) {
        if (item is Map) playlists.add(_normalizePlaylistItem(item));
      }
      pageToken = payload['nextPageToken'] as String?;
    } while (pageToken != null);

    return playlists;
  }

  static Future<void> addVideoToPlaylist({
    required String playlistId,
    required String videoId,
  }) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/youtube/v3/playlistItems',
    ).replace(queryParameters: {'part': 'snippet'});

    final response = await _postWithAutoRefresh(
      uri,
      body: jsonEncode({
        'snippet': {
          'playlistId': playlistId,
          'resourceId': {'kind': 'youtube#video', 'videoId': videoId},
        },
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final message =
            (payload['error'] as Map<String, dynamic>?)?['message'] as String?;
        if (message != null && message.isNotEmpty) detail = ' - $message';
      } catch (_) {}
      throw Exception(
        'Failed to add to playlist (${response.statusCode})$detail.',
      );
    }
  }
}
