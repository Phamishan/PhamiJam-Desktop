class PlayEvent {
  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final DateTime startedAt;
  final int listenedMs;

  const PlayEvent({
    required this.videoId,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    required this.startedAt,
    required this.listenedMs,
  });

  Duration get listened => Duration(milliseconds: listenedMs);

  String get docId {
    final safeId = videoId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final trimmed = safeId.length > 80
        ? safeId.substring(safeId.length - 80)
        : safeId;
    return '${startedAt.millisecondsSinceEpoch}_$trimmed';
  }

  Map<String, dynamic> toJson() => {
    'v': videoId,
    't': title,
    'a': artist,
    'th': thumbnailUrl,
    's': startedAt.millisecondsSinceEpoch,
    'l': listenedMs,
  };

  static PlayEvent? fromJson(Map<String, dynamic> json) {
    final videoId = json['v'];
    final startedAtMs = json['s'];
    if (videoId is! String || startedAtMs is! int) return null;
    return PlayEvent(
      videoId: videoId,
      title: json['t'] is String ? json['t'] as String : '',
      artist: json['a'] is String ? json['a'] as String : '',
      thumbnailUrl: json['th'] is String ? json['th'] as String : '',
      startedAt: DateTime.fromMillisecondsSinceEpoch(startedAtMs),
      listenedMs: json['l'] is int ? json['l'] as int : 0,
    );
  }
}
