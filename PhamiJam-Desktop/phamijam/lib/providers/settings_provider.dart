import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _suggestRemovingSkippedSongsKey =
    'phamijam.suggest_removing_skipped_songs';

class SettingsProvider extends ChangeNotifier {
  bool _suggestRemovingSkippedSongs = true;

  bool get suggestRemovingSkippedSongs => _suggestRemovingSkippedSongs;

  SettingsProvider() {
    _restore();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_suggestRemovingSkippedSongsKey);
    if (saved != null && saved != _suggestRemovingSkippedSongs) {
      _suggestRemovingSkippedSongs = saved;
      notifyListeners();
    }
  }

  Future<void> setSuggestRemovingSkippedSongs(bool value) async {
    if (value == _suggestRemovingSkippedSongs) return;
    _suggestRemovingSkippedSongs = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_suggestRemovingSkippedSongsKey, value);
  }
}
