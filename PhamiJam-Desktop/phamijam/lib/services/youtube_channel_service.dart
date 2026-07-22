import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';

class ChannelInfo {
  final String id;
  final String name;
  final String thumbnailUrl;

  const ChannelInfo({
    required this.id,
    required this.name,
    required this.thumbnailUrl,
  });
}

class YoutubeChannelService {
  YoutubeChannelService._();

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

  static String _bestThumbnailUrl(Map<String, dynamic>? snippet) {
    final thumbnails = snippet?['thumbnails'] as Map? ?? const {};
    for (final key in ['high', 'medium', 'default']) {
      final url = (thumbnails[key] as Map?)?['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    return '';
  }

  static Future<Map<String, ChannelInfo>> fetchChannelsInfo(
    List<String> channelIds,
  ) async {
    if (channelIds.isEmpty) return {};
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/channels')
        .replace(
          queryParameters: {'part': 'snippet', 'id': channelIds.join(',')},
        );

    final response = await _getWithAutoRefresh(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) return {};

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final items = data['items'] as List? ?? const [];
    final result = <String, ChannelInfo>{};
    for (final item in items) {
      if (item is! Map) continue;
      final id = item['id'] as String?;
      if (id == null) continue;
      final snippet = item['snippet'] as Map<String, dynamic>?;
      result[id] = ChannelInfo(
        id: id,
        name: snippet?['title'] as String? ?? 'Unknown artist',
        thumbnailUrl: _bestThumbnailUrl(snippet),
      );
    }
    return result;
  }
}
