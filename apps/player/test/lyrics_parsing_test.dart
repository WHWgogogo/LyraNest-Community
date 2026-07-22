import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';

void main() {
  test('parses sorted LRC timestamps and repeated timestamp tags', () {
    final lyrics = Lyrics(
      trackId: 'track-1',
      path: null,
      encoding: null,
      content: '''
[ar:Artist]
[00:05.00]Later
[00:01.25][00:03.50]Repeated
''',
    ).parsed;

    expect(lyrics.lines.map((line) => line.text), [
      'Repeated',
      'Repeated',
      'Later',
    ]);
    expect(lyrics.textAt(const Duration(seconds: 2)), 'Repeated');
    expect(lyrics.textAt(const Duration(seconds: 4)), 'Repeated');
    expect(lyrics.textAt(const Duration(seconds: 6)), 'Later');
    expect(lyrics.activeLineIndexAt(const Duration(seconds: 2)), 0);
    expect(lyrics.activeLineIndexAt(const Duration(seconds: 4)), 1);
    expect(lyrics.activeLineIndexAt(const Duration(seconds: 6)), 2);
  });

  test('applies LRC offset and shows the first lyric before its timestamp', () {
    final lyrics = Lyrics(
      trackId: 'track-1',
      path: null,
      encoding: null,
      content: '[offset:500]\n[00:01.00]First\n[00:02.00]Second',
    ).parsed;

    expect(lyrics.lines.first.timestamp, const Duration(milliseconds: 1500));
    expect(lyrics.textAt(Duration.zero), 'First');
    expect(lyrics.textAt(const Duration(milliseconds: 1600)), 'First');
    expect(lyrics.textAt(const Duration(milliseconds: 2500)), 'Second');
    expect(lyrics.activeLineIndexAt(Duration.zero), 0);
    expect(lyrics.activeLineIndexAt(const Duration(milliseconds: 2500)), 1);
  });

  test('keeps untimed lyrics readable', () {
    final lyrics = Lyrics(
      trackId: 'track-1',
      path: null,
      encoding: null,
      content: 'First line\n\nSecond line',
    ).parsed;

    expect(lyrics.hasTimestamps, isFalse);
    expect(lyrics.displayText, 'First line\nSecond line');
    expect(
        lyrics.textAt(const Duration(seconds: 10)), 'First line\nSecond line');
    expect(lyrics.activeLineIndexAt(const Duration(seconds: 10)), isNull);
  });
}
