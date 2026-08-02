import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/models/edited_song_trim.dart';

class EditedSongsService {
  EditedSongsService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('editedSongs');
  }

  static String _docId(String videoId) =>
      videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

  static Future<List<EditedSongTrim>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    final snapshot = await collection
        .orderBy('updatedAt', descending: true)
        .get();
    return snapshot.docs.map((doc) => _fromData(doc.data())).toList();
  }

  static Future<void> setTrim(EditedSongTrim trim) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(trim.videoId)).set({
      'videoId': trim.videoId,
      'startMs': trim.startMs,
      'endMs': trim.endMs,
      'title': trim.title,
      'artist': trim.artist,
      'thumbnailUrl': trim.thumbnailUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeTrim(String videoId) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(_docId(videoId)).delete();
  }

  static EditedSongTrim _fromData(Map<String, dynamic> data) {
    return EditedSongTrim(
      videoId: (data['videoId'] as String?) ?? '',
      startMs: (data['startMs'] as num?)?.toInt() ?? 0,
      endMs: (data['endMs'] as num?)?.toInt() ?? 0,
      title: (data['title'] as String?) ?? '',
      artist: (data['artist'] as String?) ?? '',
      thumbnailUrl: (data['thumbnailUrl'] as String?) ?? '',
    );
  }
}
