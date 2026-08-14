import 'package:shared_preferences/shared_preferences.dart';

class DriveDurationCacheService {
  DriveDurationCacheService._();

  static const String _keyPrefix = 'phamijam.drive_duration.';

  static Future<Duration?> getDuration(String fileId) async {
    final prefs = await SharedPreferences.getInstance();
    final ms = prefs.getInt('$_keyPrefix$fileId');
    if (ms == null || ms <= 0) return null;
    return Duration(milliseconds: ms);
  }

  static Future<void> setDuration(String fileId, Duration duration) async {
    if (duration <= Duration.zero) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('$_keyPrefix$fileId', duration.inMilliseconds);
  }
}
