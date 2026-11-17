import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';

class SongArtistsService {
  SongArtistsService._();

  static const String _prefsKey = 'phamijam.song_artists.v1';
  static const int _maxStored = 3000;
  static const int _maxConcurrent = 3;

  static final LinkedHashMap<String, List<String>> _cache = LinkedHashMap();
  static final Map<String, Future<List<String>>> _inFlight = {};
  static final Queue<Completer<void>> _waiting = Queue();
  static int _running = 0;
  static Future<void>? _loaded;
  static Timer? _saveTimer;
  static YTMusic? _ytmusic;

  static bool isLookupable(String? videoId) =>
      videoId != null &&
      videoId.isNotEmpty &&
      !videoId.startsWith('drive:') &&
      !videoId.startsWith('local:');

  static List<String>? cached(String videoId) => _cache[videoId];

  static Future<void> _ensureLoaded() => _loaded ??= _load();

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      decoded.forEach((key, value) {
        if (key is String && value is List) {
          _cache.putIfAbsent(key, () => value.whereType<String>().toList());
        }
      });
    } catch (error) {
      debugPrint('SongArtistsService: failed to load cache: $error');
    }
  }

  static void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 3), () async {
      try {
        while (_cache.length > _maxStored) {
          _cache.remove(_cache.keys.first);
        }
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsKey, jsonEncode(_cache));
      } catch (error) {
        debugPrint('SongArtistsService: failed to save cache: $error');
      }
    });
  }

  static Future<List<String>> artistsFor(String videoId) async {
    await _ensureLoaded();
    final hit = _cache[videoId];
    if (hit != null) return hit;
    return _inFlight[videoId] ??= _fetch(
      videoId,
    ).whenComplete(() => _inFlight.remove(videoId));
  }

  static Future<void> _acquire() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final waiter = Completer<void>();
    _waiting.add(waiter);
    await waiter.future;
  }

  static void _release() {
    if (_waiting.isNotEmpty) {
      _waiting.removeFirst().complete();
    } else {
      _running--;
    }
  }

  static Future<List<String>> _fetch(String videoId) async {
    await _acquire();
    try {
      final ytmusic = _ytmusic ??= await YTMusic.create();
      final result = await ytmusic
          .getWatchPlaylist(videoId: videoId, limit: 1)
          .timeout(const Duration(seconds: 12));
      final tracks = result['tracks'];
      final names = <String>[];
      if (tracks is List && tracks.isNotEmpty) {
        Map? track;
        for (final t in tracks) {
          if (t is Map && t['videoId'] == videoId) {
            track = t;
            break;
          }
        }
        track ??= tracks.first is Map ? tracks.first as Map : null;
        final artists = track?['artists'];
        if (artists is List) {
          for (final a in artists) {
            final name = a is Map ? a['name'] : null;
            if (name is String && name.trim().isNotEmpty) {
              names.add(name.trim());
            }
          }
        }
      }
      _cache[videoId] = names;
      _scheduleSave();
      return names;
    } catch (error) {
      debugPrint('SongArtistsService: lookup failed for $videoId: $error');
      return const [];
    } finally {
      _release();
    }
  }
}
