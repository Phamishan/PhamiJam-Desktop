import 'package:flutter/foundation.dart';
import 'package:phamijam/services/playlist_pin_service.dart';

class PlaylistPinProvider extends ChangeNotifier {
  List<String> _pinnedOrder = [];
  bool isLoading = false;
  bool hasLoadedOnce = false;

  bool isPinned(String playlistId) => _pinnedOrder.contains(playlistId);

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    try {
      _pinnedOrder = await PlaylistPinService.fetchAll();
    } catch (error) {
      debugPrint('PlaylistPinProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> sortByPin(
    List<Map<String, dynamic>> playlists, {
    String idKey = 'playlistId',
  }) {
    final pinnedIndex = {
      for (var i = 0; i < _pinnedOrder.length; i++) _pinnedOrder[i]: i,
    };
    final pinned = <Map<String, dynamic>>[];
    final rest = <Map<String, dynamic>>[];
    for (final playlist in playlists) {
      final id = playlist[idKey] as String?;
      if (id != null && pinnedIndex.containsKey(id)) {
        pinned.add(playlist);
      } else {
        rest.add(playlist);
      }
    }
    pinned.sort((a, b) {
      final aIndex = pinnedIndex[a[idKey] as String?] ?? 0;
      final bIndex = pinnedIndex[b[idKey] as String?] ?? 0;
      return aIndex.compareTo(bIndex);
    });
    return [...pinned, ...rest];
  }

  Future<void> togglePin(String playlistId) async {
    final wasPinned = _pinnedOrder.contains(playlistId);
    _pinnedOrder = wasPinned
        ? _pinnedOrder.where((id) => id != playlistId).toList()
        : [playlistId, ..._pinnedOrder];
    notifyListeners();

    try {
      if (wasPinned) {
        await PlaylistPinService.unpin(playlistId);
      } else {
        await PlaylistPinService.pin(playlistId);
      }
    } catch (error) {
      _pinnedOrder = wasPinned
          ? [playlistId, ..._pinnedOrder]
          : _pinnedOrder.where((id) => id != playlistId).toList();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> clearPin(String playlistId) async {
    if (!_pinnedOrder.remove(playlistId)) return;
    notifyListeners();
    try {
      await PlaylistPinService.unpin(playlistId);
    } catch (error) {
      debugPrint('PlaylistPinProvider: clearPin failed: $error');
    }
  }
}
