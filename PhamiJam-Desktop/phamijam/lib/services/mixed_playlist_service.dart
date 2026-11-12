import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/services/google_drive_service.dart';
import 'package:phamijam/services/playlist_cover_service.dart';

class MixedPlaylistService {
  MixedPlaylistService._();

  static CollectionReference<Map<String, dynamic>>? get _collection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('mixedPlaylists');
  }

  static Map<String, dynamic> _parse(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};
    final rawTracks = data['tracks'];
    final tracks = rawTracks is List
        ? rawTracks
              .whereType<Map>()
              .map((t) => Map<String, dynamic>.from(t))
              .toList()
        : <Map<String, dynamic>>[];
    final createdAt = data['createdAt'];
    return <String, dynamic>{
      'id': doc.id,
      'title': (data['title'] as String?) ?? 'Untitled playlist',
      'description': (data['description'] as String?) ?? '',
      'tracks': tracks,
      'createdAt': createdAt is Timestamp ? createdAt.toDate() : null,
    };
  }

  static List<Map<String, dynamic>> _parseAll(
    QuerySnapshot<Map<String, dynamic>> snapshot,
  ) {
    final playlists = snapshot.docs.map(_parse).toList();
    playlists.sort((a, b) {
      final da = a['createdAt'] as DateTime? ?? DateTime.now();
      final db = b['createdAt'] as DateTime? ?? DateTime.now();
      return da.compareTo(db);
    });
    return playlists;
  }

  static Stream<List<Map<String, dynamic>>> watchAll() {
    final collection = _collection;
    if (collection == null) return const Stream.empty();
    return collection.snapshots().map(_parseAll);
  }

  static Stream<Map<String, dynamic>?> watchOne(String id) {
    final collection = _collection;
    if (collection == null) return const Stream.empty();
    return collection
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? _parse(doc) : null);
  }

  static Future<List<Map<String, dynamic>>> fetchAll() async {
    final collection = _collection;
    if (collection == null) return [];
    return _parseAll(await collection.get());
  }

  static Future<String> create(String title) async {
    final collection = _collection;
    if (collection == null) throw StateError('Not signed in.');
    final doc = await collection.add({
      'title': title.trim(),
      'description': '',
      'tracks': <Map<String, dynamic>>[],
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> rename(String id, String title) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(id).update({
      'title': title.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  static String coverKey(String id) => 'mixed-$id';

  static Future<void> delete(String id) async {
    final collection = _collection;
    if (collection == null) return;
    await collection.doc(id).delete();
    try {
      await PlaylistCoverService.remove(coverKey(id));
    } catch (_) {}
  }

  static String trackKey(Map<String, dynamic> track) {
    final source = (track['source'] as String?) ?? 'youtube';
    if (source == 'local') return 'local:${track['path'] ?? ''}';
    return 'id:${track['videoId'] ?? ''}';
  }

  static Map<String, dynamic> trackFromSong(Map<String, dynamic> song) {
    final videoId = (song['videoId'] as String?) ?? '';
    final path = (song['path'] as String?) ?? '';
    final String source;
    if (videoId.isEmpty && path.isNotEmpty) {
      source = 'local';
    } else if (videoId.startsWith(driveTrackIdPrefix)) {
      source = 'drive';
    } else {
      source = 'youtube';
    }
    final durationSeconds = (song['durationSeconds'] as int?) ?? 0;
    final durationMs = (song['durationMs'] as int?) ?? durationSeconds * 1000;
    return <String, dynamic>{
      'source': source,
      'videoId': source == 'local' ? '' : videoId,
      'title': ((song['title'] ?? song['songName'] ?? '') as Object).toString(),
      'artist': ((song['artist'] ?? song['artistName'] ?? '') as Object)
          .toString(),
      'thumbnailUrl': (song['thumbnailUrl'] as String?) ?? '',
      'durationMs': durationMs,
      'path': source == 'local' ? path : '',
      'artistId': (song['artistId'] as String?) ?? '',
    };
  }

  static Future<int> addTracks(
    String id,
    List<Map<String, dynamic>> tracks,
  ) async {
    final collection = _collection;
    if (collection == null) throw StateError('Not signed in.');
    final doc = collection.doc(id);
    final snapshot = await doc.get();
    if (!snapshot.exists) throw StateError('Playlist no longer exists.');
    final existing = _parse(snapshot)['tracks'] as List<Map<String, dynamic>>;
    final seen = existing.map(trackKey).toSet();
    final added = <Map<String, dynamic>>[];
    for (final track in tracks) {
      final key = trackKey(track);
      if (key == 'id:' || key == 'local:') continue;
      if (seen.add(key)) added.add(track);
    }
    if (added.isEmpty) return 0;
    await doc.update({
      'tracks': [...existing, ...added],
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return added.length;
  }

  static Future<void> removeTrackAt(String id, int index) async {
    final collection = _collection;
    if (collection == null) return;
    final doc = collection.doc(id);
    final snapshot = await doc.get();
    if (!snapshot.exists) return;
    final existing = List<Map<String, dynamic>>.from(
      _parse(snapshot)['tracks'] as List<Map<String, dynamic>>,
    );
    if (index < 0 || index >= existing.length) return;
    existing.removeAt(index);
    await doc.update({
      'tracks': existing,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
