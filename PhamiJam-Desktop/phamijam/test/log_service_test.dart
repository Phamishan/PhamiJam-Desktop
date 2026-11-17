import 'package:flutter_test/flutter_test.dart';
import 'package:phamijam/services/log_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('report has header, snapshots and redacts secrets', () async {
    await LogService.instance.init();
    LogService.instance.registerSnapshot('Player', () => 'track: test song');

    Log.i('test', 'plain message');
    Log.i(
      'test',
      'Authorization: Bearer abc.def-123 and '
          'https://example.com/cb?access_token=SECRET123&x=1 and '
          'email me at someone@example.com '
          'stream https://rr1---sn-abc.googlevideo.com/videoplayback?sig=zzz '
          'key AIzaSyA1234567890abcdefghijKLMNOP statusCode=401',
    );
    Log.e('test', 'boom', StateError('bad'), StackTrace.current);

    final report = await LogService.instance.buildReport();
    expect(report, contains('PhamiJam log report'));
    expect(report, contains('--- Player ---'));
    expect(report, contains('track: test song'));
    expect(report, contains('[I][test] plain message'));
    expect(report, contains('[E][test] boom'));
    expect(report, isNot(contains('abc.def-123')));
    expect(report, isNot(contains('SECRET123')));
    expect(report, isNot(contains('someone@example.com')));
    expect(report, contains('s***@example.com'));
    expect(report, contains('<stream-url>'));
    expect(report, isNot(contains('AIzaSyA1234567890')));
    expect(report, contains('statusCode=401'));
  });

  test('report is capped but keeps the header and newest lines', () async {
    for (var i = 0; i < 400; i++) {
      Log.i('spam', 'line number $i with some padding text to make it longer');
    }
    Log.i('spam', 'THE-NEWEST-LINE');
    final report = await LogService.instance.buildReport(maxChars: 3000);
    expect(report.length, lessThanOrEqualTo(3100));
    expect(report, contains('PhamiJam log report'));
    expect(report, contains('THE-NEWEST-LINE'));
    expect(report, contains('older lines omitted'));
  });
}
