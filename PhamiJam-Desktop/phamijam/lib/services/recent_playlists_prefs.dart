import 'package:phamijam/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentPlaylistsPrefs {
  RecentPlaylistsPrefs._();

  static const String _key = 'phamijam.recent_playlists';
  static const int _max = 5;

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (error) {
      Log.w('library', 'reading recent playlists failed', error);
      return const [];
    }
  }

  static Future<void> record(Iterable<String> ids) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_key) ?? <String>[];
      final updated = <String>[
        ...ids,
        ...current.where((id) => !ids.contains(id)),
      ].take(_max).toList();
      await prefs.setStringList(_key, updated);
    } catch (error) {
      Log.w('library', 'saving recent playlists failed', error);
    }
  }
}
