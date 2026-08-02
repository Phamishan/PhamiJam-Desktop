import 'package:flutter/foundation.dart';
import 'package:phamijam/models/edited_song_trim.dart';
import 'package:phamijam/services/edited_songs_service.dart';

class EditedSongsProvider extends ChangeNotifier {
  Map<String, EditedSongTrim> _trims = {};
  bool isLoading = false;
  bool hasLoadedOnce = false;

  List<EditedSongTrim> get all => _trims.values.toList();
  EditedSongTrim? trimFor(String videoId) => _trims[videoId];
  bool hasTrim(String videoId) => _trims.containsKey(videoId);

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    try {
      final list = await EditedSongsService.fetchAll();
      _trims = {for (final trim in list) trim.videoId: trim};
    } catch (error) {
      debugPrint('EditedSongsProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> saveTrim(EditedSongTrim trim) async {
    final previous = _trims[trim.videoId];
    _trims = {..._trims, trim.videoId: trim};
    notifyListeners();

    try {
      await EditedSongsService.setTrim(trim);
    } catch (error) {
      _trims = {..._trims};
      if (previous != null) {
        _trims[trim.videoId] = previous;
      } else {
        _trims.remove(trim.videoId);
      }
      notifyListeners();
      rethrow;
    }
  }

  Future<void> removeTrim(String videoId) async {
    final previous = _trims[videoId];
    if (previous == null) return;
    _trims = {..._trims}..remove(videoId);
    notifyListeners();

    try {
      await EditedSongsService.removeTrim(videoId);
    } catch (error) {
      _trims = {..._trims, videoId: previous};
      notifyListeners();
      rethrow;
    }
  }
}
