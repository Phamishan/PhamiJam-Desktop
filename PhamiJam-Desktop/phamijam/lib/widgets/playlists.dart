import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/components/app_flushbar.dart';
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
  String _playlistSearchQuery = '';
  late final TextEditingController _playlistSearchController;
  YTMusic? _ytmusic;
  String? _channelId;

  List<Map<String, dynamic>> get _filteredPlaylists {
    final query = _playlistSearchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _userPlaylists;
    }

    return _userPlaylists.where((playlist) {
      final title = (playlist['title'] as String?) ?? '';
      final author = (playlist['author'] as String?) ?? '';
      final description = (playlist['description'] as String?) ?? '';
      return title.toLowerCase().contains(query) ||
          author.toLowerCase().contains(query) ||
          description.toLowerCase().contains(query);
    }).toList();
  }

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

  Future<http.Response> _youtubePostWithAutoRefresh(
    Uri uri, {
    required Object body,
  }) async {
    var accessToken = await _getAccessToken(forceRefresh: false);
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

  Future<http.Response> _youtubePutWithAutoRefresh(
    Uri uri, {
    required Object body,
  }) async {
    var accessToken = await _getAccessToken(forceRefresh: false);
    var response = await http.put(
      uri,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: body,
    );

    if (response.statusCode == 401) {
      accessToken = await _getAccessToken(forceRefresh: true);
      response = await http.put(
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

  Future<http.Response> _youtubeDeleteWithAutoRefresh(Uri uri) async {
    var accessToken = await _getAccessToken(forceRefresh: false);
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

  String _extractTextFromDynamic(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is List) {
      return value
          .map(_extractTextFromDynamic)
          .where((part) => part.isNotEmpty)
          .join(' ')
          .trim();
    }
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final directText = map['text'] as String?;
      if (directText != null && directText.isNotEmpty) {
        return directText;
      }
      final runs = map['runs'];
      if (runs != null) {
        final runsText = _extractTextFromDynamic(runs);
        if (runsText.isNotEmpty) {
          return runsText;
        }
      }
      final valueText = map['value'];
      if (valueText != null) {
        final extracted = _extractTextFromDynamic(valueText);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }
    return value.toString();
  }

  String _extractPlaylistDescription(Map<String, dynamic> playlist) {
    final candidates = [
      playlist['description'],
      playlist['subtitle'],
      playlist['secondSubtitle'],
    ];

    for (final candidate in candidates) {
      final text = _extractTextFromDynamic(candidate).trim();
      if (text.isNotEmpty) {
        return text;
      }
    }
    return '';
  }

  Map<String, dynamic> _normalizePlaylistItem(Map rawItem) {
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
      'description': (snippet['description'] as String?) ?? '',
      'author': (snippet['channelTitle'] as String?) ?? 'Unknown Author',
      'itemCount': '${contentDetails['itemCount'] ?? 0}',
      'playlistId': item['id'],
      'thumbnails': thumbnailList,
    };
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

    return items.whereType<Map>().map(_normalizePlaylistItem).toList();
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
        normalizedPlaylists = playlists.whereType<Map>().map((item) {
          final normalized = Map<String, dynamic>.from(item);
          normalized['description'] = _extractPlaylistDescription(normalized);
          return normalized;
        }).toList();
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
    _playlistSearchController = TextEditingController();
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

  Future<Map<String, dynamic>> _createPlaylist({
    required String title,
    required String description,
  }) async {
    final ensuredToken = await _getAccessToken(forceRefresh: false);
    if (ensuredToken.isEmpty) {
      throw Exception(
        'Unable to authorize playlist creation. Please sign in again.',
      );
    }

    final response = await _youtubePostWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlists?part=snippet,status',
      ),
      body: jsonEncode({
        'snippet': {'title': title, 'description': description},
        'status': {'privacyStatus': 'unlisted'},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final error = payload['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String?;
        if (message != null && message.isNotEmpty) {
          detail = ': $message';
        }
      } catch (_) {}

      throw Exception(
        'Failed to create playlist (${response.statusCode})$detail',
      );
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return _normalizePlaylistItem(payload);
    } catch (_) {
      return <String, dynamic>{
        'title': title,
        'description': description,
        'author': 'Unknown Author',
        'itemCount': '0',
        'playlistId': null,
        'thumbnails': const <Map<String, dynamic>>[],
      };
    }
  }

  Future<void> _deletePlaylist(String playlistId) async {
    final ensuredToken = await _getAccessToken(forceRefresh: false);
    if (ensuredToken.isEmpty) {
      throw Exception(
        'Unable to authorize playlist deletion. Please sign in again.',
      );
    }

    final response = await _youtubeDeleteWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlists?id=$playlistId',
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final error = payload['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String?;
        if (message != null && message.isNotEmpty) {
          detail = ': $message';
        }
      } catch (_) {}

      throw Exception(
        'Failed to delete playlist (${response.statusCode})$detail',
      );
    }
  }

  Future<void> _updatePlaylist({
    required String playlistId,
    required String title,
    required String description,
  }) async {
    final ensuredToken = await _getAccessToken(forceRefresh: false);
    if (ensuredToken.isEmpty) {
      throw Exception(
        'Unable to authorize playlist update. Please sign in again.',
      );
    }

    final response = await _youtubePutWithAutoRefresh(
      Uri.parse('https://www.googleapis.com/youtube/v3/playlists?part=snippet'),
      body: jsonEncode({
        'id': playlistId,
        'snippet': {'title': title, 'description': description},
      }),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      String detail = '';
      try {
        final payload = jsonDecode(response.body) as Map<String, dynamic>;
        final error = payload['error'] as Map<String, dynamic>?;
        final message = error?['message'] as String?;
        if (message != null && message.isNotEmpty) {
          detail = ': $message';
        }
      } catch (_) {}

      throw Exception(
        'Failed to update playlist (${response.statusCode})$detail',
      );
    }
  }

  Future<void> _confirmDeletePlaylist({
    required String playlistId,
    required String playlistTitle,
  }) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Playlist'),
          content: Text(
            'Delete "$playlistTitle"? This WILL delete the playlist on YouTube as well and cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete != true || !mounted) {
      return;
    }

    try {
      await _deletePlaylist(playlistId);
      if (!mounted) return;

      setState(() {
        _userPlaylists.removeWhere(
          (playlist) => (playlist['playlistId'] as String?) == playlistId,
        );
      });
      _cachedUserPlaylists = List<Map<String, dynamic>>.from(_userPlaylists);
      _cachedErrorMessage = null;

      AppFlushbar.success(context, 'Playlist deleted successfully.');

      await _fetchUserPlaylists(forceRefresh: true);
    } catch (e) {
      if (!mounted) return;
      AppFlushbar.error(context, '$e');
    }
  }

  void _showCreatePlaylistDialog() {
    final formKey = GlobalKey<FormState>();
    String title = '';
    String description = '';
    bool isCreating = false;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Create Playlist'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Title'),
                        onChanged: (value) => title = value,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter a title'
                            : null,
                      ),
                      TextFormField(
                        decoration: InputDecoration(labelText: 'Description'),
                        onChanged: (value) => description = value,
                      ),
                      SizedBox(height: 10),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: isCreating ? null : () => Navigator.of(context).pop(),
              child: Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isCreating
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      setState(() {
                        isCreating = true;
                      });

                      try {
                        final createdPlaylist = await _createPlaylist(
                          title: title.trim(),
                          description: description.trim(),
                        );
                        if (!mounted) return;

                        setState(() {
                          final createdId =
                              (createdPlaylist['playlistId'] as String?) ?? '';
                          if (createdId.isNotEmpty) {
                            _userPlaylists.removeWhere(
                              (playlist) =>
                                  (playlist['playlistId'] as String?) ==
                                  createdId,
                            );
                          }
                          _userPlaylists.insert(0, createdPlaylist);
                        });
                        _cachedUserPlaylists = List<Map<String, dynamic>>.from(
                          _userPlaylists,
                        );
                        _cachedErrorMessage = null;

                        Navigator.of(context).pop();
                        AppFlushbar.success(
                          this.context,
                          'Playlist created successfully.',
                        );
                      } catch (e) {
                        if (!mounted) return;
                        AppFlushbar.error(this.context, '$e');
                        setState(() {
                          isCreating = false;
                        });
                      }
                    },
              child: isCreating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Create'),
            ),
          ],
        );
      },
    );
  }

  void _showEditPlaylistDialog({
    required String playlistId,
    required String initialTitle,
    required String initialDescription,
  }) {
    final formKey = GlobalKey<FormState>();
    String title = initialTitle;
    String description = initialDescription;
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Edit Playlist'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        initialValue: initialTitle,
                        decoration: const InputDecoration(labelText: 'Title'),
                        onChanged: (value) => title = value,
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a title'
                            : null,
                      ),
                      TextFormField(
                        initialValue: initialDescription,
                        decoration: const InputDecoration(
                          labelText: 'Description',
                        ),
                        onChanged: (value) => description = value,
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: isSaving
                  ? null
                  : () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isSaving
                  ? null
                  : () async {
                      if (!formKey.currentState!.validate()) {
                        return;
                      }

                      setState(() {
                        isSaving = true;
                      });

                      try {
                        await _updatePlaylist(
                          playlistId: playlistId,
                          title: title.trim(),
                          description: description.trim(),
                        );
                        if (!mounted) return;

                        Navigator.of(dialogContext).pop();

                        setState(() {
                          for (final playlist in _userPlaylists) {
                            if ((playlist['playlistId'] as String?) ==
                                playlistId) {
                              playlist['title'] = title.trim();
                              playlist['description'] = description.trim();
                              break;
                            }
                          }
                        });
                        _cachedUserPlaylists = List<Map<String, dynamic>>.from(
                          _userPlaylists,
                        );

                        AppFlushbar.success(
                          this.context,
                          'Playlist updated successfully.',
                        );
                        await _fetchUserPlaylists(forceRefresh: true);
                      } catch (e) {
                        if (!mounted) return;
                        AppFlushbar.error(this.context, '$e');
                        setState(() {
                          isSaving = false;
                        });
                      }
                    },
              child: isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
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
            ElevatedButton.icon(
              onPressed: () {
                _showCreatePlaylistDialog();
              },
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create'),
            ),
            const SizedBox(width: 16),
            ElevatedButton.icon(
              onPressed: () => _fetchUserPlaylists(forceRefresh: true),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Refresh'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _playlistSearchController,
          onChanged: (value) {
            setState(() {
              _playlistSearchQuery = value;
            });
          },
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Search playlists...',
            hintStyle: const TextStyle(color: Colors.white60, fontSize: 14),
            prefixIcon: const Icon(Icons.search_rounded, color: Colors.white70),
            suffixIcon: _playlistSearchQuery.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                    onPressed: () {
                      _playlistSearchController.clear();
                      setState(() {
                        _playlistSearchQuery = '';
                      });
                    },
                  ),
            filled: true,
            fillColor: Colors.black26,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 0,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _filteredPlaylists.isEmpty
              ? const Center(
                  child: Text(
                    'No playlists found',
                    style: TextStyle(color: Colors.white70),
                  ),
                )
              : ListView.builder(
                  itemCount: _filteredPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = _filteredPlaylists[index];
                    final title =
                        (playlist['title'] as String?) ?? 'Unknown Playlist';
                    final description =
                        (playlist['description'] as String?) ?? '';
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
                        child: Material(
                          type: MaterialType.transparency,
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
                                                Icons.playlist_play_rounded,
                                                color: Colors.white,
                                              ),
                                    ),
                                  )
                                : const Icon(
                                    Icons.playlist_play_rounded,
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
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.black38,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.edit_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      final playlistId =
                                          (playlist['playlistId'] as String?) ??
                                          '';
                                      if (playlistId.isEmpty) {
                                        AppFlushbar.error(
                                          context,
                                          'This playlist cannot be edited.',
                                        );
                                        return;
                                      }

                                      _showEditPlaylistDialog(
                                        playlistId: playlistId,
                                        initialTitle: title,
                                        initialDescription: description,
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: IconButton(
                                    icon: const Icon(
                                      Icons.delete_rounded,
                                      color: Colors.white,
                                    ),
                                    onPressed: () {
                                      final playlistId =
                                          (playlist['playlistId'] as String?) ??
                                          '';
                                      if (playlistId.isEmpty) {
                                        AppFlushbar.error(
                                          context,
                                          'This playlist cannot be deleted.',
                                        );
                                        return;
                                      }

                                      _confirmDeletePlaylist(
                                        playlistId: playlistId,
                                        playlistTitle: title,
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              widget.onTabSelected?.call(
                                'playlist_inspect',
                                extra: {
                                  'playlistId': playlist['playlistId'],
                                  'playlistTitle': title,
                                  'thumbnailUrl': thumbnailUrl,
                                },
                              );
                            },
                          ),
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
    _playlistSearchController.dispose();
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
