import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class FriendNowPlaying {
  final Map<String, dynamic>? track;
  final Duration position;
  final bool isPlaying;
  final DateTime updatedAt;

  const FriendNowPlaying({
    required this.track,
    required this.position,
    required this.isPlaying,
    required this.updatedAt,
  });

  bool get isLive =>
      track != null &&
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

  static Future<void> pushNowPlaying({
    required Map<String, dynamic> track,
    required Duration position,
    required bool isPlaying,
  }) async {
    final doc = _ownDoc;
    if (doc == null) return;
    final videoId = track['videoId'] as String?;
    if (videoId == null || videoId.isEmpty) return;

    try {
      await doc.set({
        'track': {
          'v': videoId,
          't': (track['songName'] ?? '').toString(),
          'a': (track['artistName'] ?? '').toString(),
          'c': track['artistId'] as String?,
          'd': ((track['durationSeconds'] as int?) ?? 0) * 1000,
        },
        'positionMs': position.inMilliseconds,
        'isPlaying': isPlaying,
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
        'track': null,
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

      Map<String, dynamic>? track;
      final trackJson = data['track'];
      if (trackJson is Map) {
        final videoId = trackJson['v'];
        if (videoId is String && videoId.isNotEmpty) {
          track = {
            'videoId': videoId,
            'songName': trackJson['t'] is String
                ? trackJson['t'] as String
                : '',
            'artistName': trackJson['a'] is String
                ? trackJson['a'] as String
                : '',
            'artistId': trackJson['c'] as String?,
            'durationSeconds': trackJson['d'] is int
                ? (trackJson['d'] as int) ~/ 1000
                : 0,
          };
        }
      }

      final updatedAt = data['updatedAt'];
      if (updatedAt is! Timestamp) return null;

      return FriendNowPlaying(
        track: track,
        position: Duration(milliseconds: data['positionMs'] as int? ?? 0),
        isPlaying: data['isPlaying'] as bool? ?? false,
        updatedAt: updatedAt.toDate(),
      );
    });
  }
}
