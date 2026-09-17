import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FriendPresence {
  final bool online;
  final DateTime? lastSeenAt;

  const FriendPresence({required this.online, this.lastSeenAt});

  static const FriendPresence offline = FriendPresence(online: false);
}

class PresenceService {
  PresenceService._();

  static const Duration _staleAfter = Duration(seconds: 90);
  static const Duration _heartbeatInterval = Duration(seconds: 30);

  static Timer? _heartbeat;

  static DocumentReference<Map<String, dynamic>>? get _ownDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('status')
        .doc('presence');
  }

  static Future<void> goOnline() async {
    final doc = _ownDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'online': true,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('PresenceService: goOnline failed: $error');
    }
  }

  static Future<void> goOffline() async {
    stopHeartbeat();
    final doc = _ownDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'online': false,
        'lastSeenAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('PresenceService: goOffline failed: $error');
    }
  }

  static void startHeartbeat() {
    _heartbeat?.cancel();
    unawaited(goOnline());
    _heartbeat = Timer.periodic(_heartbeatInterval, (_) => goOnline());
  }

  static void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  static FriendPresence _deriveStatus(Map<String, dynamic>? data) {
    final rawOnline = data?['online'] == true;
    final lastSeenRaw = data?['lastSeenAt'];
    final lastSeenAt = lastSeenRaw is Timestamp ? lastSeenRaw.toDate() : null;
    final isStale =
        lastSeenAt == null ||
        DateTime.now().difference(lastSeenAt) > _staleAfter;
    return FriendPresence(
      online: rawOnline && !isStale,
      lastSeenAt: lastSeenAt,
    );
  }

  static Stream<FriendPresence> watchPresence(String friendUid) {
    late final StreamController<FriendPresence> controller;
    Map<String, dynamic>? latestData;
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? docSub;
    Timer? ticker;

    void emit() {
      if (!controller.isClosed) controller.add(_deriveStatus(latestData));
    }

    controller = StreamController<FriendPresence>.broadcast(
      onListen: () {
        docSub = FirebaseFirestore.instance
            .collection('users')
            .doc(friendUid)
            .collection('status')
            .doc('presence')
            .snapshots()
            .listen((snapshot) {
              latestData = snapshot.data();
              emit();
            }, onError: (_) {});
        ticker = Timer.periodic(const Duration(seconds: 20), (_) => emit());
      },
      onCancel: () {
        docSub?.cancel();
        ticker?.cancel();
      },
    );
    return controller.stream;
  }
}
