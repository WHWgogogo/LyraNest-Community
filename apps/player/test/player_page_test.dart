import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player/core/config/server_config.dart';
import 'package:player/core/config/server_config_controller.dart';
import 'package:player/features/collections/application/collections_controller.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_controller.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_overlay_provider.dart';
import 'package:player/features/desktop_lyrics/data/unsupported_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';
import 'package:player/features/lyrics/data/lyrics_api.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/player/presentation/player_bar.dart';
import 'package:player/features/player/presentation/player_page.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('player shows LyraNest branding on narrow and wide screens',
      (tester) async {
    for (final size in [const Size(390, 844), const Size(1440, 900)]) {
      await _pumpPlayerPage(tester, size: size);

      expect(find.text('LyraNest'), findsOneWidget);
      expect(find.text('AURA'), findsNothing);
    }
  });

  testWidgets('player exposes a download action for the current track',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    expect(
      find.byKey(const ValueKey('player-current-track-download')),
      findsOneWidget,
    );
  });

  testWidgets('narrow player swipes from compact to seekable full lyrics',
      (tester) async {
    final harness = await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    expect(find.byKey(const ValueKey('mobile-player-layout')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      findsOneWidget,
    );
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
    );

    await tester.drag(
      find.byKey(const PageStorageKey('mobile-player-stage')),
      const Offset(-360, 0),
    );
    await tester.pumpAndSettle();

    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-full-lyrics')),
      hiddenPage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
    );
    expect(
      find.byKey(const ValueKey('now-playing-lyrics-list')),
      findsOneWidget,
    );

    await tester.tap(find.text('Second'));
    await tester.pump();

    expect(harness.backend.seekPositions, [const Duration(seconds: 1)]);
  });

  testWidgets('narrow player swipes back from lyrics without snapping back',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    for (var index = 0; index < 3; index++) {
      await _swipeMobilePlayerStage(tester, const Offset(-240, 0));
      _expectMobilePageVisible(
        tester,
        visiblePage: find.byKey(const ValueKey('mobile-full-lyrics')),
        hiddenPage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      );

      await _swipeMobilePlayerStage(tester, const Offset(240, 0));
      _expectMobilePageVisible(
        tester,
        visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
        hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
      );
    }
  });

  testWidgets('narrow player accepts a slow partial swipe back from lyrics',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    final stage = find.byKey(const PageStorageKey('mobile-player-stage'));
    await tester.drag(stage, const Offset(-240, 0));
    await tester.pumpAndSettle();
    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-full-lyrics')),
      hiddenPage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
    );

    await tester.timedDrag(
      stage,
      const Offset(120, 0),
      const Duration(milliseconds: 800),
    );
    await tester.pumpAndSettle();

    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
    );
  });

  testWidgets('lyric centering cannot recapture the page during swipe back',
      (tester) async {
    final harness = await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    await _swipeMobilePlayerStage(tester, const Offset(-240, 0));
    final lyricsList = find.byKey(const ValueKey('now-playing-lyrics-list'));
    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-full-lyrics')),
      hiddenPage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
    );

    final gesture = await tester.startGesture(tester.getCenter(lyricsList));
    await tester.pump();
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.moveBy(const Offset(120, 0));
    await tester.pump(const Duration(milliseconds: 80));
    final stageCenterX = tester
        .getCenter(
          find.byKey(const PageStorageKey('mobile-player-stage')),
        )
        .dx;
    expect(
      tester.getCenter(find.byKey(const ValueKey('mobile-full-lyrics'))).dx,
      greaterThan(stageCenterX + 100),
    );

    harness.controller.emit(
      const PlaybackState(
        currentTrack: _track,
        queue: [_track, _nextTrack],
        currentIndex: 0,
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 2500),
        duration: Duration(minutes: 3, seconds: 40),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump(const Duration(milliseconds: 80));
    await gesture.up();
    await tester.pumpAndSettle();

    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
    );
  });

  testWidgets('narrow player returns to overview after scrolling lyrics',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    await _swipeMobilePlayerStage(tester, const Offset(-240, 0));
    final lyrics = find.byKey(const ValueKey('now-playing-lyrics-list'));
    expect(lyrics, findsOneWidget);

    await tester.drag(lyrics, const Offset(0, -160));
    await tester.pumpAndSettle();

    await _swipeMobilePlayerStage(tester, const Offset(240, 0));
    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
    );
  });

  testWidgets('narrow player settles rapid opposite swipes on overview',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    final stage = find.byKey(const PageStorageKey('mobile-player-stage'));
    await tester.fling(stage, const Offset(-240, 0), 1200);
    await tester.pump(const Duration(milliseconds: 20));
    await tester.fling(stage, const Offset(240, 0), 1200);
    await tester.pumpAndSettle();

    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      hiddenPage: find.byKey(const ValueKey('mobile-full-lyrics')),
    );
  });

  testWidgets('narrow player returns to overview when the track changes',
      (tester) async {
    final harness = await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );

    await _swipeMobilePlayerStage(tester, const Offset(-240, 0));
    _expectMobilePageVisible(
      tester,
      visiblePage: find.byKey(const ValueKey('mobile-full-lyrics')),
      hiddenPage: find.byKey(const ValueKey('mobile-compact-lyrics-card')),
    );

    harness.controller.emit(
      const PlaybackState(
        currentTrack: _nextTrack,
        queue: [_track, _nextTrack],
        currentIndex: 1,
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 1500),
        duration: Duration(minutes: 3, seconds: 40),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-compact-lyrics-card')),
      findsOneWidget,
    );
  });

  testWidgets('narrow player toggles desktop lyrics directly', (tester) async {
    final overlay = _PermissionRequestingDesktopLyricsOverlay();
    final desktopLyricsController = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (trackId) async => _lyrics,
    );
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
      desktopLyricsController: desktopLyricsController,
    );

    final actionArea = find.byKey(const ValueKey('mobile-player-actions'));
    final favorite = find.byKey(const ValueKey('player-favorite-toggle'));
    final desktopLyrics =
        find.byKey(const ValueKey('mobile-desktop-lyrics-toggle'));

    expect(actionArea, findsOneWidget);
    expect(favorite, findsOneWidget);
    expect(desktopLyrics, findsOneWidget);
    expect(find.ancestor(of: favorite, matching: actionArea), findsOneWidget);
    expect(
      find.ancestor(of: desktopLyrics, matching: actionArea),
      findsOneWidget,
    );
    expect(tester.getCenter(desktopLyrics).dy, tester.getCenter(favorite).dy);

    await tester.tap(desktopLyrics);
    await tester.pumpAndSettle();

    expect(overlay.permissionRequestCount, 1);
    expect(desktopLyricsController.state.isEnabled, isTrue);
    expect(
      _actionIconColor(tester, desktopLyrics),
      const Color(0xFFC6B8FF),
    );
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);

    await tester.tap(desktopLyrics);
    await tester.pumpAndSettle();

    expect(desktopLyricsController.state.isEnabled, isFalse);
  });

  testWidgets('wide desktop lyrics actions use playback mode selected color',
      (tester) async {
    final overlay = _PermissionRequestingDesktopLyricsOverlay();
    final desktopLyricsController = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (trackId) async => _lyrics,
    );
    await _pumpPlayerPage(
      tester,
      size: const Size(1440, 900),
      desktopLyricsController: desktopLyricsController,
    );

    final topBarLyrics =
        find.byKey(const ValueKey('desktop-topbar-lyrics-toggle'));
    final navigationLyrics =
        find.byKey(const ValueKey('desktop-navigation-lyrics-toggle'));

    await tester.tap(topBarLyrics);
    await tester.pumpAndSettle();

    expect(desktopLyricsController.state.isEnabled, isTrue);
    expect(
      _actionIconColor(tester, topBarLyrics),
      const Color(0xFFC6B8FF),
    );
    expect(
      _actionIconColor(tester, navigationLyrics),
      const Color(0xFFC6B8FF),
    );

    await tester.tap(
      find.byKey(const ValueKey('player-playback-mode-toggle')),
    );
    await tester.pump();

    expect(
      _actionIconColor(
        tester,
        find.byKey(const ValueKey('player-playback-mode-toggle')),
      ),
      _actionIconColor(tester, topBarLyrics),
    );
  });

  testWidgets('progress dragging seeks once only after release',
      (tester) async {
    final harness = await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('player-progress-slider')),
    );

    slider.onChangeStart!(90000);
    slider.onChanged!(120000);
    await tester.pump();

    expect(harness.backend.seekPositions, isEmpty);
    expect(
      harness.controller.state.position,
      const Duration(milliseconds: 1500),
    );

    slider.onChangeEnd!(120000);
    await tester.pumpAndSettle();

    expect(harness.backend.seekPositions, [const Duration(seconds: 120)]);
  });

  testWidgets('progress drag cancels when the playback track changes',
      (tester) async {
    final harness = await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
    );
    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('player-progress-slider')),
    );

    slider.onChangeStart!(90000);
    slider.onChanged!(120000);
    harness.controller.emit(
      const PlaybackState(
        currentTrack: _nextTrack,
        queue: [_track, _nextTrack],
        currentIndex: 1,
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 1500),
        duration: Duration(minutes: 3, seconds: 40),
      ),
    );
    await tester.pump();

    slider.onChangeEnd!(120000);
    await tester.pump();

    expect(harness.backend.seekPositions, isEmpty);
  });

  testWidgets('narrow player compacts titles, artwork, and the lyrics preview',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
      track: _longTitleTrack,
    );

    final title = tester.widget<Text>(
      find.byKey(const ValueKey('mobile-track-title')),
    );
    final artworkSize = tester.getSize(
      find.byKey(const ValueKey('mobile-track-artwork')),
    );
    final lyricsCard = find.byKey(const ValueKey('mobile-compact-lyrics-card'));
    final lyricsTitle =
        tester.element(lyricsCard).l10n.lyricsTitle.toUpperCase();

    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(title.style?.fontSize, 22);
    expect(artworkSize.width, lessThanOrEqualTo(320));
    expect(artworkSize.height, lessThanOrEqualTo(320));
    expect(
      find.descendant(
        of: lyricsCard,
        matching: find.text(lyricsTitle),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lyricsCard,
        matching: find.byIcon(Icons.open_in_full_rounded),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: lyricsCard,
        matching: find.text('Third'),
      ),
      findsOneWidget,
    );
    expect(tester.getSize(lyricsCard).height, greaterThan(150));
  });

  testWidgets(
      'player close actions return to library and restore the player bar',
      (tester) async {
    var closeCalls = 0;
    final router = GoRouter(
      initialLocation: '/player',
      routes: [
        ShellRoute(
          builder: (context, state, child) {
            return Scaffold(
              body: child,
              bottomNavigationBar: const PlayerBar(),
            );
          },
          routes: [
            GoRoute(
              path: '/',
              builder: (context, state) => const Center(
                child: Text('Track library'),
              ),
            ),
            GoRoute(
              path: '/player',
              builder: (context, state) => PlayerPage(
                onClose: () => closeCalls += 1,
              ),
            ),
          ],
        ),
      ],
    );
    addTearDown(router.dispose);

    await _pumpPlayerPage(
      tester,
      size: const Size(390, 844),
      child: _RoutedTestApp(router: router),
    );

    final playerBar = find.byType(PlayerBar);
    final miniPlayerPlayControl = find.descendant(
      of: playerBar,
      matching: find.byTooltip('Pause'),
    );
    final miniPlayerTapTarget = find.ancestor(
      of: miniPlayerPlayControl,
      matching: find.byType(InkWell),
    );

    expect(router.routeInformationProvider.value.uri.path, '/player');
    expect(miniPlayerPlayControl, findsNothing);

    await tester.tap(find.byIcon(Icons.keyboard_arrow_down_rounded));
    await tester.pumpAndSettle();

    expect(closeCalls, 1);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Track library'), findsOneWidget);
    expect(miniPlayerPlayControl, findsOneWidget);
    expect(miniPlayerTapTarget, findsOneWidget);

    router.go('/player');
    await tester.pumpAndSettle();
    expect(miniPlayerPlayControl, findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(closeCalls, 2);
    expect(router.routeInformationProvider.value.uri.path, '/');
    expect(find.text('Track library'), findsOneWidget);
    expect(miniPlayerPlayControl, findsOneWidget);
    expect(miniPlayerTapTarget, findsOneWidget);
  });

  testWidgets('wide player shows scrolling lyrics and collapsible queue',
      (tester) async {
    await _pumpPlayerPage(
      tester,
      size: const Size(1440, 900),
    );

    expect(find.byKey(const ValueKey('desktop-player-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-lyrics-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('now-playing-lyrics-list')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('desktop-queue-panel')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-queue-toggle')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-queue-panel')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

Future<_PlayerPageHarness> _pumpPlayerPage(
  WidgetTester tester, {
  required Size size,
  Track track = _track,
  Widget? child,
  DesktopLyricsController? desktopLyricsController,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  final backend = _FakeAudioPlayerBackend();
  final controller = _TestPlayerController(backend)
    ..emit(
      PlaybackState(
        currentTrack: track,
        queue: [track, _nextTrack],
        currentIndex: 0,
        status: PlaybackStatus.playing,
        position: Duration(milliseconds: 1500),
        duration: Duration(minutes: 3, seconds: 40),
      ),
    );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerControllerProvider.overrideWith((ref) => controller),
        lyricsApiProvider.overrideWithValue(_FakeLyricsApi(_lyrics)),
        serverConfigControllerProvider
            .overrideWith(_TestServerConfigController.new),
        collectionsControllerProvider
            .overrideWith(_TestCollectionsController.new),
        desktopLyricsControllerProvider.overrideWith(
          (ref) =>
              desktopLyricsController ??
              DesktopLyricsController(
                overlay: const UnsupportedLyricsOverlay(),
                loadLyrics: (trackId) async => _lyrics,
              ),
        ),
      ],
      child: child ?? const _TestApp(),
    ),
  );
  await tester.pumpAndSettle();

  return _PlayerPageHarness(backend, controller);
}

Future<void> _swipeMobilePlayerStage(
  WidgetTester tester,
  Offset offset,
) async {
  await tester.drag(
    find.byKey(const PageStorageKey('mobile-player-stage')),
    offset,
  );
  await tester.pumpAndSettle();
}

void _expectMobilePageVisible(
  WidgetTester tester, {
  required Finder visiblePage,
  required Finder hiddenPage,
}) {
  final stageRect = tester.getRect(
    find.byKey(const PageStorageKey('mobile-player-stage')),
  );
  expect(visiblePage, findsOneWidget);
  expect(stageRect.contains(tester.getCenter(visiblePage)), isTrue);
  if (hiddenPage.evaluate().isNotEmpty) {
    expect(stageRect.contains(tester.getCenter(hiddenPage)), isFalse);
  }
}

Color? _actionIconColor(WidgetTester tester, Finder action) {
  return tester
      .widget<Icon>(
        find.descendant(of: action, matching: find.byType(Icon)),
      )
      .color;
}

const _track = Track(
  id: 'track-1',
  title: 'Current track',
  artist: 'Artist',
  album: 'Album',
);

const _longTitleTrack = Track(
  id: 'track-long-title',
  title:
      'A deliberately long track title that must stay compact on mobile screens',
  artist: 'Artist',
  album: 'Album',
);

const _nextTrack = Track(
  id: 'track-2',
  title: 'Next track',
  artist: 'Artist',
);

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

class _PlayerPageHarness {
  const _PlayerPageHarness(this.backend, this.controller);

  final _FakeAudioPlayerBackend backend;
  final _TestPlayerController controller;
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const PlayerPage(),
    );
  }
}

class _RoutedTestApp extends StatelessWidget {
  const _RoutedTestApp({
    required this.router,
  });

  final GoRouter router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}

class _TestServerConfigController extends ServerConfigController {
  @override
  Future<ServerConfig> build() async {
    return const ServerConfig(baseUrl: 'http://localhost');
  }
}

class _TestCollectionsController extends CollectionsController {
  @override
  Future<CollectionsState> build() async {
    return CollectionsState();
  }
}

class _FakeLyricsApi extends LyricsApi {
  _FakeLyricsApi(this.lyrics) : super(Dio());

  final Lyrics lyrics;

  @override
  Future<Lyrics> fetchLyrics(String trackId) async => lyrics;
}

class _PermissionRequestingDesktopLyricsOverlay
    implements DesktopLyricsOverlay {
  var permissionRequestCount = 0;

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) async {
    return _permissionGrantedStatus;
  }

  @override
  Future<LyricsOverlayStatus> dispose() async {
    return _permissionGrantedStatus;
  }

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    return const LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.android,
      supportsSystemOverlay: true,
      supportsTransparentWindow: false,
      supportsClickThrough: false,
      supportsLockPosition: false,
      requiresRuntimePermission: true,
      notes: 'Test overlay',
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() async {
    return _permissionDeniedStatus;
  }

  @override
  Future<LyricsOverlayStatus> hide() async {
    return _permissionGrantedStatus;
  }

  @override
  Future<LyricsOverlayStatus> requestPermission() async {
    permissionRequestCount += 1;
    return _permissionGrantedStatus;
  }

  @override
  Future<LyricsOverlayStatus> show(String text) async {
    return _permissionGrantedStatus;
  }

  @override
  Future<LyricsOverlayStatus> update(String text) async {
    return _permissionGrantedStatus;
  }
}

const _permissionDeniedStatus = LyricsOverlayStatus(
  platform: LyricsOverlayPlatform.android,
  state: LyricsOverlayState.permissionDenied,
  canDrawOverlays: false,
  canPostNotifications: true,
  isVisible: false,
  message: 'Permission required',
);

const _permissionGrantedStatus = LyricsOverlayStatus(
  platform: LyricsOverlayPlatform.android,
  state: LyricsOverlayState.permissionGranted,
  canDrawOverlays: true,
  canPostNotifications: true,
  isVisible: false,
  message: 'Permission granted',
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
