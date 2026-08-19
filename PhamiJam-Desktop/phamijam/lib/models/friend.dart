import 'package:cloud_firestore/cloud_firestore.dart';

class Friend {
  final String uid;
  final String displayName;
  final String? photoUrl;
  final DateTime? becameFriendsAt;

  const Friend({
    required this.uid,
    required this.displayName,
    this.photoUrl,
    this.becameFriendsAt,
  });

  static Friend? fromMap(String uid, Map<String, dynamic> raw) {
    final displayName = raw['displayName'];
    if (displayName is! String) return null;
    final becameFriendsAt = raw['becameFriendsAt'];
    return Friend(
      uid: uid,
      displayName: displayName,
      photoUrl: raw['photoUrl'] as String?,
      becameFriendsAt: becameFriendsAt is Timestamp
          ? becameFriendsAt.toDate()
          : null,
    );
  }
}
