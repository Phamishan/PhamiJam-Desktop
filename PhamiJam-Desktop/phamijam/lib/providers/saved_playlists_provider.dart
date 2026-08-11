import 'package:flutter/foundation.dart';
import 'package:phamijam/services/saved_playlists_service.dart';
import 'package:phamijam/services/youtube_playlist_service.dart';

String? extractPlaylistId(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final uri = Uri.tryParse(trimmed);
  final fromQuery = uri?.queryParameters['list'];
  if (fromQuery != null && fromQuery.isNotEmpty) return fromQuery;

  if (RegExp(r'^[A-Za-z0-9_-]{10,}$').hasMatch(trimmed)) return trimmed;
  return null;
}

class SavedPlaylistsProvider extends ChangeNotifier {
  List<String> _playlistIds = [];
  final Map<String, Map<String, dynamic>> _playlists = {};
  bool isLoading = false;
  bool hasLoadedOnce = false;

  List<Map<String, dynamic>> get playlists => _playlistIds
      .map((id) => _playlists[id])
      .whereType<Map<String, dynamic>>()
      .toList();

  bool isSaved(String playlistId) => _playlistIds.contains(playlistId);

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();
    try {
      _playlistIds = await SavedPlaylistsService.fetchAll();
      await Future.wait(_playlistIds.map(_fetchMetadata));
    } catch (error) {
      debugPrint('SavedPlaylistsProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> _fetchMetadata(String playlistId) async {
    try {
      final playlist = await YoutubePlaylistService.fetchPlaylistMetadata(
        playlistId,
      );
      if (playlist != null) {
        _playlists[playlistId] = playlist;
        notifyListeners();
      }
    } catch (error) {
      debugPrint('SavedPlaylistsProvider: metadata fetch failed: $error');
    }
  }

  Future<String?> saveFromInput(String input) async {
    final playlistId = extractPlaylistId(input);
    if (playlistId == null) {
      return "That doesn't look like a playlist link.";
    }
    if (_playlistIds.contains(playlistId)) {
      return "You've already saved this playlist.";
    }

    Map<String, dynamic>? playlist;
    try {
      playlist = await YoutubePlaylistService.fetchPlaylistMetadata(playlistId);
    } catch (_) {
      return "Couldn't load that playlist. Check the link and try again.";
    }
    if (playlist == null) {
      return "Couldn't find that playlist - it may be private or deleted.";
    }

    await SavedPlaylistsService.save(playlistId);
    _playlistIds = [playlistId, ..._playlistIds];
    _playlists[playlistId] = playlist;
    notifyListeners();
    return null;
  }

  Future<void> unsave(String playlistId) async {
    if (!_playlistIds.contains(playlistId)) return;
    final previousIds = _playlistIds;
    final previousPlaylist = _playlists[playlistId];
    _playlistIds = _playlistIds.where((id) => id != playlistId).toList();
    _playlists.remove(playlistId);
    notifyListeners();

    try {
      await SavedPlaylistsService.unsave(playlistId);
    } catch (error) {
      _playlistIds = previousIds;
      if (previousPlaylist != null) {
        _playlists[playlistId] = previousPlaylist;
      }
      notifyListeners();
      rethrow;
    }
  }
}
