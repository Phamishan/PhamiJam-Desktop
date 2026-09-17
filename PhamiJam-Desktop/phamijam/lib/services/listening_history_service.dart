import 'dart:async';
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
  static const String _yearCacheKeyPrefix = 'phamijam.play_history.year.';
  static const String _earliestYearKeyPrefix =
      'phamijam.play_history.earliest_year.';
  static const int _maxPending = 2000;
  static const int _minListenMs = 30000;
  static const Duration _syncTimeout = Duration(seconds: 8);
  static const Duration _queryTimeout = Duration(seconds: 20);
  static const Duration _prefsTimeout = Duration(seconds: 5);
  static const int _batchChunkSize = 450;
  static const int _recentEventsLimit = 100;
  static Future<void>? _flushInProgress;
  static final Map<String, Future<List<PlayEvent>>> _yearInFlight = {};
  static final Map<String, int> _cachedEarliestYearByUid = {};
  static final Map<String, Future<int>> _earliestYearInFlightByUid = {};

  static String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? get _remotePlays {
    final uid = _currentUid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('plays');
  }

  static Future<List<PlayEvent>> _loadPending() async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final raw = prefs.getString(_pendingKey);
      if (raw == null || raw.isEmpty) return [];
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
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setString(
        _pendingKey,
        jsonEncode(events.map((e) => e.toJson()).toList()),
      );
    } catch (error) {
      debugPrint('ListeningHistoryService: failed to save buffer: $error');
    }
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
    if (remote == null) {
      return;
    }
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

  static Future<List<PlayEvent>> _mergeWithPending(
    List<PlayEvent> events,
    int sinceMs,
    int untilMs,
  ) async {
    final merged = List<PlayEvent>.from(events);
    final seen = merged.map((e) => e.docId).toSet();
    final pending = await _loadPending();
    for (final event in pending) {
      final ms = event.startedAt.millisecondsSinceEpoch;
      if (ms >= sinceMs && ms < untilMs && seen.add(event.docId)) {
        merged.add(event);
      }
    }
    merged.sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return merged;
  }

  static Future<List<PlayEvent>> eventsSince(
    DateTime since, {
    DateTime? until,
  }) {
    final yearMatch = _matchYearRange(since, until);
    if (yearMatch != null) return _eventsForYear(yearMatch);
    return _eventsSinceInternal(since, until: until);
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
        final snapshot = await query.get().timeout(_queryTimeout);
        for (final doc in snapshot.docs) {
          final event = PlayEvent.fromJson(doc.data());
          if (event != null) events.add(event);
        }
      } catch (error) {
        debugPrint('ListeningHistoryService: remote fetch failed: $error');
      }
    }

    return _mergeWithPending(
      events,
      sinceMs,
      untilMs ??
          DateTime.now().add(const Duration(days: 3650)).millisecondsSinceEpoch,
    );
  }

  static int? _matchYearRange(DateTime since, DateTime? until) {
    if (until == null) return null;
    final year = since.year;
    if (since != DateTime(year)) return null;
    if (until != DateTime(year + 1)) return null;
    return year;
  }

  static Future<List<PlayEvent>> _eventsForYear(int year) {
    final key = '$_currentUid|$year';
    return _yearInFlight[key] ??= _eventsForYearInternal(year).whenComplete(() {
      _yearInFlight.remove(key);
    });
  }

  static Future<List<PlayEvent>> _eventsForYearInternal(int year) async {
    await flushPending();
    final uid = _currentUid;
    final sinceMs = DateTime(year).millisecondsSinceEpoch;
    final untilMs = DateTime(year + 1).millisecondsSinceEpoch;
    final isClosedYear = year < DateTime.now().year;

    _YearCache? cache;
    if (uid != null) {
      cache = await _loadYearCache(uid, year);
      if (cache != null && cache.closed) {
        return _mergeWithPending(cache.events, sinceMs, untilMs);
      }
    }

    final remote = _remotePlays;
    if (remote == null) {
      return _mergeWithPending(cache?.events ?? const [], sinceMs, untilMs);
    }

    var events = List<PlayEvent>.from(cache?.events ?? const []);
    try {
      final fetchFromMs = cache?.syncedThroughMs ?? sinceMs;
      final snapshot = await remote
          .where('s', isGreaterThanOrEqualTo: fetchFromMs)
          .where('s', isLessThan: untilMs)
          .get()
          .timeout(_queryTimeout);
      final seen = events.map((e) => e.docId).toSet();
      for (final doc in snapshot.docs) {
        final event = PlayEvent.fromJson(doc.data());
        if (event != null && seen.add(event.docId)) events.add(event);
      }
      events.sort((a, b) => a.startedAt.compareTo(b.startedAt));

      if (uid != null) {
        await _saveYearCache(
          uid,
          year,
          _YearCache(
            events: events,
            syncedThroughMs: isClosedYear
                ? untilMs
                : DateTime.now().millisecondsSinceEpoch,
            closed: isClosedYear,
          ),
        );
      }
    } catch (error) {
      debugPrint('ListeningHistoryService: year fetch failed: $error');
    }

    return _mergeWithPending(events, sinceMs, untilMs);
  }

  static String _yearCacheKey(String uid, int year) =>
      '$_yearCacheKeyPrefix$uid.$year';

  static Future<_YearCache?> _loadYearCache(String uid, int year) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      final raw = prefs.getString(_yearCacheKey(uid, year));
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final syncedThroughMs = decoded['syncedThroughMs'];
      if (syncedThroughMs is! int) return null;
      final rawEvents = decoded['events'];
      final events = rawEvents is List
          ? rawEvents
                .whereType<Map<String, dynamic>>()
                .map(PlayEvent.fromJson)
                .whereType<PlayEvent>()
                .toList()
          : <PlayEvent>[];
      return _YearCache(
        events: events,
        syncedThroughMs: syncedThroughMs,
        closed: decoded['closed'] == true,
      );
    } catch (error) {
      debugPrint('ListeningHistoryService: failed to parse year cache: $error');
      return null;
    }
  }

  static Future<void> _saveYearCache(
    String uid,
    int year,
    _YearCache cache,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance().timeout(
        _prefsTimeout,
      );
      await prefs.setString(
        _yearCacheKey(uid, year),
        jsonEncode({
          'events': cache.events.map((e) => e.toJson()).toList(),
          'syncedThroughMs': cache.syncedThroughMs,
          'closed': cache.closed,
        }),
      );
    } catch (error) {
      debugPrint('ListeningHistoryService: failed to save year cache: $error');
    }
  }

  static Future<List<PlayEvent>> recentEvents({
    int limit = _recentEventsLimit,
  }) async {
    await flushPending();
    final events = <PlayEvent>[];

    final remote = _remotePlays;
    if (remote != null) {
      try {
        final snapshot = await remote
            .orderBy('s', descending: true)
            .limit(limit)
            .get()
            .timeout(_queryTimeout);
        for (final doc in snapshot.docs) {
          final event = PlayEvent.fromJson(doc.data());
          if (event != null) events.add(event);
        }
      } catch (error) {
        debugPrint('ListeningHistoryService: recent fetch failed: $error');
      }
    }

    final seen = events.map((e) => e.docId).toSet();
    for (final event in await _loadPending()) {
      if (seen.add(event.docId)) events.add(event);
    }
    events.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    if (events.length > limit) events.removeRange(limit, events.length);
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
      final snapshot = await query.get().timeout(_queryTimeout);
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
    final uid = _currentUid;
    if (uid == null) return _earliestEventYearInternal();

    final cached = _cachedEarliestYearByUid[uid];
    if (cached != null) return Future.value(cached);
    return _earliestYearInFlightByUid[uid] ??= _earliestEventYearInternal()
        .then((year) {
          _cachedEarliestYearByUid[uid] = year;
          return year;
        })
        .whenComplete(() => _earliestYearInFlightByUid.remove(uid));
  }

  static Future<int> _earliestEventYearInternal() async {
    await flushPending();
    final uid = _currentUid;

    if (uid != null) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          _prefsTimeout,
        );
        final persisted = prefs.getInt('$_earliestYearKeyPrefix$uid');
        if (persisted != null) {
          return persisted;
        }
      } catch (error) {
        debugPrint(
          'ListeningHistoryService: failed to read earliest year cache: $error',
        );
      }
    }

    DateTime? earliest;

    final remote = _remotePlays;
    if (remote != null) {
      try {
        final snapshot = await remote
            .orderBy('s')
            .limit(1)
            .get()
            .timeout(_queryTimeout);
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

    final year = (earliest ?? DateTime.now()).year;
    if (uid != null && earliest != null) {
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          _prefsTimeout,
        );
        await prefs.setInt('$_earliestYearKeyPrefix$uid', year);
      } catch (error) {
        debugPrint(
          'ListeningHistoryService: failed to save earliest year cache: $error',
        );
      }
    }
    return year;
  }
}

class _YearCache {
  _YearCache({
    required this.events,
    required this.syncedThroughMs,
    required this.closed,
  });

  final List<PlayEvent> events;
  final int syncedThroughMs;
  final bool closed;
}
