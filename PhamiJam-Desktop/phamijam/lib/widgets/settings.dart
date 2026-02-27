import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phamijam/components/playback_model.dart';
import 'package:phamijam/services/google_auth_service.dart';
import 'package:provider/provider.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final String _settingsTitle = 'Settings';
  bool _isPreloading = false;
  bool _isLoadingPlaylists = false;
  bool _isDone = false;
  String? _errorMessage;
  String _statusText = 'Idle';
  int _totalPlaylists = 0;
  int _processedPlaylists = 0;
  int _totalSongs = 0;
  int _processedSongs = 0;
  int _failedSongs = 0;
  List<Map<String, dynamic>> _availablePlaylists = [];
  final Set<String> _selectedPlaylistIds = <String>{};

  double get _progress {
    if (_totalSongs <= 0) return 0;
    return (_processedSongs / _totalSongs).clamp(0, 1).toDouble();
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

  Future<List<Map<String, dynamic>>> _fetchMinePlaylists() async {
    final response = await _youtubeGetWithAutoRefresh(
      Uri.parse(
        'https://www.googleapis.com/youtube/v3/playlists?part=id,snippet,contentDetails&mine=true&maxResults=50',
      ),
    );

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to load playlists: ${response.statusCode}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final items = (payload['items'] as List?) ?? const [];

    return items
        .whereType<Map>()
        .map((item) {
          final snippet = Map<String, dynamic>.from(
            item['snippet'] as Map? ?? const <String, dynamic>{},
          );
          final contentDetails = Map<String, dynamic>.from(
            item['contentDetails'] as Map? ?? const <String, dynamic>{},
          );
          final id = (item['id'] as String?) ?? '';
          return <String, dynamic>{
            'id': id,
            'title': (snippet['title'] as String?) ?? 'Unknown playlist',
            'count': (contentDetails['itemCount'] as int?) ?? 0,
          };
        })
        .where(
          (playlist) => ((playlist['id'] as String?) ?? '').trim().isNotEmpty,
        )
        .toList();
  }

  Future<void> _loadPlaylistsForSelection() async {
    if (_isLoadingPlaylists || _isPreloading) return;

    if (!mounted) return;
    setState(() {
      _isLoadingPlaylists = true;
      _errorMessage = null;
      _statusText = 'Loading playlists...';
    });

    try {
      final playlists = await _fetchMinePlaylists();
      if (!mounted) return;

      final selectedIds = _selectedPlaylistIds
          .where(
            (id) =>
                playlists.any((playlist) => (playlist['id'] as String) == id),
          )
          .toSet();

      setState(() {
        _availablePlaylists = playlists;
        _selectedPlaylistIds
          ..clear()
          ..addAll(selectedIds);
        _statusText =
            'Loaded ${_availablePlaylists.length} playlists for selection.';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _statusText = 'Failed to load playlists.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPlaylists = false;
        });
      }
    }
  }

  Future<List<String>> _fetchVideoIdsForPlaylist(String playlistId) async {
    final allVideoIds = <String>[];
    String? pageToken;

    do {
      final tokenPart = pageToken == null || pageToken.isEmpty
          ? ''
          : '&pageToken=$pageToken';
      final response = await _youtubeGetWithAutoRefresh(
        Uri.parse(
          'https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails&playlistId=$playlistId&maxResults=50$tokenPart',
        ),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          'Failed to load playlist items for $playlistId: ${response.statusCode}',
        );
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final items = (payload['items'] as List?) ?? const [];

      for (final raw in items) {
        if (raw is! Map) continue;
        final contentDetails = raw['contentDetails'] as Map?;
        final videoId = contentDetails?['videoId'] as String?;
        if (videoId != null && videoId.isNotEmpty) {
          allVideoIds.add(videoId);
        }
      }

      pageToken = payload['nextPageToken'] as String?;
    } while (pageToken != null && pageToken.isNotEmpty);

    return allVideoIds;
  }

  Future<void> _preloadSongsFromSelectedPlaylists() async {
    if (_isPreloading) return;
    if (_selectedPlaylistIds.isEmpty) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Select at least one playlist to preload.';
        _statusText = 'No playlists selected.';
      });
      return;
    }

    if (!mounted) return;
    setState(() {
      _isPreloading = true;
      _isDone = false;
      _errorMessage = null;
      _statusText = 'Loading playlists...';
      _totalPlaylists = 0;
      _processedPlaylists = 0;
      _totalSongs = 0;
      _processedSongs = 0;
      _failedSongs = 0;
    });

    final playback = context.read<PlaybackModel>();

    try {
      final playlistIds = _selectedPlaylistIds.toList();
      if (!mounted) return;

      setState(() {
        _totalPlaylists = playlistIds.length;
        _statusText = 'Loading songs from playlists...';
      });

      final allVideoIds = <String>[];

      for (final playlistId in playlistIds) {
        final videoIds = await _fetchVideoIdsForPlaylist(playlistId);
        allVideoIds.addAll(videoIds);

        if (!mounted) return;
        setState(() {
          _processedPlaylists += 1;
          _statusText =
              'Loaded $_processedPlaylists / $_totalPlaylists playlists...';
        });
      }

      final uniqueVideoIds = allVideoIds.toSet().toList();
      if (!mounted) return;
      setState(() {
        _totalSongs = uniqueVideoIds.length;
        _statusText = 'Preloading songs...';
      });

      for (var index = 0; index < uniqueVideoIds.length; index++) {
        final videoId = uniqueVideoIds[index];
        try {
          await playback.prefetchYouTubeVideoById(videoId);
        } catch (_) {
          _failedSongs += 1;
        }

        if (!mounted) return;
        setState(() {
          _processedSongs = index + 1;
        });
      }

      if (!mounted) return;
      setState(() {
        _isDone = true;
        _statusText =
            'Preloading complete: $_processedSongs songs cached (${_failedSongs} failed).';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.toString();
        _statusText = 'Preloading failed.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPreloading = false;
        });
      }
    }
  }

  Widget _buildPreloadCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFdba43a),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YouTube Preload Songs',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Preload only selected playlist songs into cache.',
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isLoadingPlaylists || _isPreloading
                    ? null
                    : _loadPlaylistsForSelection,
                icon: const Icon(Icons.playlist_add_check),
                label: Text(
                  _isLoadingPlaylists ? 'Loading...' : 'Load Playlists',
                ),
              ),
              const SizedBox(width: 12),
              if (_availablePlaylists.isNotEmpty)
                TextButton(
                  onPressed: _isPreloading
                      ? null
                      : () {
                          setState(() {
                            _selectedPlaylistIds
                              ..clear()
                              ..addAll(
                                _availablePlaylists.map(
                                  (playlist) => playlist['id'] as String,
                                ),
                              );
                          });
                        },
                  child: const Text('Select all'),
                ),
              if (_availablePlaylists.isNotEmpty)
                TextButton(
                  onPressed: _isPreloading
                      ? null
                      : () {
                          setState(() {
                            _selectedPlaylistIds.clear();
                          });
                        },
                  child: const Text('Clear'),
                ),
            ],
          ),
          if (_availablePlaylists.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              height: 180,
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                itemCount: _availablePlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = _availablePlaylists[index];
                  final playlistId = playlist['id'] as String;
                  final title =
                      (playlist['title'] as String?) ?? 'Unknown playlist';
                  final count = (playlist['count'] as int?) ?? 0;
                  final isSelected = _selectedPlaylistIds.contains(playlistId);

                  return CheckboxListTile(
                    value: isSelected,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: Colors.white,
                    checkColor: const Color(0xFFdba43a),
                    title: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '$count songs',
                      style: const TextStyle(color: Colors.white70),
                    ),
                    onChanged: _isPreloading
                        ? null
                        : (checked) {
                            setState(() {
                              if (checked == true) {
                                _selectedPlaylistIds.add(playlistId);
                              } else {
                                _selectedPlaylistIds.remove(playlistId);
                              }
                            });
                          },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Selected playlists: ${_selectedPlaylistIds.length}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _isPreloading
                    ? null
                    : _preloadSongsFromSelectedPlaylists,
                icon: const Icon(Icons.download),
                label: Text(_isPreloading ? 'Preloading...' : 'Start Preload'),
              ),
              const SizedBox(width: 12),
              if (_isDone)
                const Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.greenAccent),
                    SizedBox(width: 6),
                    Text(
                      'Done',
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: _isPreloading || _isDone ? _progress : 0,
            minHeight: 8,
            backgroundColor: Colors.white24,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
          const SizedBox(height: 8),
          Text(_statusText, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 4),
          Text(
            'Playlists: $_processedPlaylists / $_totalPlaylists  •  Songs: $_processedSongs / $_totalSongs  •  Failed: $_failedSongs',
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                _settingsTitle,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _buildPreloadCard(),
        const SizedBox(height: 10),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(child: _buildSettingsContent()),
    );
  }
}
