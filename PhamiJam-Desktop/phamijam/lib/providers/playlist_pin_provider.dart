import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _pinnedPlaylistsPrefsKey = 'phamijam.pinned_playlists';

class PlaylistPinProvider extends ChangeNotifier {
  List<String> _pinnedOrder = [];

  PlaylistPinProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _pinnedOrder = prefs.getStringList(_pinnedPlaylistsPrefsKey) ?? [];
    notifyListeners();
  }

  bool isPinned(String playlistId) => _pinnedOrder.contains(playlistId);

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
    if (_pinnedOrder.contains(playlistId)) {
      _pinnedOrder = _pinnedOrder.where((id) => id != playlistId).toList();
    } else {
      _pinnedOrder = [playlistId, ..._pinnedOrder];
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedPlaylistsPrefsKey, _pinnedOrder);
  }

  Future<void> clearPin(String playlistId) async {
    if (!_pinnedOrder.remove(playlistId)) return;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_pinnedPlaylistsPrefsKey, _pinnedOrder);
  }
}
