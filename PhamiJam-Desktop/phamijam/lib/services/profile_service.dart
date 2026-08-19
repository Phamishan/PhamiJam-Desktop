import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/models/grid_tile.dart';
import 'package:phamijam/models/user_profile.dart';

class UsernameTakenException implements Exception {
  UsernameTakenException(this.username);
  final String username;

  @override
  String toString() => 'UsernameTakenException($username)';
}

class ProfileService {
  ProfileService._();

  static final RegExp usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  static String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;

  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  static CollectionReference<Map<String, dynamic>> _profilePlaylists(
    String uid,
  ) => _userDoc(uid).collection('profilePlaylists');

  static DocumentReference<Map<String, dynamic>> _usernameDoc(
    String username,
  ) => FirebaseFirestore.instance.collection('usernames').doc(username);

  static Future<UserProfile> fetchProfile(String uid) async {
    final snapshot = await _userDoc(uid).get();
    return UserProfile.fromMap(snapshot.data()?['profile']);
  }

  static Future<String> resolveProfileLinkId(String idOrUsername) async {
    final resolved = await resolveUsername(idOrUsername);
    return resolved ?? idOrUsername;
  }

  static Future<String?> resolveUsername(String username) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    final snapshot = await _usernameDoc(normalized).get();
    return snapshot.data()?['uid'] as String?;
  }

  static Future<void> claimUsername(String username) async {
    final uid = _currentUid;
    if (uid == null) return;
    final normalized = username.trim().toLowerCase();
    if (!usernamePattern.hasMatch(normalized)) {
      throw FormatException('Invalid username: $normalized');
    }

    final newDoc = _usernameDoc(normalized);
    final userDoc = _userDoc(uid);

    await FirebaseFirestore.instance.runTransaction((transaction) async {
      final newSnapshot = await transaction.get(newDoc);
      if (newSnapshot.exists && newSnapshot.data()?['uid'] != uid) {
        throw UsernameTakenException(normalized);
      }
      final userSnapshot = await transaction.get(userDoc);
      final currentProfile = userSnapshot.data()?['profile'];
      final oldUsername = currentProfile is Map
          ? currentProfile['username'] as String?
          : null;

      if (oldUsername != null && oldUsername != normalized) {
        transaction.delete(_usernameDoc(oldUsername));
      }
      transaction.set(newDoc, {'uid': uid});
      transaction.set(userDoc, {
        'profile': {
          'username': normalized,
          'profileUpdatedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
    });
  }

  static Future<void> updateProfile({
    String? displayNameOverride,
    String? bio,
    String? avatarChoice,
    String? avatarUrl,
  }) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _userDoc(uid).set({
      'profile': {
        'displayNameOverride': ?displayNameOverride,
        'bio': ?bio,
        'avatarChoice': ?avatarChoice,
        'avatarUrl': ?avatarUrl,
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<void> saveGridLayout(List<GridTile> tiles) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _userDoc(uid).set({
      'profile': {
        'gridLayoutVersion': 1,
        'gridLayout': tiles.map((tile) => tile.toMap()).toList(),
        'profileUpdatedAt': FieldValue.serverTimestamp(),
      },
    }, SetOptions(merge: true));
  }

  static Future<List<String>> fetchProfilePlaylistIds(String uid) async {
    final snapshot = await _profilePlaylists(
      uid,
    ).orderBy('addedAt', descending: true).get();
    return snapshot.docs.map((doc) => doc.id).toList();
  }

  static Future<void> addProfilePlaylist(String playlistId) async {
    final uid = _currentUid;
    if (uid == null || playlistId.isEmpty) return;
    await _profilePlaylists(uid).doc(playlistId).set({
      'playlistId': playlistId,
      'addedAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> removeProfilePlaylist(String playlistId) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _profilePlaylists(uid).doc(playlistId).delete();
  }
}
