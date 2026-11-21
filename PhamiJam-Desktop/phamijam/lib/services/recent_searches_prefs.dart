import 'package:phamijam/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class RecentSearchesPrefs {
  RecentSearchesPrefs._();

  static const String _key = 'phamijam.recent_searches';
  static const int _max = 8;

  static Future<List<String>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getStringList(_key) ?? const [];
    } catch (error) {
      Log.w('search', 'reading recent searches failed', error);
      return const [];
    }
  }

  static Future<List<String>> record(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return load();
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = prefs.getStringList(_key) ?? <String>[];
      final updated = <String>[
        trimmed,
        ...current.where((q) => q.toLowerCase() != trimmed.toLowerCase()),
      ].take(_max).toList();
      await prefs.setStringList(_key, updated);
      return updated;
    } catch (error) {
      Log.w('search', 'saving recent search failed', error);
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key);
    } catch (error) {
      Log.w('search', 'clearing recent searches failed', error);
    }
  }
}
