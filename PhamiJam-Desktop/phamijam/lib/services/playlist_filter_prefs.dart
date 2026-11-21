import 'package:phamijam/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlaylistFilterPrefs {
  PlaylistFilterPrefs._();

  static const String _key = 'phamijam.playlists_filter';

  static Future<String?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key);
    } catch (error) {
      Log.w('library', 'reading saved playlist filter failed', error);
      return null;
    }
  }

  static Future<void> save(String name, {required bool isDefault}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (isDefault) {
        await prefs.remove(_key);
      } else {
        await prefs.setString(_key, name);
      }
    } catch (error) {
      Log.w('library', 'saving playlist filter failed', error);
    }
  }
}
