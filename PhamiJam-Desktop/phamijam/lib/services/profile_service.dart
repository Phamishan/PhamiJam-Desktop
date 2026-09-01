import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:phamijam/models/grid_tile.dart';
import 'package:phamijam/models/user_profile.dart';

typedef ProfileSearchResult = ({String uid, UserProfile profile});

class UsernameTakenException implements Exception {
  UsernameTakenException(this.username);
  final String username;

  @override
  String toString() => 'UsernameTakenException($username)';
}

class ProfileService {
  ProfileService._();

  static const Duration _writeTimeout = Duration(seconds: 8);
  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(milliseconds: 400);
  static final RegExp usernamePattern = RegExp(r'^[a-z][a-z0-9_]{2,19}$');

  static Future<T> _withRetry<T>(Future<T> Function() attempt) async {
    for (var i = 0; ; i++) {
      try {
        return await attempt();
      } on TimeoutException {
        if (i >= _maxRetries) rethrow;
      } on FirebaseException {
        if (i >= _maxRetries) rethrow;
      }
      await Future.delayed(_retryDelay);
    }
  }

  static String? get _currentUid => FirebaseAuth.instance.currentUser?.uid;
  static DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);
  static CollectionReference<Map<String, dynamic>> _profilePlaylists(
    String uid,
  ) => _userDoc(uid).collection('profilePlaylists');
  static DocumentReference<Map<String, dynamic>> _usernameDoc(
    String username,
  ) => FirebaseFirestore.instance.collection('usernames').doc(username);

  static Future<UserProfile> fetchProfile(String uid) => _withRetry(() async {
    final snapshot = await _userDoc(
      uid,
    ).get(const GetOptions(source: Source.server)).timeout(_writeTimeout);
    return UserProfile.fromMap(snapshot.data()?['profile']);
  });

  static Future<String> resolveProfileLinkId(String idOrUsername) async {
    final resolved = await resolveUsername(idOrUsername);
    return resolved ?? idOrUsername;
  }

  static Future<String?> resolveUsername(String username) {
    final normalized = username.trim().toLowerCase();
    if (normalized.isEmpty) return Future.value(null);
    return _withRetry(() async {
      final snapshot = await _usernameDoc(
        normalized,
      ).get().timeout(_writeTimeout);
      return snapshot.data()?['uid'] as String?;
    });
  }

  static Future<void> claimUsername(String username) async {
    final uid = _currentUid;
    if (uid == null) return;
    final normalized = username.trim().toLowerCase();
    if (!usernamePattern.hasMatch(normalized)) {
      throw FormatException('Invalid username: $normalized');
    }

    await _withRetry(() async {
      final newDoc = _usernameDoc(normalized);
      final userDoc = _userDoc(uid);

      final newSnapshot = await newDoc.get().timeout(_writeTimeout);
      if (newSnapshot.exists && newSnapshot.data()?['uid'] != uid) {
        throw UsernameTakenException(normalized);
      }

      final userSnapshot = await userDoc.get().timeout(_writeTimeout);
      final currentProfile = userSnapshot.data()?['profile'];
      final oldUsername = currentProfile is Map
          ? currentProfile['username'] as String?
          : null;

      if (oldUsername != null && oldUsername != normalized) {
        await _usernameDoc(oldUsername).delete().timeout(_writeTimeout);
      }
      await newDoc.set({'uid': uid}).timeout(_writeTimeout);
      await userDoc
          .set({
            'profile': {
              'username': normalized,
              'profileUpdatedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true))
          .timeout(_writeTimeout);
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
    await _withRetry(
      () => _userDoc(uid)
          .set({
            'profile': {
              'displayNameOverride': ?displayNameOverride,
              'bio': ?bio,
              'avatarChoice': ?avatarChoice,
              'avatarUrl': ?avatarUrl,
              'profileUpdatedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true))
          .timeout(_writeTimeout),
    );
  }

  static Future<void> saveGridLayout(List<GridTile> tiles) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _withRetry(
      () => _userDoc(uid)
          .set({
            'profile': {
              'gridLayoutVersion': 1,
              'gridLayout': tiles.map((tile) => tile.toMap()).toList(),
              'profileUpdatedAt': FieldValue.serverTimestamp(),
            },
          }, SetOptions(merge: true))
          .timeout(_writeTimeout),
    );
  }

  static Future<List<String>> fetchProfilePlaylistIds(String uid) {
    return _withRetry(() async {
      final snapshot = await _profilePlaylists(
        uid,
      ).orderBy('addedAt', descending: true).get().timeout(_writeTimeout);
      return snapshot.docs.map((doc) => doc.id).toList();
    });
  }

  static Future<void> addProfilePlaylist(String playlistId) async {
    final uid = _currentUid;
    if (uid == null || playlistId.isEmpty) return;
    await _withRetry(
      () => _profilePlaylists(uid)
          .doc(playlistId)
          .set({
            'playlistId': playlistId,
            'addedAt': FieldValue.serverTimestamp(),
          })
          .timeout(_writeTimeout),
    );
  }

  static Future<void> removeProfilePlaylist(String playlistId) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _withRetry(
      () => _profilePlaylists(
        uid,
      ).doc(playlistId).delete().timeout(_writeTimeout),
    );
  }

  static Future<List<ProfileSearchResult>> searchByUsername(
    String query, {
    int limit = 20,
  }) {
    var normalized = query.trim().toLowerCase();
    if (normalized.startsWith('@')) normalized = normalized.substring(1);
    if (normalized.isEmpty) return Future.value(const []);
    return _withRetry(() async {
      final snapshot = await FirebaseFirestore.instance
          .collection('usernames')
          .orderBy(FieldPath.documentId)
          .startAt([normalized])
          .endAt([normalized + String.fromCharCode(0xf8ff)])
          .limit(limit)
          .get()
          .timeout(_writeTimeout);
      final me = _currentUid;
      final uids = snapshot.docs
          .map((doc) => doc.data()['uid'] as String?)
          .whereType<String>()
          .where((uid) => uid != me)
          .toList();
      return Future.wait(
        uids.map((uid) async => (uid: uid, profile: await fetchProfile(uid))),
      );
    });
  }
}
