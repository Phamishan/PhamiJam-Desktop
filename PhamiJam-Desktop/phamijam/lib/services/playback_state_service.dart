import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class SavedQueueState {
  const SavedQueueState({
    required this.playlistItems,
    required this.playOrder,
    required this.currentOrderIndex,
    required this.shuffle,
    required this.repeatMode,
    required this.position,
  });

  final List<Map<String, dynamic>> playlistItems;
  final List<int> playOrder;
  final int currentOrderIndex;
  final bool shuffle;
  final String repeatMode;
  final Duration position;
}

class PlaybackStateService {
  PlaybackStateService._();

  static const String _queueKey = 'phamijam.playback_queue_state';
  static const String _volumeKey = 'phamijam.playback_volume';

  static Future<void> saveVolume(double sliderValuePercent) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_volumeKey, sliderValuePercent);
  }

  static Future<double?> loadVolume() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_volumeKey);
  }

  static Map<String, dynamic> _sanitizeItemForJson(Map<String, dynamic> item) {
    final sanitized = <String, dynamic>{};
    for (final entry in item.entries) {
      final value = entry.value;
      if (value == null || value is String || value is num || value is bool) {
        sanitized[entry.key] = value;
      }
    }
    return sanitized;
  }

  static Future<void> saveQueue({
    required List<dynamic> playlistItems,
    required List<int> playOrder,
    required int currentOrderIndex,
    required bool shuffle,
    required String repeatMode,
    required Duration position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (playlistItems.isEmpty ||
        playOrder.isEmpty ||
        currentOrderIndex < 0 ||
        currentOrderIndex >= playOrder.length) {
      await prefs.remove(_queueKey);
      return;
    }

    await prefs.setString(
      _queueKey,
      jsonEncode({
        'playlistItems': playlistItems
            .whereType<Map>()
            .map(
              (item) => _sanitizeItemForJson(Map<String, dynamic>.from(item)),
            )
            .toList(),
        'playOrder': playOrder,
        'currentOrderIndex': currentOrderIndex,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
        'positionMs': position.inMilliseconds,
      }),
    );
  }

  static Future<SavedQueueState?> loadQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_queueKey);
    if (raw == null || raw.isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;

      final playlistItems = ((decoded['playlistItems'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      if (playlistItems.isEmpty) return null;

      final playOrder = ((decoded['playOrder'] as List?) ?? const [])
          .whereType<num>()
          .map((n) => n.toInt())
          .where((index) => index >= 0 && index < playlistItems.length)
          .toList();
      if (playOrder.isEmpty) return null;

      final currentOrderIndex = decoded['currentOrderIndex'] as int? ?? 0;
      if (currentOrderIndex < 0 || currentOrderIndex >= playOrder.length) {
        return null;
      }

      return SavedQueueState(
        playlistItems: playlistItems,
        playOrder: playOrder,
        currentOrderIndex: currentOrderIndex,
        shuffle: decoded['shuffle'] as bool? ?? false,
        repeatMode: decoded['repeatMode'] as String? ?? 'off',
        position: Duration(milliseconds: decoded['positionMs'] as int? ?? 0),
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearQueue() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_queueKey);
  }
}
