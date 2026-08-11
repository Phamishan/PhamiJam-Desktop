import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavedPlaylistsService {
  SavedPlaylistsService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('savedPlaylists');
  }

  static Future<List<String>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    final snapshot = await collection
        .orderBy('savedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  static Future<void> save(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(playlistId).set({
      'playlistId': playlistId,
      'savedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> unsave(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(playlistId).delete();
  }
}
