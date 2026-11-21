import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_context_menu/flutter_context_menu.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/services/google_auth_service.dart';
import 'package:phamijam/components/app_flushbar.dart';
import 'package:phamijam/components/delete_playlist_dialog.dart';
import 'package:phamijam/components/edit_playlist_dialog.dart';
import 'package:phamijam/providers/playlist_pin_provider.dart';
import 'package:phamijam/providers/saved_playlists_provider.dart';
import 'package:phamijam/providers/settings_provider.dart';
import 'package:phamijam/components/mixed_playlist_dialogs.dart';
import 'package:phamijam/services/mixed_playlist_service.dart';
import 'package:phamijam/services/playlist_cover_service.dart';
import 'package:phamijam/services/share_link_service.dart';
import 'package:provider/provider.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:phamijam/services/playlist_filter_prefs.dart';

class PlaylistsPage extends StatefulWidget {
  final void Function(String, {Map<String, dynamic>? extra})? onTabSelected;
  const PlaylistsPage({super.key, this.onTabSelected});
  static void resetCache() => _PlaylistsPageState._resetCache();

  @override
  State<PlaylistsPage> createState() => _PlaylistsPageState();
}

enum _PlaylistFilter { all, youtube, phamijam, saved }

class _PlaylistsPageState extends State<PlaylistsPage> {
  _PlaylistFilter _filter = _PlaylistFilter.all;

  Future<void> _restoreFilter() async {
    final saved = await PlaylistFilterPrefs.load();
    if (saved == null || !mounted) return;
    final match = _PlaylistFilter.values.where((f) => f.name == saved);
    if (match.isNotEmpty) setState(() => _filter = match.first);
  }

  void _selectFilter(_PlaylistFilter value) {
    if (value == _filter) return;
    setState(() => _filter = value);
    Log.i('library', 'playlist filter -> ${value.name}');
    PlaylistFilterPrefs.save(
      value.name,
      isDefault: value == _PlaylistFilter.all,
    );
  }

  Widget _buildFilterChips({
    required int youtube,
    required int phamijam,
    required int saved,
  }) {
    Widget chip(_PlaylistFilter filter, String label, int count) => Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text('$label · $count'),
        selected: _filter == filter,
        onSelected: (_) => _selectFilter(filter),
      ),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip(_PlaylistFilter.all, 'All', youtube + phamijam + saved),
          chip(_PlaylistFilter.youtube, 'YouTube', youtube),
          chip(_PlaylistFilter.phamijam, 'PhamiJam', phamijam),
          chip(_PlaylistFilter.saved, 'Saved', saved),
        ],
      ),
    );
  }

  static bool _hasLoadedOnce = false;
  static String? _cachedErrorMessage;
  static String _cachedPlaylistTitle = 'Playlists';
  static List<Map<String, dynamic>> _cachedUserPlaylists = [];
  static String? _cachedChannelId;

  static void _resetCache() {
    _hasLoadedOnce = false;
    _cachedErrorMessage = null;
    _cachedPlaylistTitle = 'Playlists';
    _cachedUserPlaylists = [];
    _cachedChannelId = null;
  }

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
    final status = Map<String, dynamic>.from(
      item['status'] as Map? ?? const <String, dynamic>{},
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
      'privacyStatus': (status['privacyStatus'] as String?) ?? 'public',
      'thumbnails': thumbnailList,
    };
  }

  Future<List<Map<String, dynamic>>> _fetchMinePlaylistsViaYouTubeApi() async {
    final response = await _youtubeGetWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlists?part=snippet,contentDetails,status&mine=true&maxResults=50',
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
      } catch (error) {
        Log.w('library', 'normalize playlist item failed', error);
      }
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
    if (forceRefresh) {
      _ytmusic?.close();
      _ytmusic = null;
      _channelId = null;
    }
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
        Log.e('library', 'fetch user playlists failed', mineError);
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
      Log.e('library', 'fetch user playlists failed', e);
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

  StreamSubscription<Map<String, String>>? _playlistCoverSubscription;

  @override
  void initState() {
    super.initState();
    _restoreFilter();
    _playlistSearchController = TextEditingController();
    _playlistCoverSubscription = PlaylistCoverService.watchAll().listen(
      _applyPlaylistCoverOverrides,
    );
    _mixedSubscription = MixedPlaylistService.watchAll().listen((playlists) {
      if (!mounted) return;
      setState(() => _mixedPlaylists = playlists);
    }, onError: (_) {});
  }

  StreamSubscription<List<Map<String, dynamic>>>? _mixedSubscription;
  List<Map<String, dynamic>> _mixedPlaylists = [];

  Future<void> _createMixedPlaylist() async {
    final name = await showMixedPlaylistNameDialog(context);
    if (name == null || !mounted) return;
    try {
      await MixedPlaylistService.create(name);
    } catch (error) {
      Log.e('library', 'create mixed playlist failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't create playlist: $error");
      }
    }
  }

  void _editMixedPlaylist(Map<String, dynamic> playlist) {
    final id = playlist['id'] as String;
    final tracks = ((playlist['tracks'] as List?) ?? const []).whereType<Map>();
    final firstThumb = tracks
        .map((t) => (t['thumbnailUrl'] as String?) ?? '')
        .firstWhere((u) => u.isNotEmpty, orElse: () => '');
    final coverKey = MixedPlaylistService.coverKey(id);
    final customCover = _coverOverrides[coverKey];
    final hasCustomCover = customCover != null && customCover.isNotEmpty;
    showEditPlaylistDialog(
      context,
      playlistId: coverKey,
      mixedPlaylistId: id,
      initialTitle: (playlist['title'] as String?) ?? '',
      initialDescription: (playlist['description'] as String?) ?? '',
      initialPrivacyStatus: 'private',
      initialThumbnailUrl: hasCustomCover ? customCover : firstThumb,
      originalThumbnailUrl: firstThumb,
      initialCustomCoverUrl: hasCustomCover ? customCover : null,
      onUpdated: (_, _, _) {},
      onCoverChanged: (customCoverUrl) {
        if (!mounted) return;
        setState(() {
          _coverOverrides = {..._coverOverrides};
          if (customCoverUrl == null) {
            _coverOverrides.remove(coverKey);
          } else {
            _coverOverrides[coverKey] = customCoverUrl;
          }
        });
      },
    );
  }

  Future<void> _deleteMixedPlaylist(Map<String, dynamic> playlist) async {
    final title = (playlist['title'] as String?) ?? 'Untitled playlist';
    final confirmed = await confirmDeleteMixedPlaylist(context, title);
    if (!confirmed) return;
    try {
      final id = playlist['id'] as String;
      final export = await MixedPlaylistService.exportPlaylist(id);
      await MixedPlaylistService.delete(id);
      if (!mounted) return;
      unawaited(context.read<PlaylistPinProvider>().clearPin('mixed-$id'));
      if (export != null) {
        AppFlushbar.undo(
          context,
          'Deleted "$title"',
          onUndo: () {
            MixedPlaylistService.restorePlaylist(export).catchError((
              Object error,
            ) {
              Log.w('library', 'undo delete failed', error);
              return '';
            });
          },
        );
      }
    } catch (error) {
      Log.e('library', 'delete mixed playlist failed', error);
      if (mounted) {
        AppFlushbar.error(context, "Couldn't delete playlist: $error");
      }
    }
  }

  Widget _buildMixedPlaylistTile(
    Map<String, dynamic> playlist,
    PlaylistPinProvider pins,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final id = playlist['id'] as String;
    final pinKey = 'mixed-$id';
    final isPinned = pins.isPinned(pinKey);
    final title = (playlist['title'] as String?) ?? 'Untitled playlist';
    final count = (playlist['tracks'] as List?)?.length ?? 0;
    final customCover = _coverOverrides[MixedPlaylistService.coverKey(id)];
    final hasCustomCover = customCover != null && customCover.isNotEmpty;
    final coverUrl = hasCustomCover
        ? customCover
        : ((playlist['tracks'] as List?) ?? const [])
              .whereType<Map>()
              .map((t) => (t['thumbnailUrl'] as String?) ?? '')
              .firstWhere((u) => u.isNotEmpty, orElse: () => '');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ContextMenuRegion<String>(
        contextMenu: ContextMenu(
          borderRadius: BorderRadius.circular(12),
          entries: [
            MenuItem<String>(
              value: 'toggle_pin',
              icon: Icon(
                isPinned ? Icons.push_pin_outlined : Icons.push_pin_rounded,
              ),
              label: Text(isPinned ? 'Unpin playlist' : 'Pin playlist'),
            ),
            MenuItem<String>(
              value: 'edit',
              icon: const Icon(Icons.edit_rounded),
              label: const Text('Edit playlist'),
            ),
            MenuItem<String>(
              value: 'delete',
              icon: const Icon(Icons.delete_rounded),
              label: const Text('Delete playlist'),
            ),
          ],
        ),
        onItemSelected: (value) {
          if (value == 'toggle_pin') {
            pins.togglePin(pinKey);
          } else if (value == 'edit') {
            _editMixedPlaylist(playlist);
          } else if (value == 'delete') {
            _deleteMixedPlaylist(playlist);
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: coverUrl.isEmpty
                      ? Container(
                          color: colorScheme.primary.withValues(alpha: 0.2),
                          child: Icon(
                            Icons.library_music_rounded,
                            color: colorScheme.primary,
                          ),
                        )
                      : Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: colorScheme.primary.withValues(alpha: 0.2),
                            child: Icon(
                              Icons.library_music_rounded,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                ),
              ),
              title: Text(
                title,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                'PhamiJam playlist - $count ${count == 1 ? 'song' : 'songs'}',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      icon: Icon(
                        isPinned
                            ? Icons.push_pin_rounded
                            : Icons.push_pin_outlined,
                        color: colorScheme.onSurface,
                      ),
                      onPressed: () => pins.togglePin(pinKey),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.edit_rounded,
                        color: colorScheme.onSurface,
                      ),
                      onPressed: () => _editMixedPlaylist(playlist),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.error,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.delete_rounded,
                        color: colorScheme.onError,
                      ),
                      onPressed: () => _deleteMixedPlaylist(playlist),
                    ),
                  ),
                ],
              ),
              onTap: () => widget.onTabSelected?.call(
                'mixed_playlist',
                extra: {'playlistId': id},
              ),
            ),
          ),
        ),
      ),
    );
  }

  Map<String, String> _coverOverrides = {};

  void _applyPlaylistCoverOverrides(Map<String, String> overrides) {
    if (!mounted) return;
    setState(() => _coverOverrides = overrides);
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
      } catch (error) {
        Log.w('library', 'initialize ytmusic failed', error);
      }

      throw Exception(
        'Failed to create playlist (${response.statusCode})$detail',
      );
    }

    try {
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      return _normalizePlaylistItem(payload);
    } catch (error) {
      Log.w('library', 'initialize ytmusic failed', error);
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

  Future<void> _confirmDeletePlaylist({
    required String playlistId,
    required String playlistTitle,
  }) {
    return confirmDeletePlaylist(
      context,
      playlistId: playlistId,
      playlistTitle: playlistTitle,
      onDeleted: () {
        if (!mounted) return;
        setState(() {
          _userPlaylists.removeWhere(
            (playlist) => (playlist['playlistId'] as String?) == playlistId,
          );
        });
        _cachedUserPlaylists = List<Map<String, dynamic>>.from(_userPlaylists);
        _cachedErrorMessage = null;
        unawaited(_fetchUserPlaylists(forceRefresh: true));
      },
    );
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
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
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

                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        AppFlushbar.success(
                          this.context,
                          'Playlist created successfully.',
                        );
                      } catch (e) {
                        Log.e(
                          'library',
                          'show create playlist dialog failed',
                          e,
                        );
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

  void _showSavePlaylistDialog() {
    final formKey = GlobalKey<FormState>();
    String link = '';
    bool isSaving = false;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Save a playlist'),
          content: StatefulBuilder(
            builder: (context, setState) {
              return SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Paste a link to any public YouTube playlist to save",
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        autofocus: true,
                        decoration: const InputDecoration(
                          labelText: 'Playlist link',
                          hintText: 'https://www.youtube.com/playlist?list=...',
                        ),
                        onChanged: (value) => link = value,
                        validator: (value) => value == null || value.isEmpty
                            ? 'Enter a playlist link'
                            : null,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: isSaving ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            StatefulBuilder(
              builder: (context, setState) => ElevatedButton(
                style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
                onPressed: isSaving
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setState(() => isSaving = true);
                        final error = await this.context
                            .read<SavedPlaylistsProvider>()
                            .saveFromInput(link.trim());
                        if (!context.mounted) return;
                        if (error == null) {
                          Navigator.of(context).pop();
                          if (!mounted) return;
                          AppFlushbar.success(this.context, 'Playlist saved');
                        } else {
                          setState(() => isSaving = false);
                          if (!mounted) return;
                          AppFlushbar.error(this.context, error);
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
    required String initialPrivacyStatus,
    String initialThumbnailUrl = '',
    String? originalThumbnailUrl,
    String? initialCustomCoverUrl,
  }) {
    showEditPlaylistDialog(
      context,
      playlistId: playlistId,
      initialTitle: initialTitle,
      initialDescription: initialDescription,
      initialPrivacyStatus: initialPrivacyStatus,
      initialThumbnailUrl: initialThumbnailUrl,
      originalThumbnailUrl: originalThumbnailUrl,
      initialCustomCoverUrl: initialCustomCoverUrl,
      onUpdated: (title, description, privacyStatus) {
        if (!mounted) return;
        setState(() {
          for (final playlist in _userPlaylists) {
            if ((playlist['playlistId'] as String?) == playlistId) {
              playlist['title'] = title;
              playlist['description'] = description;
              playlist['privacyStatus'] = privacyStatus;
              break;
            }
          }
        });
        _cachedUserPlaylists = List<Map<String, dynamic>>.from(_userPlaylists);
        unawaited(_fetchUserPlaylists(forceRefresh: true));
      },
      onCoverChanged: (customCoverUrl) {
        if (!mounted) return;
        setState(() {
          _coverOverrides = {..._coverOverrides};
          if (customCoverUrl == null) {
            _coverOverrides.remove(playlistId);
          } else {
            _coverOverrides[playlistId] = customCoverUrl;
          }
        });
      },
    );
  }

  Widget _buildPlaylistsContent() {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoadingPlaylists) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Text(
          _errorMessage!,
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 18),
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
                style: TextStyle(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '',
              onSelected: (value) {
                if (value == 'youtube') _showCreatePlaylistDialog();
                if (value == 'phamijam') _createMixedPlaylist();
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'youtube',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.smart_display_rounded),
                    title: Text('YouTube playlist'),
                  ),
                ),
                PopupMenuItem(
                  value: 'phamijam',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.library_music_rounded),
                    title: Text('PhamiJam playlist'),
                  ),
                ),
              ],
              child: IgnorePointer(
                child: ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    foregroundColor: Colors.white,
                  ),
                  child: const Icon(Icons.add_rounded),
                ),
              ),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: _showSavePlaylistDialog,
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
              child: const Icon(Icons.bookmark_add_outlined),
            ),
            const SizedBox(width: 12),
            ElevatedButton(
              onPressed: () => _fetchUserPlaylists(forceRefresh: true),
              style: ElevatedButton.styleFrom(foregroundColor: Colors.white),
              child: const Icon(Icons.refresh_rounded),
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
          style: TextStyle(color: colorScheme.onSurface),
          decoration: InputDecoration(
            hintText: 'Search playlists...',
            hintStyle: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              fontSize: 14,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            suffixIcon: _playlistSearchQuery.isEmpty
                ? null
                : IconButton(
                    icon: Icon(
                      Icons.close_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    onPressed: () {
                      _playlistSearchController.clear();
                      setState(() {
                        _playlistSearchQuery = '';
                      });
                    },
                  ),
            filled: true,
            fillColor: colorScheme.onSurface.withValues(alpha: 0.26),
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
          child: Builder(
            builder: (context) {
              final settings = context.watch<SettingsProvider>();
              final pins = context.watch<PlaylistPinProvider>();
              final visiblePlaylists = _filteredPlaylists
                  .where(
                    (p) => !settings.isPlaylistHidden(
                      (p['playlistId'] as String?) ?? '',
                    ),
                  )
                  .toList();
              final sortedPlaylists = pins.sortByPin(visiblePlaylists);
              final saved = context.watch<SavedPlaylistsProvider>().playlists;

              final mixedQuery = _playlistSearchQuery.trim().toLowerCase();
              final mixed = mixedQuery.isEmpty
                  ? _mixedPlaylists
                  : _mixedPlaylists
                        .where(
                          (p) => ((p['title'] as String?) ?? '')
                              .toLowerCase()
                              .contains(mixedQuery),
                        )
                        .toList();
              final sortedMixed = pins.sortByPin([
                for (final p in mixed) {...p, 'pinKey': 'mixed-${p['id']}'},
              ], idKey: 'pinKey');
              final showYoutube =
                  _filter == _PlaylistFilter.all ||
                  _filter == _PlaylistFilter.youtube;
              final showMixed =
                  _filter == _PlaylistFilter.all ||
                  _filter == _PlaylistFilter.phamijam;
              final showSaved =
                  _filter == _PlaylistFilter.all ||
                  _filter == _PlaylistFilter.saved;
              final nothingToShow =
                  (!showYoutube || sortedPlaylists.isEmpty) &&
                  (!showSaved || saved.isEmpty) &&
                  (!showMixed || mixed.isEmpty);

              return CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _buildFilterChips(
                        youtube: sortedPlaylists.length,
                        phamijam: mixed.length,
                        saved: saved.length,
                      ),
                    ),
                  ),
                  if (showYoutube) ...[
                    if (sortedPlaylists.isNotEmpty)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 16, bottom: 8),
                          child: Text(
                            'YouTube playlists',
                            style: TextStyle(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w600,
                              fontSize: 16,
                            ),
                          ),
                        ),
                      ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate((context, index) {
                        final playlist = sortedPlaylists[index];
                        final title =
                            (playlist['title'] as String?) ??
                            'Unknown Playlist';
                        final description =
                            (playlist['description'] as String?) ?? '';
                        final author =
                            (playlist['author'] as String?) ?? 'Unknown Author';
                        final itemCount =
                            (playlist['itemCount'] as String?) ??
                            (playlist['count'] as String?) ??
                            '';
                        final subtitle = itemCount.isNotEmpty
                            ? '$author - $itemCount songs'
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

                        final playlistId =
                            (playlist['playlistId'] as String?) ?? '';
                        final originalThumbnailUrl = thumbnailUrl;
                        final customCover = _coverOverrides[playlistId];
                        if (customCover != null && customCover.isNotEmpty) {
                          thumbnailUrl = customCover;
                        }
                        final isPinned =
                            playlistId.isNotEmpty && pins.isPinned(playlistId);
                        final privacyStatus =
                            (playlist['privacyStatus'] as String?) ?? 'public';
                        final canShare =
                            playlistId.isNotEmpty && privacyStatus != 'private';

                        void handleTogglePin() {
                          if (playlistId.isEmpty) return;
                          pins.togglePin(playlistId);
                        }

                        void handleShare() {
                          if (!canShare) return;
                          ShareLinkService.sharePlaylist(context, playlistId);
                        }

                        void handleEdit() {
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
                            initialPrivacyStatus: privacyStatus,
                            initialThumbnailUrl: thumbnailUrl ?? '',
                            originalThumbnailUrl: originalThumbnailUrl,
                            initialCustomCoverUrl:
                                (customCover != null && customCover.isNotEmpty)
                                ? customCover
                                : null,
                          );
                        }

                        void handleDelete() {
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
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: ContextMenuRegion<String>(
                            contextMenu: ContextMenu(
                              borderRadius: BorderRadius.circular(12),
                              entries: [
                                MenuItem<String>(
                                  value: 'toggle_pin',
                                  icon: Icon(
                                    isPinned
                                        ? Icons.push_pin_outlined
                                        : Icons.push_pin_rounded,
                                  ),
                                  label: Text(
                                    isPinned
                                        ? 'Unpin playlist'
                                        : 'Pin playlist',
                                  ),
                                ),
                                if (canShare)
                                  MenuItem<String>(
                                    value: 'share',
                                    icon: const Icon(Icons.share_rounded),
                                    label: const Text('Share playlist'),
                                  ),
                                MenuItem<String>(
                                  value: 'edit',
                                  icon: const Icon(Icons.edit_rounded),
                                  label: const Text('Edit playlist'),
                                ),
                                MenuItem<String>(
                                  value: 'delete',
                                  icon: const Icon(Icons.delete_rounded),
                                  label: const Text('Delete playlist'),
                                ),
                              ],
                            ),
                            onItemSelected: (value) {
                              if (value == 'toggle_pin') {
                                handleTogglePin();
                              } else if (value == 'share') {
                                handleShare();
                              } else if (value == 'edit') {
                                handleEdit();
                              } else if (value == 'delete') {
                                handleDelete();
                              }
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surface,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Material(
                                type: MaterialType.transparency,
                                child: ListTile(
                                  leading:
                                      thumbnailUrl != null &&
                                          thumbnailUrl.isNotEmpty
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          child: Image.network(
                                            thumbnailUrl,
                                            width: 56,
                                            height: 56,
                                            cacheWidth: 112,
                                            cacheHeight: 112,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Icon(
                                                  Icons.playlist_play_rounded,
                                                  color: colorScheme.onSurface,
                                                ),
                                          ),
                                        )
                                      : Icon(
                                          Icons.playlist_play_rounded,
                                          color: colorScheme.onSurface,
                                        ),
                                  title: Text(
                                    title,
                                    style: TextStyle(
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  subtitle: Text(
                                    subtitle,
                                    style: TextStyle(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        decoration: BoxDecoration(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.38),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            isPinned
                                                ? Icons.push_pin_rounded
                                                : Icons.push_pin_outlined,
                                            color: colorScheme.onSurface,
                                          ),
                                          onPressed: playlistId.isEmpty
                                              ? null
                                              : handleTogglePin,
                                        ),
                                      ),
                                      if (canShare) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          decoration: BoxDecoration(
                                            color: colorScheme.onSurface
                                                .withValues(alpha: 0.38),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: IconButton(
                                            icon: Icon(
                                              Icons.share_rounded,
                                              color: colorScheme.onSurface,
                                            ),
                                            onPressed: handleShare,
                                          ),
                                        ),
                                      ],
                                      const SizedBox(width: 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: colorScheme.onSurface
                                              .withValues(alpha: 0.38),
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.edit_rounded,
                                            color: colorScheme.onSurface,
                                          ),
                                          onPressed: handleEdit,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        decoration: BoxDecoration(
                                          color: colorScheme.error,
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        child: IconButton(
                                          icon: Icon(
                                            Icons.delete_rounded,
                                            color: colorScheme.onError,
                                          ),
                                          onPressed: handleDelete,
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
                          ),
                        );
                      }, childCount: sortedPlaylists.length),
                    ),
                  ],
                  if (showMixed) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'PhamiJam playlists',
                                style: TextStyle(
                                  color: colorScheme.onSurface,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _buildMixedPlaylistTile(sortedMixed[index], pins),
                        childCount: sortedMixed.length,
                      ),
                    ),
                  ],
                  if (nothingToShow)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Center(
                          child: Text(
                            'No playlists found',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (showSaved && saved.isNotEmpty) ...[
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 16, bottom: 8),
                        child: Text(
                          'Saved Playlists',
                          style: TextStyle(
                            color: colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) =>
                            _buildSavedPlaylistTile(saved[index]),
                        childCount: saved.length,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSavedPlaylistTile(Map<String, dynamic> playlist) {
    final colorScheme = Theme.of(context).colorScheme;
    final playlistId = (playlist['playlistId'] as String?) ?? '';
    final title = (playlist['title'] as String?) ?? 'Unknown Playlist';
    final itemCount = (playlist['itemCount'] as int?) ?? 0;
    final thumbnailUrl = (playlist['thumbnailUrl'] as String?) ?? '';
    final privacyStatus = (playlist['privacyStatus'] as String?) ?? 'public';
    final canShare = playlistId.isNotEmpty && privacyStatus != 'private';

    void handleUnsave() {
      if (playlistId.isEmpty) return;
      context.read<SavedPlaylistsProvider>().unsave(playlistId);
    }

    void handleShare() {
      if (!canShare) return;
      ShareLinkService.sharePlaylist(context, playlistId);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: ContextMenuRegion<String>(
        contextMenu: ContextMenu(
          borderRadius: BorderRadius.circular(12),
          entries: [
            if (canShare)
              MenuItem<String>(
                value: 'share',
                icon: const Icon(Icons.share_rounded),
                label: const Text('Share playlist'),
              ),
            MenuItem<String>(
              value: 'unsave',
              icon: const Icon(Icons.bookmark_remove_outlined),
              label: const Text('Remove from saved'),
            ),
          ],
        ),
        onItemSelected: (value) {
          if (value == 'share') {
            handleShare();
          } else if (value == 'unsave') {
            handleUnsave();
          }
        },
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: thumbnailUrl.isEmpty
                  ? Icon(
                      Icons.playlist_play_rounded,
                      color: colorScheme.onSurface,
                    )
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        thumbnailUrl,
                        width: 56,
                        height: 56,
                        cacheWidth: 112,
                        cacheHeight: 112,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          Icons.playlist_play_rounded,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ),
              title: Text(
                title,
                style: TextStyle(color: colorScheme.onSurface),
              ),
              subtitle: Text(
                '$itemCount videos',
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (canShare) ...[
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(alpha: 0.38),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: IconButton(
                        icon: Icon(
                          Icons.share_rounded,
                          color: colorScheme.onSurface,
                        ),
                        onPressed: handleShare,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.38),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: IconButton(
                      icon: Icon(
                        Icons.bookmark_remove_outlined,
                        color: colorScheme.onSurface,
                      ),
                      onPressed: playlistId.isEmpty ? null : handleUnsave,
                    ),
                  ),
                ],
              ),
              onTap: playlistId.isEmpty
                  ? null
                  : () => widget.onTabSelected?.call(
                      'playlist_inspect',
                      extra: {
                        'playlistId': playlistId,
                        'playlistTitle': title,
                        'thumbnailUrl': thumbnailUrl,
                        'isOwnedByUser': false,
                      },
                    ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _playlistSearchController.dispose();
    _playlistCoverSubscription?.cancel();
    _mixedSubscription?.cancel();
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
