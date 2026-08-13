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

  static Future<http.Response> _deleteWithAutoRefresh(Uri uri) async {
    var accessToken = await _getAccessToken();
    var response = await http.delete(
      uri,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 401) {
      accessToken = await _getAccessToken(forceRefresh: true);
      response = await http.delete(
        uri,
        headers: {'Authorization': 'Bearer $accessToken'},
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
    final status = Map<String, dynamic>.from(
      item['status'] as Map? ?? const <String, dynamic>{},
    );

    return <String, dynamic>{
      'playlistId': item['id'],
      'title': (snippet['title'] as String?) ?? 'Untitled playlist',
      'itemCount': (contentDetails['itemCount'] as num?)?.toInt() ?? 0,
      'thumbnailUrl': _bestThumbnailUrl(snippet),
      'privacyStatus': (status['privacyStatus'] as String?) ?? 'public',
    };
  }

  static Future<List<Map<String, dynamic>>> fetchMyPlaylists() async {
    final playlists = <Map<String, dynamic>>[];
    String? pageToken;

    do {
      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/playlists')
          .replace(
            queryParameters: {
              'part': 'snippet,contentDetails,status',
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

  static Future<Map<String, dynamic>?> fetchPlaylistMetadata(
    String playlistId,
  ) async {
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/playlists')
        .replace(
          queryParameters: {
            'part': 'snippet,contentDetails,status',
            'id': playlistId,
          },
        );
    final response = await _getWithAutoRefresh(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load playlist (${response.statusCode}).');
    }
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (payload['items'] as List?) ?? const [];
    if (items.isEmpty) return null;
    return _normalizePlaylistItem(items.first as Map);
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

  static Future<Map<String, String>> fetchPlaylistItemIds(
    String playlistId,
  ) async {
    final result = <String, String>{};
    String? pageToken;

    do {
      final uri =
          Uri.parse(
            'https://www.googleapis.com/youtube/v3/playlistItems',
          ).replace(
            queryParameters: {
              'part': 'contentDetails',
              'playlistId': playlistId,
              'maxResults': '50',
              'pageToken': ?pageToken,
            },
          );

      final response = await _getWithAutoRefresh(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to load playlist items (${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (payload['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final itemId = item['id'] as String?;
        final contentDetails = item['contentDetails'] as Map?;
        final videoId = contentDetails?['videoId'] as String?;
        if (itemId != null && videoId != null && videoId.isNotEmpty) {
          result[videoId] = itemId;
        }
      }
      pageToken = payload['nextPageToken'] as String?;
    } while (pageToken != null);

    return result;
  }

  static Future<Map<String, dynamic>> fetchPlaylistSongs(
    String playlistId,
  ) async {
    final metadataUri =
        Uri.parse('https://www.googleapis.com/youtube/v3/playlists').replace(
          queryParameters: {
            'part': 'snippet,contentDetails,status',
            'id': playlistId,
          },
        );
    final metadataResponse = await _getWithAutoRefresh(metadataUri);
    if (metadataResponse.statusCode < 200 ||
        metadataResponse.statusCode >= 300) {
      throw Exception(
        'Failed to load playlist (${metadataResponse.statusCode}).',
      );
    }
    final metadataPayload =
        jsonDecode(metadataResponse.body) as Map<String, dynamic>;
    final metadataItems = (metadataPayload['items'] as List?) ?? const [];
    final firstMetadataItem = metadataItems.isNotEmpty
        ? metadataItems.first
        : null;
    final playlistSnippet = firstMetadataItem is Map
        ? Map<String, dynamic>.from(
            firstMetadataItem['snippet'] as Map? ?? const {},
          )
        : const <String, dynamic>{};
    final playlistContentDetails = firstMetadataItem is Map
        ? Map<String, dynamic>.from(
            firstMetadataItem['contentDetails'] as Map? ?? const {},
          )
        : const <String, dynamic>{};
    final playlistStatus = firstMetadataItem is Map
        ? Map<String, dynamic>.from(
            firstMetadataItem['status'] as Map? ?? const {},
          )
        : const <String, dynamic>{};

    final songs = <Map<String, dynamic>>[];
    String? pageToken;
    do {
      final uri =
          Uri.parse(
            'https://www.googleapis.com/youtube/v3/playlistItems',
          ).replace(
            queryParameters: {
              'part': 'snippet',
              'playlistId': playlistId,
              'maxResults': '50',
              'pageToken': ?pageToken,
            },
          );

      final response = await _getWithAutoRefresh(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to load playlist items (${response.statusCode}).',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (payload['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final snippet = Map<String, dynamic>.from(
          item['snippet'] as Map? ?? const {},
        );
        final resourceId = snippet['resourceId'] as Map?;
        final videoId = resourceId?['videoId'] as String?;
        if (videoId == null || videoId.isEmpty) continue;

        final videoOwnerChannelTitle =
            snippet['videoOwnerChannelTitle'] as String?;
        final artist =
            (videoOwnerChannelTitle != null &&
                videoOwnerChannelTitle.isNotEmpty)
            ? videoOwnerChannelTitle
            : ((snippet['channelTitle'] as String?) ?? 'Unknown artist');
        final artistId =
            (snippet['videoOwnerChannelId'] as String?) ??
            (snippet['channelId'] as String?) ??
            '';

        songs.add(<String, dynamic>{
          'title': (snippet['title'] as String?) ?? 'Unknown song',
          'artist': artist,
          'artistId': artistId,
          'videoId': videoId,
          'thumbnailUrl': _bestThumbnailUrl(snippet),
        });
      }
      pageToken = payload['nextPageToken'] as String?;
    } while (pageToken != null);

    final durations = await _fetchVideoDurationsSeconds(
      songs.map((song) => song['videoId'] as String).toList(),
    );
    var totalDurationSeconds = 0;
    for (final song in songs) {
      final seconds = durations[song['videoId']] ?? 0;
      song['durationSeconds'] = seconds;
      totalDurationSeconds += seconds;
    }

    return <String, dynamic>{
      'title': playlistSnippet['title'] as String?,
      'creator': playlistSnippet['channelTitle'] as String?,
      'songCount':
          (playlistContentDetails['itemCount'] as num?)?.toInt() ??
          songs.length,
      'durationSeconds': totalDurationSeconds,
      'privacyStatus': playlistStatus['privacyStatus'] as String?,
      'songs': songs,
    };
  }

  static Future<int> fetchVideoDurationSeconds(String videoId) async {
    if (videoId.isEmpty) return 0;
    final result = await _fetchVideoDurationsSeconds([videoId]);
    return result[videoId] ?? 0;
  }

  static Future<Map<String, int>> _fetchVideoDurationsSeconds(
    List<String> videoIds,
  ) async {
    final result = <String, int>{};
    for (var i = 0; i < videoIds.length; i += 50) {
      final end = i + 50 < videoIds.length ? i + 50 : videoIds.length;
      final batch = videoIds.sublist(i, end);
      if (batch.isEmpty) continue;

      final uri = Uri.parse('https://www.googleapis.com/youtube/v3/videos')
          .replace(
            queryParameters: {'part': 'contentDetails', 'id': batch.join(',')},
          );
      final response = await _getWithAutoRefresh(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) continue;

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      for (final item in (payload['items'] as List? ?? const [])) {
        if (item is! Map) continue;
        final id = item['id'] as String?;
        final iso = (item['contentDetails'] as Map?)?['duration'] as String?;
        if (id == null || iso == null) continue;
        result[id] = _parseIso8601Duration(iso);
      }
    }
    return result;
  }

  static int _parseIso8601Duration(String iso) {
    final match = RegExp(
      r'^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$',
    ).firstMatch(iso);
    if (match == null) return 0;
    final hours = int.tryParse(match.group(1) ?? '') ?? 0;
    final minutes = int.tryParse(match.group(2) ?? '') ?? 0;
    final seconds = int.tryParse(match.group(3) ?? '') ?? 0;
    return hours * 3600 + minutes * 60 + seconds;
  }

  static Future<void> removeVideoFromPlaylist(String playlistItemId) async {
    final uri = Uri.parse(
      'https://www.googleapis.com/youtube/v3/playlistItems',
    ).replace(queryParameters: {'id': playlistItemId});

    final response = await _deleteWithAutoRefresh(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final message =
            (payload['error'] as Map<String, dynamic>?)?['message'] as String?;
        if (message != null && message.isNotEmpty) detail = ' - $message';
      } catch (_) {}
      throw Exception(
        'Failed to remove from playlist (${response.statusCode})$detail.',
      );
    }
  }
}
