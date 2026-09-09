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
  static const int _batchChunkSize = 450;
  static Future<void>? _flushInProgress;
  static const Duration _eventsCacheTtl = Duration(minutes: 2);
  static final Map<String, Future<List<PlayEvent>>> _eventsSinceInFlight = {};
  static final Map<String, _CachedEvents> _eventsSinceCache = {};
  static int? _cachedEarliestYear;
  static Future<int>? _earliestYearInFlight;

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
    String? channelId,
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
          channelId: channelId,
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

  static Future<void> flushPending() {
    return _flushInProgress ??= _flushPendingInternal().whenComplete(() {
      _flushInProgress = null;
    });
  }

  static Future<void> _flushPendingInternal() async {
    final remote = _remotePlays;
    if (remote == null) return;
    final pending = await _loadPending();
    if (pending.isEmpty) return;

    var syncedCount = 0;
    for (var offset = 0; offset < pending.length; offset += _batchChunkSize) {
      final chunk = pending.sublist(
        offset,
        min(offset + _batchChunkSize, pending.length),
      );
      try {
        final batch = FirebaseFirestore.instance.batch();
        for (final event in chunk) {
          batch.set(remote.doc(event.docId), event.toJson());
        }
        await batch.commit().timeout(_syncTimeout);
        syncedCount += chunk.length;
      } catch (error) {
        debugPrint('ListeningHistoryService: sync paused: $error');
        break;
      }
    }
    if (syncedCount > 0) {
      await _savePending(pending.sublist(syncedCount));
    }
  }

  static Future<List<PlayEvent>> eventsSince(
    DateTime since, {
    DateTime? until,
  }) {
    final key =
        '${since.millisecondsSinceEpoch}-${until?.millisecondsSinceEpoch}';
    final cached = _eventsSinceCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _eventsCacheTtl) {
      return Future.value(cached.events);
    }
    return _eventsSinceInFlight[key] ??=
        _eventsSinceInternal(since, until: until)
            .then((events) {
              _eventsSinceCache[key] = _CachedEvents(events, DateTime.now());
              return events;
            })
            .whenComplete(() => _eventsSinceInFlight.remove(key));
  }

  static Future<List<PlayEvent>> _eventsSinceInternal(
    DateTime since, {
    DateTime? until,
  }) async {
    await flushPending();
    final sinceMs = since.millisecondsSinceEpoch;
    final untilMs = until?.millisecondsSinceEpoch;
    final events = <PlayEvent>[];

    final remote = _remotePlays;
    if (remote != null) {
      try {
        Query<Map<String, dynamic>> query = remote.where(
          's',
          isGreaterThanOrEqualTo: sinceMs,
        );
        if (untilMs != null) {
          query = query.where('s', isLessThan: untilMs);
        }
        final snapshot = await query.get();
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
      final ms = event.startedAt.millisecondsSinceEpoch;
      if (ms >= sinceMs &&
          (untilMs == null || ms < untilMs) &&
          seen.add(event.docId)) {
        events.add(event);
      }
    }
    events.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return events;
  }

  static Future<List<PlayEvent>> eventsSinceForUid(
    String uid,
    DateTime since, {
    DateTime? until,
  }) async {
    final sinceMs = since.millisecondsSinceEpoch;
    final untilMs = until?.millisecondsSinceEpoch;
    final events = <PlayEvent>[];

    try {
      Query<Map<String, dynamic>> query = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('plays')
          .where('s', isGreaterThanOrEqualTo: sinceMs);
      if (untilMs != null) {
        query = query.where('s', isLessThan: untilMs);
      }
      final snapshot = await query.get();
      for (final doc in snapshot.docs) {
        final event = PlayEvent.fromJson(doc.data());
        if (event != null) events.add(event);
      }
    } catch (error) {
      debugPrint('ListeningHistoryService: remote fetch failed: $error');
    }

    events.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return events;
  }

  static Future<int> earliestEventYear() {
    final cached = _cachedEarliestYear;
    if (cached != null) return Future.value(cached);
    return _earliestYearInFlight ??= _earliestEventYearInternal()
        .then((year) {
          _cachedEarliestYear = year;
          return year;
        })
        .whenComplete(() => _earliestYearInFlight = null);
  }

  static Future<int> _earliestEventYearInternal() async {
    await flushPending();
    DateTime? earliest;

    final remote = _remotePlays;
    if (remote != null) {
      try {
        final snapshot = await remote.orderBy('s').limit(1).get();
        if (snapshot.docs.isNotEmpty) {
          final event = PlayEvent.fromJson(snapshot.docs.first.data());
          if (event != null) earliest = event.startedAt;
        }
      } catch (error) {
        debugPrint('ListeningHistoryService: earliest fetch failed: $error');
      }
    }

    for (final event in await _loadPending()) {
      if (earliest == null || event.startedAt.isBefore(earliest)) {
        earliest = event.startedAt;
      }
    }

    return (earliest ?? DateTime.now()).year;
  }
}

class _CachedEvents {
  _CachedEvents(this.events, this.fetchedAt);

  final List<PlayEvent> events;
  final DateTime fetchedAt;
}
