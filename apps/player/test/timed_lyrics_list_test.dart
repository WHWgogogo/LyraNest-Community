import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/lyrics/presentation/timed_lyrics_list.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/preferences/player_preferences.dart';

void main() {
  testWidgets('centers a distant active line when lyrics first open',
      (tester) async {
    final controller = _TestPlayerController(_FakeAudioPlayerBackend())
      ..emit(
        const PlaybackState(
          position: Duration(seconds: 70),
          duration: Duration(minutes: 2),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider.overrideWith((ref) => controller),
          inAppLyricsFontSizeProvider.overrideWithValue(20),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TimedLyricsList(
              trackId: 'long-lyrics',
              lyrics: _longLyrics.parsed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lyricsList = find.byType(ListView);
    final activeLine = find.text('Line 70');

    expect(activeLine, findsOneWidget);
    expect(
      tester.getCenter(activeLine).dy,
      closeTo(tester.getCenter(lyricsList).dy, 80),
    );
  });

  testWidgets('centers a distant active line with many wrapped lyrics',
      (tester) async {
    final controller = _TestPlayerController(_FakeAudioPlayerBackend())
      ..emit(
        const PlaybackState(
          position: Duration(seconds: 70),
          duration: Duration(minutes: 2),
        ),
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerControllerProvider.overrideWith((ref) => controller),
          inAppLyricsFontSizeProvider.overrideWithValue(20),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TimedLyricsList(
              trackId: 'variable-height-lyrics',
              lyrics: _variableHeightLyrics.parsed,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lyricsList = find.byType(ListView);
    final activeLine = find.text('Line 70');

    expect(activeLine, findsOneWidget);
    expect(
      tester.getCenter(activeLine).dy,
      closeTo(tester.getCenter(lyricsList).dy, 80),
    );
  });
}

final _longLyrics = Lyrics(
  trackId: 'long-lyrics',
  path: null,
  encoding: null,
  content: List<String>.generate(
    100,
    (index) {
      final minutes = (index ~/ 60).toString().padLeft(2, '0');
      final seconds = (index % 60).toString().padLeft(2, '0');
      return '[$minutes:$seconds.00]Line $index';
    },
  ).join('\n'),
);

final _variableHeightLyrics = Lyrics(
  trackId: 'variable-height-lyrics',
  path: null,
  encoding: null,
  content: List<String>.generate(
    100,
    (index) {
      final minutes = (index ~/ 60).toString().padLeft(2, '0');
      final seconds = (index % 60).toString().padLeft(2, '0');
      final text = index < 60
          ? 'Line $index ${List<String>.filled(32, 'wrapped lyric').join(' ')}'
          : 'Line $index';
      return '[$minutes:$seconds.00]$text';
    },
  ).join('\n'),
);

class _TestPlayerController extends PlayerController {
  _TestPlayerController(_FakeAudioPlayerBackend backend)
      : super(
          backend: backend,
          serverBaseUrl: () => 'http://localhost',
        );

  void emit(PlaybackState playback) {
    state = playback;
  }
}

class _FakeAudioPlayerBackend implements AudioPlayerBackend {
  @override
  Stream<bool> get buffering => Stream<bool>.empty();

  @override
  Stream<bool> get completed => Stream<bool>.empty();

  @override
  Stream<Duration> get duration => Stream<Duration>.empty();

  @override
  Stream<String> get errors => Stream<String>.empty();

  @override
  Stream<bool> get playing => Stream<bool>.empty();

  @override
  Stream<Duration> get position => Stream<Duration>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> open(Uri uri, {required bool play}) async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}
