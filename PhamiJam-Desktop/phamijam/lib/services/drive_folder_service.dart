import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriveFolderService {
  DriveFolderService._();

  static DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static DocumentReference<Map<String, dynamic>>? get _settingsDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('private')
        .doc('settings');
  }

  static Future<Map<String, dynamic>> _readSettings() async {
    final settingsDoc = _settingsDoc;
    if (settingsDoc == null) return const {};
    final settingsSnapshot = await settingsDoc.get();
    final settingsData = settingsSnapshot.data();
    if (settingsData?['driveFolderId'] != null) return settingsData!;

    final userDoc = _userDoc;
    if (userDoc == null) return settingsData ?? const {};
    final userSnapshot = await userDoc.get();
    final legacyFolderId = userSnapshot.data()?['driveFolderId'];
    if (legacyFolderId is! String || legacyFolderId.isEmpty) {
      return settingsData ?? const {};
    }

    final migrated = {
      'driveFolderId': legacyFolderId,
      'driveFolderRequiresAuth':
          userSnapshot.data()?['driveFolderRequiresAuth'] == true,
    };
    await settingsDoc.set(migrated, SetOptions(merge: true));
    await userDoc.set({
      'driveFolderId': FieldValue.delete(),
      'driveFolderRequiresAuth': FieldValue.delete(),
    }, SetOptions(merge: true));
    return migrated;
  }

  static Future<String?> getFolderId() async {
    final folderId = (await _readSettings())['driveFolderId'];
    return folderId is String && folderId.isNotEmpty ? folderId : null;
  }

  static Future<void> setFolderId(
    String folderId, {
    bool requiresAuth = false,
  }) async {
    final doc = _settingsDoc;
    if (doc == null || folderId.isEmpty) return;
    await doc.set({
      'driveFolderId': folderId,
      'driveFolderRequiresAuth': requiresAuth,
    }, SetOptions(merge: true));
  }

  static Future<bool> getRequiresAuth() async {
    return (await _readSettings())['driveFolderRequiresAuth'] == true;
  }

  static Future<void> clearFolderId() async {
    final doc = _settingsDoc;
    if (doc != null) {
      await doc.set({
        'driveFolderId': FieldValue.delete(),
        'driveFolderRequiresAuth': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
    final userDoc = _userDoc;
    if (userDoc != null) {
      await userDoc.set({
        'driveFolderId': FieldValue.delete(),
        'driveFolderRequiresAuth': FieldValue.delete(),
      }, SetOptions(merge: true));
    }
  }

  static final RegExp _folderPathPattern = RegExp(r'/folders/([\w-]+)');
  static final RegExp _idParamPattern = RegExp(r'[?&]id=([\w-]+)');
  static final RegExp _bareIdPattern = RegExp(r'^[\w-]{10,}$');

  static String? extractFolderId(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return null;

    final folderMatch = _folderPathPattern.firstMatch(trimmed);
    if (folderMatch != null) return folderMatch.group(1);

    final idParamMatch = _idParamPattern.firstMatch(trimmed);
    if (idParamMatch != null) return idParamMatch.group(1);

    if (_bareIdPattern.hasMatch(trimmed)) return trimmed;

    return null;
  }
}
