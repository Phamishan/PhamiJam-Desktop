import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class FriendsService {
  FriendsService._();

  static User? get _currentUser => FirebaseAuth.instance.currentUser;

  static CollectionReference<Map<String, dynamic>> _userCollection(
    String uid,
    String name,
  ) => FirebaseFirestore.instance.collection('users').doc(uid).collection(name);

  static CollectionReference<Map<String, dynamic>>? get _receivedForMe {
    final uid = _currentUser?.uid;
    if (uid == null) return null;
    return _userCollection(uid, 'friendRequestsReceived');
  }

  static CollectionReference<Map<String, dynamic>>? get _sentByMe {
    final uid = _currentUser?.uid;
    if (uid == null) return null;
    return _userCollection(uid, 'friendRequestsSent');
  }

  static CollectionReference<Map<String, dynamic>>? get _myFriends {
    final uid = _currentUser?.uid;
    if (uid == null) return null;
    return _userCollection(uid, 'friends');
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchReceivedRequests() {
    final collection = _receivedForMe;
    if (collection == null) return const Stream.empty();
    return collection
        .where('status', isEqualTo: 'pending')
        .orderBy('sentAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchSentRequests() {
    final collection = _sentByMe;
    if (collection == null) return const Stream.empty();
    return collection
        .where('status', isEqualTo: 'pending')
        .orderBy('sentAt', descending: true)
        .snapshots();
  }

  static Stream<QuerySnapshot<Map<String, dynamic>>> watchFriends() {
    final collection = _myFriends;
    if (collection == null) return const Stream.empty();
    return collection.orderBy('becameFriendsAt', descending: true).snapshots();
  }

  static Future<void> sendFriendRequest(
    String toUid, {
    required String toDisplayName,
    String? toPhotoUrl,
  }) async {
    final me = _currentUser;
    if (me == null || toUid.isEmpty || toUid == me.uid) return;
    final batch = FirebaseFirestore.instance.batch();
    final firestore = FirebaseFirestore.instance;
    batch.set(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friendRequestsSent')
          .doc(toUid),
      {
        'toUid': toUid,
        'toDisplayName': toDisplayName,
        'toPhotoUrl': toPhotoUrl,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      firestore
          .collection('users')
          .doc(toUid)
          .collection('friendRequestsReceived')
          .doc(me.uid),
      {
        'fromUid': me.uid,
        'fromDisplayName': me.displayName ?? 'PhamiJam User',
        'fromPhotoUrl': me.photoURL,
        'status': 'pending',
        'sentAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  static Future<void> cancelSentRequest(String toUid) async {
    final me = _currentUser;
    if (me == null) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.delete(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friendRequestsSent')
          .doc(toUid),
    );
    batch.delete(
      firestore
          .collection('users')
          .doc(toUid)
          .collection('friendRequestsReceived')
          .doc(me.uid),
    );
    await batch.commit();
  }

  static Future<void> acceptFriendRequest(
    String fromUid, {
    required String fromDisplayName,
    String? fromPhotoUrl,
  }) async {
    final me = _currentUser;
    if (me == null) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();

    batch.delete(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friendRequestsReceived')
          .doc(fromUid),
    );
    batch.delete(
      firestore
          .collection('users')
          .doc(fromUid)
          .collection('friendRequestsSent')
          .doc(me.uid),
    );
    batch.set(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friends')
          .doc(fromUid),
      {
        'friendUid': fromUid,
        'displayName': fromDisplayName,
        'photoUrl': fromPhotoUrl,
        'becameFriendsAt': FieldValue.serverTimestamp(),
      },
    );
    batch.set(
      firestore
          .collection('users')
          .doc(fromUid)
          .collection('friends')
          .doc(me.uid),
      {
        'friendUid': me.uid,
        'displayName': me.displayName ?? 'PhamiJam User',
        'photoUrl': me.photoURL,
        'becameFriendsAt': FieldValue.serverTimestamp(),
      },
    );
    await batch.commit();
  }

  static Future<void> declineFriendRequest(String fromUid) async {
    final me = _currentUser;
    if (me == null) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.delete(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friendRequestsReceived')
          .doc(fromUid),
    );
    batch.delete(
      firestore
          .collection('users')
          .doc(fromUid)
          .collection('friendRequestsSent')
          .doc(me.uid),
    );
    await batch.commit();
  }

  static Future<void> unfriend(String friendUid) async {
    final me = _currentUser;
    if (me == null) return;
    final firestore = FirebaseFirestore.instance;
    final batch = firestore.batch();
    batch.delete(
      firestore
          .collection('users')
          .doc(me.uid)
          .collection('friends')
          .doc(friendUid),
    );
    batch.delete(
      firestore
          .collection('users')
          .doc(friendUid)
          .collection('friends')
          .doc(me.uid),
    );
    await batch.commit();
  }
}
