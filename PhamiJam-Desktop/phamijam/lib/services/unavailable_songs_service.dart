import 'package:flutter/foundation.dart';
import 'package:phamijam/services/log_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class UnavailableSongs extends ChangeNotifier {
  UnavailableSongs._();
  static final UnavailableSongs instance = UnavailableSongs._();

  static const String _key = 'phamijam.unavailable_songs';
  static const int _max = 2000;

  final Set<String> _ids = {};
  Future<void>? _loading;

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _ids.addAll(prefs.getStringList(_key) ?? const []);
      if (_ids.isNotEmpty) notifyListeners();
    } catch (error) {
      Log.w('library', 'reading unavailable songs failed', error);
    }
  }

  bool contains(String? videoId) => videoId != null && _ids.contains(videoId);

  int countIn(Iterable<String?> videoIds) =>
      videoIds.where((id) => id != null && _ids.contains(id)).length;

  bool _eligible(String id) => id.isNotEmpty && !id.startsWith('drive:');

  void add(String videoId) => addAll([videoId]);

  void addAll(Iterable<String> videoIds) {
    var changed = false;
    for (final id in videoIds) {
      if (_eligible(id) && _ids.add(id)) changed = true;
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  void removeAll(Iterable<String> videoIds) {
    var changed = false;
    for (final id in videoIds) {
      if (_ids.remove(id)) changed = true;
    }
    if (changed) {
      _persist();
      notifyListeners();
    }
  }

  Future<void> _persist() async {
    try {
      await ensureLoaded();
      while (_ids.length > _max) {
        _ids.remove(_ids.first);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_key, _ids.toList());
    } catch (error) {
      Log.w('library', 'saving unavailable songs failed', error);
    }
  }
}
