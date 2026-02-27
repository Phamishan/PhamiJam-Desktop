import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class PlaylistsPage extends StatefulWidget {
  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;

  const PlaylistsPage({super.key, this.onTabSelected});

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

class _PlaylistsPageState extends State<PlaylistsPage> {
  static bool _hasLoadedOnce = false;
  static String? _cachedErrorMessage;
  static String _cachedPlaylistTitle = 'Playlists';
  static List<Map<String, dynamic>> _cachedUserPlaylists = [];
  static String? _cachedChannelId;

  bool _didInitialDependencySetup = false;
  bool _isLoadingPlaylists = false;
  String? _errorMessage;
  String _playlistTitle = 'Playlists';
  List<Map<String, dynamic>> _userPlaylists = [];
  YTMusic? _ytmusic;
  String? _channelId;

  Future<String> _getAccessToken({bool forceRefresh = false}) async {
    final accessToken = await GoogleAuthService.ensureAccessToken(
      forceRefresh: forceRefresh,
    );
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('Google access token not found. Please sign in again.');
    }
    return accessToken;
  }

  Future<http.Response> _youtubeGetWithAutoRefresh(Uri uri) async {
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

  bool _isUsableThumbnailUrl(String? url) {
    if (url == null || url.isEmpty) {
      return false;
    }

    final lowered = url.toLowerCase();
    if (lowered.contains('no_thumbnail.jpg')) {
      return false;
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> _fetchMinePlaylistsViaYouTubeApi() async {
    final response = await _youtubeGetWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlists?part=snippet,contentDetails&mine=true&maxResults=50',
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final error = payload['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String?;
        if (message != null && message.isNotEmpty) {
          detail = ' - $message';
        }
      } catch (_) {}
      throw Exception(
        'Failed to load mine playlists: ${response.statusCode}$detail',
      );
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (payload['items'] as List?) ?? const [];

    return items.whereType<Map>().map((rawItem) {
      final item = Map<String, dynamic>.from(rawItem);
      final snippet = Map<String, dynamic>.from(
        item['snippet'] as Map? ?? const <String, dynamic>{},
      );
      final contentDetails = Map<String, dynamic>.from(
        item['contentDetails'] as Map? ?? const <String, dynamic>{},
      );
      final thumbnailsMap = Map<String, dynamic>.from(
        snippet['thumbnails'] as Map? ?? const <String, dynamic>{},
      );

      final thumbnailList = <Map<String, dynamic>>[];
      for (final key in ['default', 'medium', 'high', 'standard', 'maxres']) {
        final thumbnail = thumbnailsMap[key] as Map?;
        if (thumbnail != null) {
          thumbnailList.add(Map<String, dynamic>.from(thumbnail));
        }
      }

      return <String, dynamic>{
        'title': (snippet['title'] as String?) ?? 'Unknown Playlist',
        'author': (snippet['channelTitle'] as String?) ?? 'Unknown Author',
        'itemCount': '${contentDetails['itemCount'] ?? 0}',
        'playlistId': item['id'],
        'thumbnails': thumbnailList,
      };
    }).toList();
  }

  Future<String?> _fetchCurrentUserChannelId() async {
    final response = await _youtubeGetWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/channels?part=id,snippet&mine=true',
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to resolve channel: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (payload['items'] as List?) ?? const [];
    if (items.isEmpty) return null;

    final firstItem = items.first as Map<String, dynamic>;
    return firstItem['id'] as String?;
  }

  Future<void> _fetchUserPlaylists({bool forceRefresh = false}) async {
    if (!forceRefresh && _hasLoadedOnce) {
      if (!mounted) return;
      setState(() {
        _playlistTitle = _cachedPlaylistTitle;
        _userPlaylists = List<Map<String, dynamic>>.from(_cachedUserPlaylists);
        _errorMessage = _cachedErrorMessage;
        _channelId = _cachedChannelId;
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoadingPlaylists = true;
      _errorMessage = null;
    });
    try {
      await _getAccessToken();

      if (_ytmusic == null) {
        await _initializeYTMusic();
      }

      try {
        final minePlaylists = await _fetchMinePlaylistsViaYouTubeApi();
        if (!mounted) return;
        setState(() {
          _userPlaylists = minePlaylists;
          _playlistTitle = 'Playlists';
        });
        _cachedUserPlaylists = List<Map<String, dynamic>>.from(minePlaylists);
        _cachedPlaylistTitle = 'Playlists';
        _cachedErrorMessage = null;
        _cachedChannelId = _channelId;
        _hasLoadedOnce = true;
        return;
      } catch (mineError) {
        debugPrint('YouTube mine playlists failed: $mineError');
      }

      final ytmusic = _ytmusic;
      if (ytmusic == null) {
        throw Exception('Music client is not initialized');
      }

      final resolvedChannelId =
          _channelId ?? await _fetchCurrentUserChannelId();
      if (resolvedChannelId == null || resolvedChannelId.isEmpty) {
        throw Exception('No YouTube channel found for signed-in account');
      }

      _channelId = resolvedChannelId;

      final user = await ytmusic.getUser(resolvedChannelId);
      final playlistsData = user['playlists'] as Map<String, dynamic>?;
      final params = playlistsData?['params'] as String?;

      List<Map<String, dynamic>> normalizedPlaylists;
      if (params != null && params.isNotEmpty) {
        final playlists = await ytmusic.getUserPlaylists(
          resolvedChannelId,
          params,
        );
        normalizedPlaylists = playlists
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      } else {
        normalizedPlaylists = await _fetchMinePlaylistsViaYouTubeApi();
      }

      if (!mounted) return;
      setState(() {
        _userPlaylists = normalizedPlaylists;
        _playlistTitle =
            (playlistsData?['title'] as String?) ?? 'User Playlists';
      });
      _cachedUserPlaylists = List<Map<String, dynamic>>.from(
        normalizedPlaylists,
      );
      _cachedPlaylistTitle =
          (playlistsData?['title'] as String?) ?? 'User Playlists';
      _cachedErrorMessage = null;
      _cachedChannelId = _channelId;
      _hasLoadedOnce = true;
    } catch (e) {
      debugPrint('Error fetching playlists: $e');
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to load playlists. Re-login Google and confirm YouTube Data API access.\n$e';
      });
      _cachedErrorMessage =
          'Failed to load playlists. Re-login Google and confirm YouTube Data API access.\n$e';
      _cachedPlaylistTitle = _playlistTitle;
      _cachedUserPlaylists = List<Map<String, dynamic>>.from(_userPlaylists);
      _cachedChannelId = _channelId;
      _hasLoadedOnce = true;
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencySetup) return;

    _didInitialDependencySetup = true;
    _fetchUserPlaylists(forceRefresh: false);
  }

  Future<void> _initializeYTMusic() async {
    final accessToken = await GoogleAuthService.ensureAccessToken();
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Please sign in with Google again.';
      });
      _cachedErrorMessage = _errorMessage;
      _hasLoadedOnce = true;
      return;
    }

    _ytmusic ??= await YTMusic.create(
      auth: {'authorization': 'Bearer $accessToken'},
    );
  }

  Widget _buildPlaylistsContent() {
    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: const TextStyle(color: Colors.white70, fontSize: 18),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _playlistTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _fetchUserPlaylists(forceRefresh: true),
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _userPlaylists.isEmpty
              ? const Center(
                  child: Text(
                    'No playlists found',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  itemCount: _userPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = _userPlaylists[index];
                    final title =
                        (playlist['title'] as String?) ?? 'Unknown Playlist';
                    final author =
                        (playlist['author'] as String?) ?? 'Unknown Author';
                    final itemCount =
                        (playlist['itemCount'] as String?) ??
                        (playlist['count'] as String?) ??
                        '';
                    final subtitle = itemCount.isNotEmpty
                        ? '$author • $itemCount songs'
                        : author;
                    final thumbnails =
                        (playlist['thumbnails'] as List?) ?? const [];
                    String? thumbnailUrl;
                    for (final rawThumbnail in thumbnails.reversed) {
                      if (rawThumbnail is! Map) {
                        continue;
                      }
                      final candidate = rawThumbnail['url'] as String?;
                      if (_isUsableThumbnailUrl(candidate)) {
                        thumbnailUrl = candidate;
                        break;
                      }
                    }

                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFdba43a),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ListTile(
                          leading:
                              thumbnailUrl != null && thumbnailUrl.isNotEmpty
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(6),
                                  child: Image.network(
                                    thumbnailUrl,
                                    width: 56,
                                    height: 56,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            const Icon(
                                              Icons.playlist_play,
                                              color: Colors.white,
                                            ),
                                  ),
                                )
                              : const Icon(
                                  Icons.playlist_play,
                                  color: Colors.white,
                                ),
                          title: Text(
                            title,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            subtitle,
                            style: const TextStyle(color: Colors.white70),
                          ),
                          trailing: const Icon(
                            Icons.play_arrow,
                            color: Colors.white,
                          ),
                          onTap: () {
                            widget.onTabSelected?.call(
                              'playlist_inspect',
                              extra: {
                                'playlistId': playlist['playlistId'],
                                'playlistTitle': title,
                              },
                            );
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _ytmusic?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: _buildPlaylistsContent(),
    );
  }
}
