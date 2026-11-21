import 'package:phamijam/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaylistSortPrefs {
  PlaylistSortPrefs._();

  static String _key(String playlistId) => 'phamijam.playlist_sort.$playlistId';

  static Future<String?> load(String? playlistId) async {
    if (playlistId == null || playlistId.isEmpty) return null;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(playlistId));
    } catch (error) {
      Log.w('library', 'reading saved sort order failed', error);
      return null;
    }
  }

  static Future<void> save(
    String? playlistId,
    String sortName, {
    required bool isDefault,
  }) async {
    if (playlistId == null || playlistId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isDefault) {
        await prefs.remove(_key(playlistId));
      } else {
        await prefs.setString(_key(playlistId), sortName);
      }
    } catch (error) {
      Log.w('library', 'saving sort order failed', error);
    }
  }
}
