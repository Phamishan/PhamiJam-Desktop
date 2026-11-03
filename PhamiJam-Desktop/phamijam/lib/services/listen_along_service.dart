import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FriendNowPlaying {
  final List<Map<String, dynamic>> queue;
  final int queueIndex;
  final Duration position;
  final bool isPlaying;
  final DateTime updatedAt;
  final Duration? trimStart;
  final Duration? trimEnd;

  const FriendNowPlaying({
    required this.queue,
    required this.queueIndex,
    required this.position,
    required this.isPlaying,
    required this.updatedAt,
    this.trimStart,
    this.trimEnd,
  });

  Map<String, dynamic>? get currentTrack =>
      (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null;

  bool get isLive =>
      currentTrack != null &&
      DateTime.now().difference(updatedAt) < const Duration(minutes: 2);
}

class ListenAlongService {
  ListenAlongService._();

  static DocumentReference<Map<String, dynamic>>? get _ownDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('status')
        .doc('nowPlaying');
  }

  static DocumentReference<Map<String, dynamic>> _friendDoc(String friendUid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(friendUid)
          .collection('status')
          .doc('nowPlaying');

  static Map<String, dynamic> _trackToJson(Map<String, dynamic> item) => {
    'v': item['videoId'] as String?,
    't': (item['songName'] ?? '').toString(),
    'a': (item['artistName'] ?? '').toString(),
    'c': item['artistId'] as String?,
    'd': ((item['durationSeconds'] as int?) ?? 0) * 1000,
  };

  static Map<String, dynamic>? _trackFromJson(dynamic json) {
    if (json is! Map) return null;
    final videoId = json['v'];
    if (videoId is! String || videoId.isEmpty) return null;
    return {
      'videoId': videoId,
      'songName': json['t'] is String ? json['t'] as String : '',
      'artistName': json['a'] is String ? json['a'] as String : '',
      'artistId': json['c'] as String?,
      'durationSeconds': json['d'] is int ? (json['d'] as int) ~/ 1000 : 0,
    };
  }

  static Future<void> pushNowPlaying({
    required List<Map<String, dynamic>> queue,
    required int queueIndex,
    required Duration position,
    required bool isPlaying,
    Duration? trimStart,
    Duration? trimEnd,
  }) async {
    final doc = _ownDoc;
    if (doc == null) return;
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    final currentVideoId = queue[queueIndex]['videoId'] as String?;
    if (currentVideoId == null || currentVideoId.isEmpty) return;

    final syncableQueue = queue
        .where((item) => (item['videoId'] as String?)?.isNotEmpty ?? false)
        .toList();
    final syncableIndex = syncableQueue.indexWhere(
      (item) => item['videoId'] == currentVideoId,
    );
    if (syncableIndex < 0) return;

    try {
      await doc.set({
        'queue': syncableQueue.map(_trackToJson).toList(),
        'queueIndex': syncableIndex,
        'positionMs': position.inMilliseconds,
        'isPlaying': isPlaying,
        'trimStartMs': trimStart?.inMilliseconds,
        'trimEndMs': trimEnd?.inMilliseconds,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('ListenAlongService: push failed: $error');
    }
  }

  static Future<void> clearNowPlaying() async {
    final doc = _ownDoc;
    if (doc == null) return;
    try {
      await doc.set({
        'queue': [],
        'isPlaying': false,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (error) {
      debugPrint('ListenAlongService: clear failed: $error');
    }
  }

  static Stream<FriendNowPlaying?> watchFriendNowPlaying(String friendUid) {
    return _friendDoc(friendUid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;

      final queue = ((data['queue'] as List?) ?? [])
          .map(_trackFromJson)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (queue.isEmpty) return null;
      final queueIndex = data['queueIndex'] as int? ?? 0;
      if (queueIndex < 0 || queueIndex >= queue.length) return null;

      final updatedAt = data['updatedAt'];
      if (updatedAt is! Timestamp) return null;

      final trimStartMs = data['trimStartMs'] as int?;
      final trimEndMs = data['trimEndMs'] as int?;

      return FriendNowPlaying(
        queue: queue,
        queueIndex: queueIndex,
        position: Duration(milliseconds: data['positionMs'] as int? ?? 0),
        isPlaying: data['isPlaying'] as bool? ?? false,
        updatedAt: updatedAt.toDate(),
        trimStart: trimStartMs != null ? Duration(milliseconds: trimStartMs) : null,
        trimEnd: trimEndMs != null ? Duration(milliseconds: trimEndMs) : null,
      );
    });
  }
}
