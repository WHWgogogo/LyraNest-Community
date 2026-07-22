import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/config/server_config.dart';
import 'package:player/core/config/server_config_controller.dart';
import 'package:player/features/collections/application/collections_controller.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/application/queue_repository.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/player/presentation/queue_panel.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('add sheet searches title, artist, album, and genre',
      (tester) async {
    final controller = _TestPlayerController();
    await _pumpQueuePanel(
      tester,
      controller: controller,
      tracks: const [
        Track(id: 'title', title: 'Midnight Drive'),
        Track(id: 'artist', title: 'Other Song', artist: 'Nova'),
        Track(id: 'album', title: 'Another Song', album: 'Moonlight'),
        Track(
          id: 'genre',
          title: 'Different Song',
          genres: ['Synthwave'],
        ),
      ],
    );

    await tester.tap(find.byKey(const ValueKey('queue-add-tracks')));
    await tester.pumpAndSettle();

    final search = find.byKey(const ValueKey('queue-add-search'));
    expect(search, findsOneWidget);

    await _expectOnlyMatchingTrack(
      tester,
      search: search,
      query: 'midnight',
      matchingTitle: 'Midnight Drive',
    );
    await _expectOnlyMatchingTrack(
      tester,
      search: search,
      query: 'nova',
      matchingTitle: 'Other Song',
    );
    await _expectOnlyMatchingTrack(
      tester,
      search: search,
      query: 'moonlight',
      matchingTitle: 'Another Song',
    );
    await _expectOnlyMatchingTrack(
      tester,
      search: search,
      query: 'synthwave',
      matchingTitle: 'Different Song',
    );
  });

  testWidgets('current-track control is disabled without a current track',
      (tester) async {
    final controller = _TestPlayerController()
      ..emit(
        const PlaybackState(
          queue: [
            Track(id: 'queued', title: 'Queued'),
          ],
          currentIndex: 0,
        ),
      );
    await _pumpQueuePanel(tester, controller: controller);

    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('queue-locate-current')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('current-track control scrolls to the current item after reorder',
      (tester) async {
    final queue = List<Track>.generate(
      32,
      (index) => Track(id: 'track-$index', title: 'Track $index'),
    );
    final controller = _TestPlayerController()
      ..emit(
        PlaybackState(
          currentTrack: queue[1],
          queue: queue,
          currentIndex: 1,
        ),
      );
    await _pumpQueuePanel(tester, controller: controller);

    await controller.moveQueueItem(1, queue.length);
    await tester.pumpAndSettle();

    expect(controller.state.currentTrack?.id, 'track-1');
    expect(controller.state.currentIndex, queue.length - 1);

    final scrollable = tester.state<ScrollableState>(
      find.byType(Scrollable),
    );
    expect(scrollable.position.pixels, 0);

    await tester.tap(find.byKey(const ValueKey('queue-locate-current')));
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, greaterThan(0));
    expect(find.text('Track 1'), findsOneWidget);
  });

  testWidgets('automatically locates once without stealing later scrolling',
      (tester) async {
    final queue = List<Track>.generate(
      32,
      (index) => Track(id: 'track-$index', title: 'Track $index'),
    );
    final controller = _TestPlayerController()
      ..emit(
        PlaybackState(
          currentTrack: queue[24],
          queue: queue,
          currentIndex: 24,
        ),
      );
    await _pumpQueuePanel(tester, controller: controller);

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, greaterThan(0));

    scrollable.position.jumpTo(0);
    controller.emit(
      controller.state.copyWith(position: const Duration(seconds: 8)),
    );
    await tester.pumpAndSettle();

    expect(scrollable.position.pixels, 0);
  });
}

Future<void> _expectOnlyMatchingTrack(
  WidgetTester tester, {
  required Finder search,
  required String query,
  required String matchingTitle,
}) async {
  await tester.enterText(search, query);
  await tester.pumpAndSettle();

  expect(find.text(matchingTitle), findsOneWidget);
  for (final title in const [
    'Midnight Drive',
    'Other Song',
    'Another Song',
    'Different Song',
  ]) {
    expect(
      find.text(title),
      title == matchingTitle ? findsOneWidget : findsNothing,
    );
  }
}

Future<void> _pumpQueuePanel(
  WidgetTester tester, {
  required _TestPlayerController controller,
  List<Track> tracks = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith((ref) => controller),
        serverConfigControllerProvider
            .overrideWith(_TestServerConfigController.new),
        tracksProvider.overrideWith(
          (ref) async => TrackList(
            total: tracks.length,
            tracks: tracks,
          ),
        ),
        favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: QueuePanel()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _TestServerConfigController extends ServerConfigController {
  @override
  Future<ServerConfig> build() async {
    return const ServerConfig(baseUrl: 'http://localhost');
  }
}

class _TestPlayerController extends PlayerController {
  _TestPlayerController()
      : super(
          backend: _FakeAudioPlayerBackend(),
          serverBaseUrl: () => 'http://localhost',
          queueRepository: _MemoryQueueRepository(),
        );

  void emit(PlaybackState playback) {
    state = playback;
  }
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
