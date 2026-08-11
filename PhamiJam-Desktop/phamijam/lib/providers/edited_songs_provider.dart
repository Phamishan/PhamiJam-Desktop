import 'package:flutter/foundation.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/services/edited_songs_service.dart';

class EditedSongsProvider extends ChangeNotifier {
  Map<String, EditedSongTrim> _trims = {};
  bool isLoading = false;
  bool hasLoadedOnce = false;

  static String _key(String videoId, [String? playlistId]) =>
      playlistId == null ? videoId : '$videoId::$playlistId';

  List<EditedSongTrim> get all => _trims.values.toList();

  EditedSongTrim? trimFor(String videoId, [String? playlistId]) {
    if (playlistId != null) {
      final scoped = _trims[_key(videoId, playlistId)];
      if (scoped != null) return scoped;
    }
    return _trims[videoId];
  }

  bool hasTrim(String videoId, [String? playlistId]) =>
      trimFor(videoId, playlistId) != null;

  EditedSongTrim? exactTrimFor(String videoId, [String? playlistId]) =>
      _trims[_key(videoId, playlistId)];

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    try {
      final list = await EditedSongsService.fetchAll();
      _trims = {
        for (final trim in list) _key(trim.videoId, trim.playlistId): trim,
      };
    } catch (error) {
      debugPrint('EditedSongsProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> saveTrim(EditedSongTrim trim) async {
    final key = _key(trim.videoId, trim.playlistId);
    final previous = _trims[key];
    _trims = {..._trims, key: trim};
    notifyListeners();

    try {
      await EditedSongsService.setTrim(trim);
    } catch (error) {
      _trims = {..._trims};
      if (previous != null) {
        _trims[key] = previous;
      } else {
        _trims.remove(key);
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeTrim(String videoId, [String? playlistId]) async {
    final key = _key(videoId, playlistId);
    final previous = _trims[key];
    if (previous == null) return;
    _trims = {..._trims}..remove(key);
    notifyListeners();

    try {
      await EditedSongsService.removeTrim(videoId, playlistId);
    } catch (error) {
      _trims = {..._trims, key: previous};
      notifyListeners();
      rethrow;
    }
  }
}
