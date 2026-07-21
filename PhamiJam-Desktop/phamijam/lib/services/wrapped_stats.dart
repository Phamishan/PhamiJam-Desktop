import 'package:phamijam/models/play_event.dart';

class WrappedEntry {
  final String name;
  final String subtitle;
  final String thumbnailUrl;
  final int plays;
  final int listenedMs;

  const WrappedEntry({
    required this.name,
    required this.subtitle,
    required this.thumbnailUrl,
    required this.plays,
    required this.listenedMs,
  });

  int get minutes => listenedMs ~/ 60000;
}

class WrappedStats {
  final int totalPlays;
  final int totalMs;
  final int uniqueTracks;
  final int uniqueArtists;
  final List<WrappedEntry> topTracks;
  final List<WrappedEntry> topArtists;
  final String busiestDay;
  final String busiestHour;
  final int longestStreakDays;
  final int topArtistPercent;

  const WrappedStats({
    required this.totalPlays,
    required this.totalMs,
    required this.uniqueTracks,
    required this.uniqueArtists,
    required this.topTracks,
    required this.topArtists,
    required this.busiestDay,
    required this.busiestHour,
    required this.longestStreakDays,
    required this.topArtistPercent,
  });

  int get totalMinutes => totalMs ~/ 60000;
  bool get isEmpty => totalPlays == 0;

  static const List<String> _dayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  static String _formatHour(int hour) {
    final h = hour % 12 == 0 ? 12 : hour % 12;
    return '$h ${hour < 12 ? 'AM' : 'PM'}';
  }

  factory WrappedStats.fromEvents(List<PlayEvent> events) {
    if (events.isEmpty) {
      return const WrappedStats(
        totalPlays: 0,
        totalMs: 0,
        uniqueTracks: 0,
        uniqueArtists: 0,
        topTracks: [],
        topArtists: [],
        busiestDay: '',
        busiestHour: '',
        longestStreakDays: 0,
        topArtistPercent: 0,
      );
    }

    var totalMs = 0;
    final byTrack = <String, List<PlayEvent>>{};
    final byArtist = <String, List<PlayEvent>>{};
    final msByWeekday = <int, int>{};
    final msByHour = <int, int>{};
    final daysListened = <int>{};

    for (final event in events) {
      totalMs += event.listenedMs;
      byTrack.putIfAbsent(event.videoId, () => []).add(event);
      if (event.artist.isNotEmpty) {
        byArtist.putIfAbsent(event.artist, () => []).add(event);
      }
      final weekday = event.startedAt.weekday;
      msByWeekday[weekday] = (msByWeekday[weekday] ?? 0) + event.listenedMs;
      final hour = event.startedAt.hour;
      msByHour[hour] = (msByHour[hour] ?? 0) + event.listenedMs;
      final day = event.startedAt;
      daysListened.add(day.year * 10000 + day.month * 100 + day.day);
    }

    List<WrappedEntry> rank(
      Map<String, List<PlayEvent>> groups,
      WrappedEntry Function(String key, List<PlayEvent> plays) build,
    ) {
      final entries = groups.entries.map((e) => build(e.key, e.value)).toList();
      entries.sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0 ? byPlays : b.listenedMs.compareTo(a.listenedMs);
      });
      return entries.take(5).toList();
    }

    int sumMs(List<PlayEvent> plays) =>
        plays.fold(0, (sum, e) => sum + e.listenedMs);

    final topTracks = rank(byTrack, (videoId, plays) {
      final latest = plays.last;
      return WrappedEntry(
        name: latest.title,
        subtitle: latest.artist,
        thumbnailUrl: latest.thumbnailUrl,
        plays: plays.length,
        listenedMs: sumMs(plays),
      );
    });

    final topArtists = rank(byArtist, (artist, plays) {
      final latest = plays.last;
      return WrappedEntry(
        name: artist,
        subtitle: '${plays.length} plays',
        thumbnailUrl: latest.thumbnailUrl,
        plays: plays.length,
        listenedMs: sumMs(plays),
      );
    });

    int busiestKey(Map<int, int> map) =>
        map.entries.reduce((a, b) => b.value > a.value ? b : a).key;

    final sortedDays = daysListened.toList()..sort();
    var longestStreak = 0;
    var streak = 0;
    DateTime? previousDay;
    for (final key in sortedDays) {
      final day = DateTime(key ~/ 10000, (key ~/ 100) % 100, key % 100);
      if (previousDay != null && day.difference(previousDay).inDays == 1) {
        streak++;
      } else {
        streak = 1;
      }
      if (streak > longestStreak) longestStreak = streak;
      previousDay = day;
    }

    final topArtistMs = topArtists.isEmpty ? 0 : topArtists.first.listenedMs;

    return WrappedStats(
      totalPlays: events.length,
      totalMs: totalMs,
      uniqueTracks: byTrack.length,
      uniqueArtists: byArtist.length,
      topTracks: topTracks,
      topArtists: topArtists,
      busiestDay: _dayNames[busiestKey(msByWeekday) - 1],
      busiestHour: _formatHour(busiestKey(msByHour)),
      longestStreakDays: longestStreak,
      topArtistPercent: totalMs == 0 ? 0 : (topArtistMs * 100 ~/ totalMs),
    );
  }
}
