import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/data/lyrics_api.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/player/presentation/now_playing_lyrics.dart';
import 'package:player/features/preferences/player_preferences.dart';

void main() {
  testWidgets('compact lyrics show previous, centered current, and next lines',
      (tester) async {
    final backend = _FakeAudioPlayerBackend();
    final controller = _TestPlayerController(backend)
      ..emit(
        const PlaybackState(
          position: Duration(milliseconds: 1500),
          duration: Duration(seconds: 10),
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        lyrics: _lyrics,
        inAppLyricsFontSize: 22,
        child: const SizedBox(
          width: 300,
          child: NowPlayingLyrics(
            trackId: 'track-1',
            textAlign: TextAlign.left,
            activeColor: Colors.white,
            inactiveColor: Colors.grey,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('First'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Fourth'), findsNothing);
    expect(find.text('Fifth'), findsNothing);

    final currentLine = find.byKey(const ValueKey(('compact-lyric', 1)));
    final previousLine = find.byKey(const ValueKey(('compact-lyric', 0)));
    final nextLine = find.byKey(const ValueKey(('compact-lyric', 2)));
    final currentStyles = tester.widgetList<AnimatedDefaultTextStyle>(
      find.descendant(
        of: currentLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    final previousStyles = tester.widgetList<AnimatedDefaultTextStyle>(
      find.descendant(
        of: previousLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    final nextStyles = tester.widgetList<AnimatedDefaultTextStyle>(
      find.descendant(
        of: nextLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    final currentAlignments = tester.widgetList<Align>(
      find.descendant(of: currentLine, matching: find.byType(Align)),
    );

    expect(
      currentAlignments.any((widget) => widget.alignment == Alignment.center),
      isTrue,
    );
    expect(
      currentStyles.any((widget) => widget.style.fontSize == 26),
      isTrue,
    );
    expect(
      previousStyles.any((widget) => widget.style.fontSize == 22),
      isTrue,
    );
    expect(
      nextStyles.any((widget) => widget.style.fontSize == 22),
      isTrue,
    );

    await tester.tap(find.text('Third'));
    await tester.pump();

    expect(backend.seekPositions, [const Duration(seconds: 2)]);
  });

  testWidgets('expanded lyrics scroll and highlight the active line',
      (tester) async {
    final backend = _FakeAudioPlayerBackend();
    final controller = _TestPlayerController(backend)
      ..emit(
        const PlaybackState(
          position: Duration(milliseconds: 3500),
          duration: Duration(seconds: 10),
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        lyrics: _lyrics,
        child: const SizedBox(
          width: 500,
          height: 360,
          child: NowPlayingLyrics(
            trackId: 'track-1',
            textAlign: TextAlign.right,
            activeColor: Colors.orange,
            inactiveColor: Colors.grey,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('now-playing-lyrics-list')),
      findsOneWidget,
    );
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Sixth'), findsOneWidget);

    final activeLine = find.byKey(
      const ValueKey(('expanded-lyric', 3, true)),
    );
    final activeStyles = tester.widgetList<AnimatedDefaultTextStyle>(
      find.descendant(
        of: activeLine,
        matching: find.byType(AnimatedDefaultTextStyle),
      ),
    );
    expect(
      activeStyles.any((widget) => widget.style.color == Colors.orange),
      isTrue,
    );

    final activeAlignments = tester.widgetList<Align>(
      find.descendant(of: activeLine, matching: find.byType(Align)),
    );
    expect(
      activeAlignments.any(
        (widget) => widget.alignment == Alignment.centerRight,
      ),
      isTrue,
    );
  });

  testWidgets('large double-line lyrics expand instead of clipping',
      (tester) async {
    final backend = _FakeAudioPlayerBackend();
    final controller = _TestPlayerController(backend)
      ..emit(
        const PlaybackState(
          position: Duration.zero,
          duration: Duration(seconds: 10),
        ),
      );
    const lyricText =
        'A long current lyric line that wraps cleanly across two rows.';

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        lyrics: const Lyrics(
          trackId: 'large-lyrics',
          path: null,
          encoding: null,
          content: '[00:00.00]$lyricText',
        ),
        inAppLyricsFontSize: 36,
        child: const SizedBox(
          width: 320,
          height: 260,
          child: NowPlayingLyrics(
            trackId: 'large-lyrics',
            textAlign: TextAlign.center,
            activeColor: Colors.white,
            inactiveColor: Colors.grey,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final activeLine = find.byKey(const ValueKey(('expanded-lyric', 0, true)));
    expect(activeLine, findsOneWidget);
    expect(tester.getSize(activeLine).height, greaterThan(100));
    expect(find.text(lyricText), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expanded lyrics center a distant active line on first build',
      (tester) async {
    final backend = _FakeAudioPlayerBackend();
    final controller = _TestPlayerController(backend)
      ..emit(
        const PlaybackState(
          position: Duration(seconds: 70),
          duration: Duration(minutes: 2),
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        lyrics: _longLyrics,
        child: const SizedBox(
          width: 360,
          height: 320,
          child: NowPlayingLyrics(
            trackId: 'long-lyrics',
            textAlign: TextAlign.center,
            activeColor: Colors.white,
            inactiveColor: Colors.grey,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lyricsList = find.byKey(const ValueKey('now-playing-lyrics-list'));
    final activeLine = find.byKey(
      const ValueKey(('expanded-lyric', 70, true)),
    );

    expect(activeLine, findsOneWidget);
    expect(
      tester.getCenter(activeLine).dy,
      closeTo(tester.getCenter(lyricsList).dy, 60),
    );
  });

  testWidgets('expanded lyrics center a distant active line with wrapped lines',
      (tester) async {
    final backend = _FakeAudioPlayerBackend();
    final controller = _TestPlayerController(backend)
      ..emit(
        const PlaybackState(
          position: Duration(seconds: 70),
          duration: Duration(minutes: 2),
        ),
      );

    await tester.pumpWidget(
      _TestApp(
        controller: controller,
        lyrics: _variableHeightLyrics,
        inAppLyricsFontSize: 36,
        child: const SizedBox(
          width: 260,
          height: 320,
          child: NowPlayingLyrics(
            trackId: 'variable-height-lyrics',
            textAlign: TextAlign.center,
            activeColor: Colors.white,
            inactiveColor: Colors.grey,
            expanded: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final lyricsList = find.byKey(const ValueKey('now-playing-lyrics-list'));
    final activeLine = find.byKey(
      const ValueKey(('expanded-lyric', 70, true)),
    );

    expect(activeLine, findsOneWidget);
    expect(
      tester.getCenter(activeLine).dy,
      closeTo(tester.getCenter(lyricsList).dy, 60),
    );
  });
}

const _lyrics = Lyrics(
  trackId: 'track-1',
  path: null,
  encoding: null,
  content: '''
[00:00.00]First
[00:01.00]Second
[00:02.00]Third
[00:03.00]Fourth
[00:04.00]Fifth
[00:05.00]Sixth
''',
);

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
          ? 'Line $index ${List<String>.filled(18, 'wrapped lyric').join(' ')}'
          : 'Line $index';
      return '[$minutes:$seconds.00]$text';
    },
  ).join('\n'),
);

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.controller,
    required this.lyrics,
    required this.child,
    this.inAppLyricsFontSize = PlayerPreferences.defaultInAppLyricsFontSize,
  });

  final PlayerController controller;
  final Lyrics lyrics;
  final Widget child;
  final double inAppLyricsFontSize;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        lyricsApiProvider.overrideWithValue(_FakeLyricsApi(lyrics)),
        playerControllerProvider.overrideWith((ref) => controller),
        inAppLyricsFontSizeProvider.overrideWithValue(inAppLyricsFontSize),
      ],
      child: MaterialApp(
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }
}

class _FakeLyricsApi extends LyricsApi {
  _FakeLyricsApi(this.lyrics) : super(Dio());

  final Lyrics lyrics;

  @override
  Future<Lyrics> fetchLyrics(String trackId) async => lyrics;
}

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
  final seekPositions = <Duration>[];

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
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> stop() async {}
}
