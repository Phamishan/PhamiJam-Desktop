import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';

class PlaylistCoverService {
  PlaylistCoverService._();

  static String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = _uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('playlistCovers');
  }

  static String _docId(String playlistId) =>
      playlistId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<Map<String, String>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return {};
    final snapshot = await collection.get();
    final result = <String, String>{};
    for (final doc in snapshot.docs) {
      final playlistId = doc.data()['playlistId'];
      final url = doc.data()['url'];
      if (playlistId is String && url is String && url.isNotEmpty) {
        result[playlistId] = url;
      }
    }
    return result;
  }

  static Future<String?> fetchOne(String playlistId) async {
    final collection = _collection;
    if (collection == null) return null;
    final snapshot = await collection.doc(_docId(playlistId)).get();
    final url = snapshot.data()?['url'];
    return url is String && url.isNotEmpty ? url : null;
  }

  static Future<String> upload(String playlistId, File imageFile) async {
    final uid = _uid;
    final collection = _collection;
    if (uid == null || collection == null) {
      throw StateError('Not signed in.');
    }

    final ref = FirebaseStorage.instance.ref(
      'playlistCovers/$uid/${_docId(playlistId)}.jpg',
    );
    await ref.putFile(imageFile, SettableMetadata(contentType: 'image/jpeg'));
    final url = await ref.getDownloadURL();

    await collection.doc(_docId(playlistId)).set({
      'playlistId': playlistId,
      'url': url,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return url;
  }

  static Future<void> remove(String playlistId) async {
    final uid = _uid;
    final collection = _collection;
    if (uid == null || collection == null) return;

    try {
      await FirebaseStorage.instance
          .ref('playlistCovers/$uid/${_docId(playlistId)}.jpg')
          .delete();
    } catch (_) {}
    await collection.doc(_docId(playlistId)).delete();
  }
}
