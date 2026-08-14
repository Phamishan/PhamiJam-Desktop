import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class DriveFolderService {
  DriveFolderService._();

  static DocumentReference<Map<String, dynamic>>? get _userDoc {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance.collection('users').doc(uid);
  }

  static Future<String?> getFolderId() async {
    final doc = _userDoc;
    if (doc == null) return null;
    final snapshot = await doc.get();
    final folderId = snapshot.data()?['driveFolderId'];
    return folderId is String && folderId.isNotEmpty ? folderId : null;
  }

  static Future<void> setFolderId(
    String folderId, {
    bool requiresAuth = false,
  }) async {
    final doc = _userDoc;
    if (doc == null || folderId.isEmpty) return;
    await doc.set({
      'driveFolderId': folderId,
      'driveFolderRequiresAuth': requiresAuth,
    }, SetOptions(merge: true));
  }

  static Future<bool> getRequiresAuth() async {
    final doc = _userDoc;
    if (doc == null) return false;
    final snapshot = await doc.get();
    return snapshot.data()?['driveFolderRequiresAuth'] == true;
  }

  static Future<void> clearFolderId() async {
    final doc = _userDoc;
    if (doc == null) return;
    await doc.set({
      'driveFolderId': FieldValue.delete(),
      'driveFolderRequiresAuth': FieldValue.delete(),
    }, SetOptions(merge: true));
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
