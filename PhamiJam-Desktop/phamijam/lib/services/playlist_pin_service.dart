import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class PlaylistPinService {
  PlaylistPinService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('pinnedPlaylists');
  }

  static String _docId(String playlistId) =>
      playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<List<String>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    final snapshot = await collection
        .orderBy('pinnedAt', descending: true)
        .get();
    return snapshot.docs
        .map((doc) => doc.data()['playlistId'])
        .whereType<String>()
        .toList();
  }

  static Future<void> pin(String playlistId) async {
    final collection = _collection;
    if (collection == null || playlistId.isEmpty) return;
    await collection.doc(_docId(playlistId)).set({
      'playlistId': playlistId,
      'pinnedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unpin(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(playlistId)).delete();
  }
}
