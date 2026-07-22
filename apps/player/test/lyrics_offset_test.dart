import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/application/lyrics_offset_controller.dart';
import 'package:player/features/lyrics/data/lyrics_api.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/lyrics/domain/lyrics_offset.dart';
import 'package:player/features/lyrics/presentation/lyrics_page.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/application/queue_repository.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('persists an independent lyrics offset for each track', () async {
    final firstContainer = ProviderContainer();
    await firstContainer.read(lyricsOffsetProvider('track-a').future);
    await firstContainer.read(lyricsOffsetProvider('track-b').future);

    await firstContainer
        .read(lyricsOffsetProvider('track-a').notifier)
        .setOffset(const Duration(milliseconds: 500));
    await firstContainer
        .read(lyricsOffsetProvider('track-b').notifier)
        .setOffset(const Duration(milliseconds: -1000));

    expect(
      firstContainer.read(lyricsOffsetProvider('track-a')).requireValue,
      const Duration(milliseconds: 500),
    );
    expect(
      firstContainer.read(lyricsOffsetProvider('track-b')).requireValue,
      const Duration(milliseconds: -1000),
    );
    firstContainer.dispose();

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    expect(
      await secondContainer.read(lyricsOffsetProvider('track-a').future),
      const Duration(milliseconds: 500),
    );
    expect(
      await secondContainer.read(lyricsOffsetProvider('track-b').future),
      const Duration(milliseconds: -1000),
    );
  });

  test('positive offsets advance lyrics and preserve seek alignment', () {
    const offset = Duration(milliseconds: 500);

    expect(
      lyricsTimelinePosition(const Duration(seconds: 1), offset),
      const Duration(milliseconds: 1500),
    );
    expect(
      playbackPositionForLyricsTimestamp(const Duration(seconds: 1), offset),
      const Duration(milliseconds: 500),
    );
    expect(
      lyricsTimelinePosition(
        Duration.zero,
        const Duration(milliseconds: -500),
      ),
      Duration.zero,
    );
  });

  testWidgets('explains and adjusts the lyrics timing offset', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          lyricsApiProvider.overrideWithValue(_FakeLyricsApi()),
          playerControllerProvider.overrideWith(
            (ref) => _TestPlayerController(),
          ),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LyricsPage(trackId: 'track-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Positive values show lyrics earlier.'), findsOneWidget);
    expect(
      find.byTooltip('Show lyrics 0.5 seconds earlier'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lyrics-offset-value')))
          .data,
      '0.0 s · in sync',
    );

    await tester.tap(find.byKey(const ValueKey('increase-lyrics-offset')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('lyrics-offset-value')))
          .data,
      '+0.5 s · lyrics earlier',
    );
  });
}

class _TestPlayerController extends PlayerController {
  _TestPlayerController()
      : super(
          backend: _FakeAudioPlayerBackend(),
          serverBaseUrl: () => 'http://localhost',
          queueRepository: _MemoryQueueRepository(),
        );
}

class _MemoryQueueRepository implements QueueRepository {
  @override
  Future<void> clearQueue() async {}

  @override
  Future<List<Track>> loadQueue() async => const [];

  @override
  Future<void> saveQueue(Iterable<Track> queue) async {}
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

class _FakeLyricsApi extends LyricsApi {
  _FakeLyricsApi() : super(Dio());

  @override
  Future<Lyrics> fetchLyrics(String trackId) async {
    return Lyrics(
      trackId: trackId,
      path: null,
      encoding: null,
      content: '[00:00.00]First line',
    );
  }
}
