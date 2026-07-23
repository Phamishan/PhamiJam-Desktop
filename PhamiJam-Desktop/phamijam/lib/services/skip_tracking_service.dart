import 'package:shared_preferences/shared_preferences.dart';

class SkipTrackingService {
  const SkipTrackingService._();

  static const int skipThreshold = 3;
  static const double consideredSkippedBeforeFraction = 0.5;

  static String _key(String playlistId, String videoId) =>
      'phamijam.skip_count.$playlistId.$videoId';

  static Future<int> recordSkip(String playlistId, String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _key(playlistId, videoId);
    final count = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, count);
    return count;
  }

  static Future<void> clearForTrack(String playlistId, String videoId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(playlistId, videoId));
  }

  static Future<void> recordCompleted(String playlistId, String videoId) =>
      clearForTrack(playlistId, videoId);
}
