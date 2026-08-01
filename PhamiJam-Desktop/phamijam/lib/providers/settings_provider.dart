import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _suggestRemovingSkippedSongsKey =
    'phamijam.suggest_removing_skipped_songs';
const String _searchEngineKey = 'phamijam.search_engine';

enum SearchEngine {
  youtubeMusic,
  youtube;

  static SearchEngine fromName(String? name) => SearchEngine.values.firstWhere(
    (e) => e.name == name,
    orElse: () => youtubeMusic,
  );
}

class SettingsProvider extends ChangeNotifier {
  bool _suggestRemovingSkippedSongs = true;
  SearchEngine _searchEngine = SearchEngine.youtubeMusic;

  bool get suggestRemovingSkippedSongs => _suggestRemovingSkippedSongs;
  SearchEngine get searchEngine => _searchEngine;

  SettingsProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_suggestRemovingSkippedSongsKey);
    if (saved != null && saved != _suggestRemovingSkippedSongs) {
      _suggestRemovingSkippedSongs = saved;
    }
    _searchEngine = SearchEngine.fromName(prefs.getString(_searchEngineKey));
    notifyListeners();
  }

  Future<void> setSuggestRemovingSkippedSongs(bool value) async {
    if (value == _suggestRemovingSkippedSongs) return;
    _suggestRemovingSkippedSongs = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suggestRemovingSkippedSongsKey, value);
  }

  Future<void> setSearchEngine(SearchEngine value) async {
    if (value == _searchEngine) return;
    _searchEngine = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_searchEngineKey, value.name);
  }
}
