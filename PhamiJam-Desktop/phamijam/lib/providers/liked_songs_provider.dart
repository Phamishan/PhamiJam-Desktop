import 'package:flutter/foundation.dart';
import 'package:phamijam/services/liked_songs_service.dart';

class LikedSongsProvider extends ChangeNotifier {
  bool isLoading = false;
  bool hasLoadedOnce = false;
  List<Map<String, dynamic>> songs = [];

  final Set<String> _likedVideoIds = {};

  bool isLiked(String videoId) => _likedVideoIds.contains(videoId);

  Future<void> refresh() async {
    isLoading = true;
    notifyListeners();

    try {
      final liked = await LikedSongsService.fetchAll();
      songs = liked;
      _likedVideoIds
        ..clear()
        ..addAll(liked.map((s) => s['videoId'] as String));
    } catch (error) {
      debugPrint('LikedSongsProvider: refresh failed: $error');
    } finally {
      isLoading = false;
      hasLoadedOnce = true;
      notifyListeners();
    }
  }

  Future<void> toggleLike(Map<String, dynamic> song) async {
    final videoId = song['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return;
    final alreadyLiked = _likedVideoIds.contains(videoId);

    _applyLikeState(videoId: videoId, song: song, liked: !alreadyLiked);
    notifyListeners();

    try {
      if (alreadyLiked) {
        await LikedSongsService.unlike(videoId);
      } else {
        await LikedSongsService.like(song);
      }
    } catch (error) {
      _applyLikeState(videoId: videoId, song: song, liked: alreadyLiked);
      notifyListeners();
      rethrow;
    }
  }

  void _applyLikeState({
    required String videoId,
    required Map<String, dynamic> song,
    required bool liked,
  }) {
    if (liked) {
      _likedVideoIds.add(videoId);
      if (songs.any((s) => s['videoId'] == videoId)) return;
      songs = [Map<String, dynamic>.from(song), ...songs];
    } else {
      _likedVideoIds.remove(videoId);
      songs = songs.where((s) => s['videoId'] != videoId).toList();
    }
  }
}
