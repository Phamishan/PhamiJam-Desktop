import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HiddenPlaylistsService {
  HiddenPlaylistsService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('hiddenPlaylists');
  }

  static String _docId(String playlistId) =>
      playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<List<String>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    final snapshot = await collection.get();
    return snapshot.docs
        .map((doc) => doc.data()['playlistId'])
        .whereType<String>()
        .toList();
  }

  static Future<void> hide(String playlistId) async {
    final collection = _collection;
    if (collection == null || playlistId.isEmpty) return;
    await collection.doc(_docId(playlistId)).set({'playlistId': playlistId});
  }

  static Future<void> unhide(String playlistId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(playlistId)).delete();
  }
}
