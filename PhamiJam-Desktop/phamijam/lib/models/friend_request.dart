import 'package:cloud_firestore/cloud_firestore.dart';

enum FriendRequestStatus { pending }

FriendRequestStatus? _statusFromString(String? value) {
  for (final status in FriendRequestStatus.values) {
    if (status.name == value) return status;
  }
  return null;
}

class FriendRequest {
  final String otherUid;
  final String otherDisplayName;
  final String? otherPhotoUrl;
  final FriendRequestStatus status;
  final DateTime? sentAt;

  const FriendRequest({
    required this.otherUid,
    required this.otherDisplayName,
    this.otherPhotoUrl,
    this.status = FriendRequestStatus.pending,
    this.sentAt,
  });

  static FriendRequest? fromReceivedMap(Map<String, dynamic> raw) {
    final otherUid = raw['fromUid'];
    final otherDisplayName = raw['fromDisplayName'];
    if (otherUid is! String || otherDisplayName is! String) return null;
    return FriendRequest(
      otherUid: otherUid,
      otherDisplayName: otherDisplayName,
      otherPhotoUrl: raw['fromPhotoUrl'] as String?,
      status:
          _statusFromString(raw['status'] as String?) ??
          FriendRequestStatus.pending,
      sentAt: _timestamp(raw['sentAt']),
    );
  }

  static FriendRequest? fromSentMap(Map<String, dynamic> raw) {
    final otherUid = raw['toUid'];
    final otherDisplayName = raw['toDisplayName'];
    if (otherUid is! String || otherDisplayName is! String) return null;
    return FriendRequest(
      otherUid: otherUid,
      otherDisplayName: otherDisplayName,
      otherPhotoUrl: raw['toPhotoUrl'] as String?,
      status:
          _statusFromString(raw['status'] as String?) ??
          FriendRequestStatus.pending,
      sentAt: _timestamp(raw['sentAt']),
    );
  }

  static DateTime? _timestamp(dynamic value) =>
      value is Timestamp ? value.toDate() : null;
}
