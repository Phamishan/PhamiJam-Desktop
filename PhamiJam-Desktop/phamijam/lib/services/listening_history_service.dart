import 'dart:convert';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ListeningHistoryService {
  ListeningHistoryService._();

  static const String _pendingKey = 'phamijam.play_history.pending';
  static const int _maxPending = 2000;
  static const int _minListenMs = 30000;
  static const Duration _syncTimeout = Duration(seconds: 8);

  static CollectionReference<Map<String, dynamic>>? get _remotePlays {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('plays');
  }

  static Future<List<PlayEvent>> _loadPending() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(PlayEvent.fromJson)
            .whereType<PlayEvent>()
            .toList();
      }
    } catch (error) {
      debugPrint('ListeningHistoryService: failed to parse buffer: $error');
    }
    return [];
  }

  static Future<void> _savePending(List<PlayEvent> events) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode(events.map((e) => e.toJson()).toList()),
    );
  }

  static Future<void> logPlay({
    required String trackId,
    required String title,
    required String artist,
    required String thumbnailUrl,
    required Duration trackDuration,
    required DateTime startedAt,
    required Duration listened,
  }) async {
    if (trackId.isEmpty) return;

    var listenedMs = listened.inMilliseconds;
    final durationMs = trackDuration.inMilliseconds;
    final threshold = durationMs > 0
        ? min(_minListenMs, durationMs ~/ 2)
        : _minListenMs;
    if (listenedMs < threshold) return;
    if (durationMs > 0) listenedMs = min(listenedMs, durationMs);

    final pending = List<PlayEvent>.from(await _loadPending())
      ..add(
        PlayEvent(
          videoId: trackId,
          title: title,
          artist: artist,
          thumbnailUrl: thumbnailUrl,
          startedAt: startedAt,
          listenedMs: listenedMs,
        ),
      );
    if (pending.length > _maxPending) {
      pending.removeRange(0, pending.length - _maxPending);
    }
    await _savePending(pending);
    await flushPending();
  }

  static Future<void> flushPending() async {
    final remote = _remotePlays;
    if (remote == null) return;
    final pending = await _loadPending();
    if (pending.isEmpty) return;

    final remaining = List<PlayEvent>.from(pending);
    for (final event in pending) {
      try {
        await remote.doc(event.docId).set(event.toJson()).timeout(_syncTimeout);
        remaining.remove(event);
      } catch (error) {
        debugPrint('ListeningHistoryService: sync paused: $error');
        break;
      }
    }
    if (remaining.length != pending.length) {
      await _savePending(remaining);
    }
  }

  static Future<List<PlayEvent>> eventsSince(DateTime since) async {
    await flushPending();
    final sinceMs = since.millisecondsSinceEpoch;
    final events = <PlayEvent>[];

    final remote = _remotePlays;
    if (remote != null) {
      try {
        final snapshot = await remote
            .where('s', isGreaterThanOrEqualTo: sinceMs)
            .get();
        for (final doc in snapshot.docs) {
          final event = PlayEvent.fromJson(doc.data());
          if (event != null) events.add(event);
        }
      } catch (error) {
        debugPrint('ListeningHistoryService: remote fetch failed: $error');
      }
    }

    final seen = events.map((e) => e.docId).toSet();
    for (final event in await _loadPending()) {
      if (event.startedAt.millisecondsSinceEpoch >= sinceMs &&
          seen.add(event.docId)) {
        events.add(event);
      }
    }
    events.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return events;
  }
}
