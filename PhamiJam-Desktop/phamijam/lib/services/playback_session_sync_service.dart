import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

enum RemoteCommandType { play, pause, next, previous, setVolume }

class RemoteCommand {
  final String id;
  final RemoteCommandType type;
  final double? value;

  const RemoteCommand({required this.id, required this.type, this.value});

  static RemoteCommand? fromDoc(String id, Map<String, dynamic> data) {
    final typeName = data['type'];
    if (typeName is! String) return null;
    final type = RemoteCommandType.values.where((t) => t.name == typeName);
    if (type.isEmpty) return null;
    final value = data['value'];
    return RemoteCommand(
      id: id,
      type: type.first,
      value: value is num ? value.toDouble() : null,
    );
  }
}

class RemoteSession {
  final List<Map<String, dynamic>> queue;
  final int queueIndex;
  final Duration position;
  final bool isPlaying;
  final double volume;
  final bool shuffle;
  final String repeatMode;
  final String deviceName;
  final DateTime updatedAt;

  const RemoteSession({
    required this.queue,
    required this.queueIndex,
    required this.position,
    required this.isPlaying,
    required this.volume,
    required this.shuffle,
    required this.repeatMode,
    required this.deviceName,
    required this.updatedAt,
  });

  Map<String, dynamic>? get currentTrack =>
      (queueIndex >= 0 && queueIndex < queue.length) ? queue[queueIndex] : null;

  bool get isLive =>
      isPlaying &&
      DateTime.now().difference(updatedAt) < const Duration(minutes: 2);
}

class PlaybackSessionSyncService {
  PlaybackSessionSyncService._();

  static const String _selfId = 'desktop';
  static const String _selfName = 'Desktop';
  static const String _otherId = 'phone';

  static CollectionReference<Map<String, dynamic>>? get _sessionCollection {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('playbackSession');
  }

  static DocumentReference<Map<String, dynamic>>? get _ownDoc =>
      _sessionCollection?.doc(_selfId);

  static DocumentReference<Map<String, dynamic>>? get _otherDoc =>
      _sessionCollection?.doc(_otherId);

  static Map<String, dynamic> _trackToJson(Map<String, dynamic> item) {
    final videoId = item['videoId'] as String?;
    final durationSeconds = item['durationSeconds'] as int?;
    return {
      'v': videoId,
      't': (item['songName'] ?? item['title'] ?? '').toString(),
      'a': (item['artistName'] ?? item['artist'] ?? '').toString(),
      'th': videoId == null || videoId.isEmpty
          ? ''
          : 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      'd': (durationSeconds ?? 0) * 1000,
      'c': item['artistId'] as String?,
    };
  }

  static Map<String, dynamic>? _trackFromJson(dynamic json) {
    if (json is! Map) return null;
    final videoId = json['v'];
    if (videoId is! String || videoId.isEmpty) return null;
    return {
      'videoId': videoId,
      'songName': json['t'] is String ? json['t'] as String : '',
      'artistName': json['a'] is String ? json['a'] as String : '',
      'artistId': json['c'] is String ? json['c'] as String : null,
      'durationSeconds': json['d'] is int ? (json['d'] as int) ~/ 1000 : 0,
    };
  }

  static Future<void> pushSession({
    required List<Map<String, dynamic>> queue,
    required int queueIndex,
    required Duration position,
    required bool isPlaying,
    required double volume,
    required bool shuffle,
    required String repeatMode,
  }) async {
    final doc = _ownDoc;
    if (doc == null) return;
    if (queueIndex < 0 || queueIndex >= queue.length) return;
    final currentVideoId = queue[queueIndex]['videoId'] as String?;
    if (currentVideoId == null || currentVideoId.isEmpty) return;

    final syncableQueue = queue
        .where((item) => (item['videoId'] as String?)?.isNotEmpty ?? false)
        .toList();
    final syncableIndex = syncableQueue.indexWhere(
      (item) => item['videoId'] == currentVideoId,
    );
    if (syncableIndex < 0) return;

    try {
      await doc.set({
        'queue': syncableQueue.map(_trackToJson).toList(),
        'queueIndex': syncableIndex,
        'positionMs': position.inMilliseconds,
        'isPlaying': isPlaying,
        'volume': volume,
        'shuffle': shuffle,
        'repeatMode': repeatMode,
        'deviceName': _selfName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('PlaybackSessionSyncService: push failed: $error');
    }
  }

  static Stream<RemoteSession?> watchOtherSession() {
    final doc = _otherDoc;
    if (doc == null) return Stream.value(null);
    return doc.snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return null;

      final queue = ((data['queue'] as List?) ?? [])
          .map(_trackFromJson)
          .whereType<Map<String, dynamic>>()
          .toList();
      if (queue.isEmpty) return null;
      final queueIndex = data['queueIndex'] as int? ?? 0;
      if (queueIndex < 0 || queueIndex >= queue.length) return null;

      final updatedAt = data['updatedAt'];
      if (updatedAt is! Timestamp) return null;

      return RemoteSession(
        queue: queue,
        queueIndex: queueIndex,
        position: Duration(milliseconds: data['positionMs'] as int? ?? 0),
        isPlaying: data['isPlaying'] as bool? ?? false,
        volume: (data['volume'] as num?)?.toDouble() ?? 0.8,
        shuffle: data['shuffle'] as bool? ?? false,
        repeatMode: data['repeatMode'] as String? ?? 'off',
        deviceName: data['deviceName'] as String? ?? 'Other device',
        updatedAt: updatedAt.toDate(),
      );
    });
  }

  static Future<void> sendCommand(
    RemoteCommandType type, {
    double? value,
  }) async {
    final commands = _otherDoc?.collection('commands');
    if (commands == null) return;
    try {
      await commands.add({
        'type': type.name,
        'value': ?value,
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (error) {
      debugPrint('PlaybackSessionSyncService: sendCommand failed: $error');
    }
  }

  static Stream<List<RemoteCommand>> watchIncomingCommands() {
    final commands = _ownDoc?.collection('commands');
    if (commands == null) return const Stream.empty();
    return commands
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) => snapshot.docChanges
              .where((change) => change.type == DocumentChangeType.added)
              .map(
                (change) =>
                    RemoteCommand.fromDoc(change.doc.id, change.doc.data()!),
              )
              .whereType<RemoteCommand>()
              .toList(),
        );
  }

  static Future<void> ackCommand(String commandDocId) async {
    final commands = _ownDoc?.collection('commands');
    if (commands == null) return;
    try {
      await commands.doc(commandDocId).delete();
    } catch (error) {
      debugPrint('PlaybackSessionSyncService: ackCommand failed: $error');
    }
  }
}
