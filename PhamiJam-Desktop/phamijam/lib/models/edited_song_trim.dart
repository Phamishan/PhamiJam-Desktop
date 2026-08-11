class EditedSongTrim {
  final String videoId;
  final int startMs;
  final int endMs;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final String? playlistId;

  const EditedSongTrim({
    required this.videoId,
    required this.startMs,
    required this.endMs,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.playlistId,
  });

  Duration get start => Duration(milliseconds: startMs);
  Duration get end => Duration(milliseconds: endMs);
}
