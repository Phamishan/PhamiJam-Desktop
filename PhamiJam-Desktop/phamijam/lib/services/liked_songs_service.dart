import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class LikedSongsService {
  LikedSongsService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('likedSongs');
  }

  static String _docId(String videoId) =>
      videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    return _fetchFrom(collection);
  }

  static Future<List<Map<String, dynamic>>> fetchAllForUid(String uid) =>
      _fetchFrom(
        FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('likedSongs'),
      );

  static Future<List<Map<String, dynamic>>> _fetchFrom(
    CollectionReference<Map<String, dynamic>> collection,
  ) async {
    final snapshot = await collection
        .orderBy('likedAt', descending: true)
        .get();
    return snapshot.docs
        .map(_songFromData)
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  static Future<void> like(Map<String, dynamic> song) async {
    final collection = _collection;
    final videoId = song['videoId'] as String?;
    if (collection == null || videoId == null || videoId.isEmpty) return;
    await collection.doc(_docId(videoId)).set({
      'videoId': videoId,
      'title': (song['title'] ?? '').toString(),
      'artist': (song['artist'] ?? '').toString(),
      'thumbnailUrl': (song['thumbnailUrl'] ?? '').toString(),
      'durationMs': ((song['durationSeconds'] as int?) ?? 0) * 1000,
      'channelId': song['artistId'] as String?,
      'likedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unlike(String videoId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(videoId)).delete();
  }

  static Map<String, dynamic>? _songFromData(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final videoId = data['videoId'];
    if (videoId is! String || videoId.isEmpty) return null;
    final likedAt = data['likedAt'];
    return {
      'videoId': videoId,
      'title': data['title'] is String ? data['title'] as String : '',
      'artist': data['artist'] is String ? data['artist'] as String : '',
      'thumbnailUrl': data['thumbnailUrl'] is String
          ? data['thumbnailUrl'] as String
          : '',
      'durationSeconds': data['durationMs'] is int
          ? (data['durationMs'] as int) ~/ 1000
          : 0,
      'artistId': data['channelId'] is String
          ? data['channelId'] as String
          : null,
      'addedAt': likedAt is Timestamp ? likedAt.toDate() : null,
    };
  }
}
