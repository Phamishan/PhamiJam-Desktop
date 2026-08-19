import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:phamijam/models/friend.dart';
import 'package:phamijam/models/friend_request.dart';
import 'package:phamijam/services/friends_service.dart';

class FriendsProvider extends ChangeNotifier {
  List<Friend> friends = [];
  List<FriendRequest> received = [];
  List<FriendRequest> sent = [];
  bool hasLoadedOnce = false;

  StreamSubscription? _friendsSub;
  StreamSubscription? _receivedSub;
  StreamSubscription? _sentSub;

  void start() {
    _friendsSub?.cancel();
    _receivedSub?.cancel();
    _sentSub?.cancel();

    _friendsSub = FriendsService.watchFriends().listen((snapshot) {
      friends = snapshot.docs
          .map((doc) => Friend.fromMap(doc.id, doc.data()))
          .whereType<Friend>()
          .toList();
      hasLoadedOnce = true;
      notifyListeners();
    });
    _receivedSub = FriendsService.watchReceivedRequests().listen((snapshot) {
      received = snapshot.docs
          .map((doc) => FriendRequest.fromReceivedMap(doc.data()))
          .whereType<FriendRequest>()
          .toList();
      notifyListeners();
    });
    _sentSub = FriendsService.watchSentRequests().listen((snapshot) {
      sent = snapshot.docs
          .map((doc) => FriendRequest.fromSentMap(doc.data()))
          .whereType<FriendRequest>()
          .toList();
      notifyListeners();
    });
  }

  void stop() {
    _friendsSub?.cancel();
    _receivedSub?.cancel();
    _sentSub?.cancel();
    friends = [];
    received = [];
    sent = [];
    hasLoadedOnce = false;
  }

  bool isFriend(String uid) => friends.any((f) => f.uid == uid);
  bool hasSentRequestTo(String uid) => sent.any((r) => r.otherUid == uid);
  bool hasReceivedRequestFrom(String uid) =>
      received.any((r) => r.otherUid == uid);

  Future<void> sendFriendRequest(
    String toUid, {
    required String toDisplayName,
    String? toPhotoUrl,
  }) async {
    final previous = sent;
    sent = [
      FriendRequest(
        otherUid: toUid,
        otherDisplayName: toDisplayName,
        otherPhotoUrl: toPhotoUrl,
      ),
      ...sent,
    ];
    notifyListeners();
    try {
      await FriendsService.sendFriendRequest(
        toUid,
        toDisplayName: toDisplayName,
        toPhotoUrl: toPhotoUrl,
      );
    } catch (error) {
      sent = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> cancelSentRequest(String toUid) async {
    final previous = sent;
    sent = sent.where((r) => r.otherUid != toUid).toList();
    notifyListeners();
    try {
      await FriendsService.cancelSentRequest(toUid);
    } catch (error) {
      sent = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> acceptFriendRequest(FriendRequest request) async {
    final previousReceived = received;
    final previousFriends = friends;
    received = received.where((r) => r.otherUid != request.otherUid).toList();
    friends = [
      Friend(
        uid: request.otherUid,
        displayName: request.otherDisplayName,
        photoUrl: request.otherPhotoUrl,
      ),
      ...friends,
    ];
    notifyListeners();
    try {
      await FriendsService.acceptFriendRequest(
        request.otherUid,
        fromDisplayName: request.otherDisplayName,
        fromPhotoUrl: request.otherPhotoUrl,
      );
    } catch (error) {
      received = previousReceived;
      friends = previousFriends;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> declineFriendRequest(String fromUid) async {
    final previous = received;
    received = received.where((r) => r.otherUid != fromUid).toList();
    notifyListeners();
    try {
      await FriendsService.declineFriendRequest(fromUid);
    } catch (error) {
      received = previous;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> unfriend(String friendUid) async {
    final previous = friends;
    friends = friends.where((f) => f.uid != friendUid).toList();
    notifyListeners();
    try {
      await FriendsService.unfriend(friendUid);
    } catch (error) {
      friends = previous;
      notifyListeners();
      rethrow;
    }
  }

  @override
  void dispose() {
    _friendsSub?.cancel();
    _receivedSub?.cancel();
    _sentSub?.cancel();
    super.dispose();
  }
}
