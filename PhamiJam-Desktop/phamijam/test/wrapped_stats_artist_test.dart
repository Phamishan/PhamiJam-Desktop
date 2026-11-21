import 'package:flutter_test/flutter_test.dart';
import 'package:phamijam/models/play_event.dart';
import 'package:phamijam/services/wrapped_stats.dart';

PlayEvent _play(String id, String artist, int minute) => PlayEvent(
  videoId: id,
  title: 'Song $id',
  artist: artist,
  thumbnailUrl: '',
  startedAt: DateTime(2026, 5, 1, 12, minute),
  listenedMs: 60000,
);

void main() {
  test('cleans Topic and VEVO suffixes', () {
    expect(cleanArtistName('Polo G - Topic'), 'Polo G');
    expect(cleanArtistName('PoloGVEVO'), 'PoloG');
    expect(cleanArtistName('Drake VEVO'), 'Drake');
    expect(cleanArtistName('Drake'), 'Drake');
    expect(cleanArtistName('- Topic'), '- Topic');
  });

  test('merges channel variants into one artist with the clean name', () {
    final stats = WrappedStats.fromEvents([
      _play('a', 'Polo G', 1),
      _play('b', 'Polo G - Topic', 2),
      _play('c', 'PoloGVEVO', 3),
      _play('d', 'Drake', 4),
    ]);
    expect(stats.uniqueArtists, 2);
    expect(stats.topArtists.first.name, 'Polo G');
    expect(stats.topArtists.first.plays, 3);
  });
}
