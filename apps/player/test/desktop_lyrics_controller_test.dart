import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_controller.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_overlay_provider.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';
import 'package:player/features/lyrics/data/lyrics_api.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/preferences/player_preferences.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const firstTrack = Track(id: 'first', title: 'First');
  const secondTrack = Track(id: 'second', title: 'Second');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('updates a timed lyric as playback position changes', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:01.00]First\n[00:03.00]Second'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack, seconds: 1));
    await controller.enable();
    await controller.updatePlayback(_playing(firstTrack, seconds: 3));

    expect(overlay.shownTexts, ['First']);
    expect(overlay.updatedTexts, ['Second']);
    expect(controller.state.hasTimedLyrics, isTrue);
  });

  test('applies the per-track timing offset to desktop lyrics immediately',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:01.00]First\n[00:03.00]Second'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack, seconds: 2));
    await controller.enable();
    await controller.setLyricsOffset(const Duration(seconds: 1));

    expect(overlay.shownTexts, ['First']);
    expect(overlay.updatedTexts, ['Second']);
  });

  test('switches a visible overlay between single and double lines', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async =>
          _lyrics('[00:01.00]First\n[00:03.00]Second\n[00:05.00]Third'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack, seconds: 1));
    await controller.enable();
    await controller.setLineMode(DesktopLyricsLineMode.doubleLine);
    await controller.setLineMode(DesktopLyricsLineMode.singleLine);

    expect(overlay.shownTexts, ['First']);
    expect(overlay.updatedTexts, ['First\nSecond', 'First']);
  });

  test('uses only the current line at the end of double-line lyrics', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:01.00]First\n[00:03.00]Last'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack, seconds: 3));
    await controller.setLineMode(DesktopLyricsLineMode.doubleLine);
    await controller.enable();

    expect(overlay.shownTexts, ['Last']);
  });

  test('applies style to a visible overlay without reopening it', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:00.00]Visible lyric'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();
    await controller.applyDesktopLyricsStyle(
      backgroundOpacity: 0.7,
      textColor: 0xff80deea,
      fontSize: 28,
      textAlignment: LyricsTextAlignment.right,
    );

    expect(overlay.shownTexts, ['Visible lyric']);
    expect(overlay.updatedTexts, isEmpty);
    expect(overlay.hideCalls, isZero);
    expect(overlay.configurations, hasLength(1));
    final configuration = overlay.configurations.single;
    expect(configuration.backgroundOpacity, 0.7);
    expect(configuration.textColor, 0xff80deea);
    expect(configuration.fontSize, 28);
    expect(configuration.textAlignment, LyricsTextAlignment.right);
    expect(configuration.resetPosition, isFalse);
  });

  test('applies style to a hidden overlay for immediate native persistence',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:00.00]Visible lyric'),
    );
    addTearDown(controller.dispose);

    await controller.applyDesktopLyricsStyle(
      backgroundOpacity: 0.35,
      textColor: 0xffffffff,
      fontSize: 26,
      textAlignment: LyricsTextAlignment.center,
    );

    expect(overlay.configurations, hasLength(1));
    expect(overlay.configurations.single.fontSize, 26);
    expect(overlay.shownTexts, isEmpty);
  });

  test('reloads lyrics when the current track changes', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final requestedTrackIds = <String>[];
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (trackId) async {
        requestedTrackIds.add(trackId);
        return _lyrics('[00:00.00]$trackId lyric');
      },
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();
    await controller.updatePlayback(_playing(secondTrack));

    expect(requestedTrackIds, ['first', 'second']);
    expect(overlay.shownTexts, ['first lyric', 'second lyric']);
    expect(overlay.updatedTexts, isEmpty);
  });

  test('hides the overlay when playback stops or desktop lyrics disable',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:00.00]Visible lyric'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();
    await controller.updatePlayback(
      const PlaybackState(
        currentTrack: firstTrack,
        status: PlaybackStatus.stopped,
      ),
    );
    await controller.disable();

    expect(overlay.hideCalls, 2);
  });

  test('keeps lyrics enabled when the listening page detaches', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:00.00]Visible lyric'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();
    controller.setUiListenerActive(false);
    await controller.disable();

    expect(controller.state.isEnabled, isTrue);
    expect(overlay.hideCalls, isZero);
  });

  test('keeps the controller alive and follows global playback after detach',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final playerController = _TestPlayerController();
    final container = ProviderContainer(
      overrides: [
        desktopLyricsOverlayProvider.overrideWithValue(overlay),
        lyricsApiProvider.overrideWithValue(
          _FakeLyricsApi(_lyrics('[00:00.00]First\n[00:02.00]Second')),
        ),
        playerControllerProvider.overrideWith((ref) => playerController),
      ],
    );
    addTearDown(container.dispose);

    final subscription = container.listen<DesktopLyricsState>(
      desktopLyricsControllerProvider,
      (previous, next) {},
    );
    final controller = container.read(desktopLyricsControllerProvider.notifier);

    await controller.enable();
    playerController.emit(_playing(firstTrack));
    await _drainAsync();

    final pendingDisable = controller.disable();
    subscription.close();
    await pendingDisable;
    playerController.emit(_playing(firstTrack, seconds: 2));
    await _drainAsync();

    expect(
      identical(
        controller,
        container.read(desktopLyricsControllerProvider.notifier),
      ),
      isTrue,
    );
    expect(controller.state.isEnabled, isTrue);
    expect(overlay.shownTexts, ['First']);
    expect(overlay.updatedTexts, ['Second']);
  });

  test('refreshes visible lyrics when the persisted line mode changes',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final playerController = _TestPlayerController();
    final container = ProviderContainer(
      overrides: [
        desktopLyricsOverlayProvider.overrideWithValue(overlay),
        lyricsApiProvider.overrideWithValue(
          _FakeLyricsApi(_lyrics('[00:01.00]First\n[00:03.00]Second')),
        ),
        playerControllerProvider.overrideWith((ref) => playerController),
      ],
    );
    addTearDown(container.dispose);

    final controller = container.read(desktopLyricsControllerProvider.notifier);
    final preferences = container.read(playerPreferencesProvider.notifier);
    await container.read(playerPreferencesProvider.future);

    await controller.enable();
    playerController.emit(_playing(firstTrack, seconds: 1));
    await _drainAsync();

    await preferences
        .setDesktopLyricsLineMode(DesktopLyricsLineMode.doubleLine);
    await _drainAsync();

    expect(overlay.shownTexts, ['First']);
    expect(overlay.updatedTexts, ['First\nSecond']);
  });

  test('404 lyrics response hides overlay without affecting enabled state',
      () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) => Future<Lyrics>.error(
        const ApiError('Not found', statusCode: 404),
      ),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();

    expect(controller.state.isEnabled, isTrue);
    expect(controller.state.hasLyrics, isFalse);
    expect(controller.state.lyricsErrorMessage, isNull);
    expect(overlay.shownTexts, isEmpty);
  });

  test('shows untimed lyrics as a readable fallback', () async {
    final overlay = _FakeDesktopLyricsOverlay();
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('First line\nSecond line'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack, seconds: 40));
    await controller.enable();

    expect(overlay.shownTexts, ['First line\nSecond line']);
    expect(controller.state.hasTimedLyrics, isFalse);
  });

  test('requests permission before loading and showing lyrics', () async {
    final overlay = _FakeDesktopLyricsOverlay(
      status: _overlayStatus(
        state: LyricsOverlayState.permissionDenied,
        canDrawOverlays: false,
        canPostNotifications: false,
      ),
      permissionStatus: _overlayStatus(
        state: LyricsOverlayState.permissionGranted,
        canDrawOverlays: true,
        canPostNotifications: true,
      ),
    );
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (_) async => _lyrics('[00:00.00]Allowed'),
    );
    addTearDown(controller.dispose);

    await controller.updatePlayback(_playing(firstTrack));
    await controller.enable();

    expect(overlay.permissionRequests, 1);
    expect(overlay.shownTexts, ['Allowed']);
    expect(controller.state.needsPermission, isFalse);
  });
}

PlaybackState _playing(Track track, {int seconds = 0}) {
  return PlaybackState(
    currentTrack: track,
    status: PlaybackStatus.playing,
    position: Duration(seconds: seconds),
  );
}

Lyrics _lyrics(String content) {
  return Lyrics(
    trackId: 'track',
    path: null,
    encoding: null,
    content: content,
  );
}

Future<void> _drainAsync() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

LyricsOverlayStatus _overlayStatus({
  LyricsOverlayState state = LyricsOverlayState.permissionGranted,
  bool canDrawOverlays = true,
  bool canPostNotifications = true,
  bool isVisible = false,
}) {
  return LyricsOverlayStatus(
    platform: LyricsOverlayPlatform.windows,
    state: state,
    canDrawOverlays: canDrawOverlays,
    canPostNotifications: canPostNotifications,
    isVisible: isVisible,
    message: state.name,
  );
}

class _FakeDesktopLyricsOverlay implements DesktopLyricsOverlay {
  _FakeDesktopLyricsOverlay({
    LyricsOverlayStatus? status,
    LyricsOverlayStatus? permissionStatus,
  })  : _status = status ?? _overlayStatus(),
        _permissionStatus = permissionStatus;

  LyricsOverlayStatus _status;
  final LyricsOverlayStatus? _permissionStatus;
  final shownTexts = <String>[];
  final updatedTexts = <String>[];
  final configurations = <_OverlayConfiguration>[];
  var hideCalls = 0;
  var permissionRequests = 0;

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    return const LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.windows,
      supportsSystemOverlay: true,
      supportsTransparentWindow: true,
      supportsClickThrough: true,
      supportsLockPosition: true,
      requiresRuntimePermission: false,
      notes: '',
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() async => _status;

  @override
  Future<LyricsOverlayStatus> requestPermission() async {
    permissionRequests++;
    return _status = _permissionStatus ?? _status;
  }

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) async {
    configurations.add(
      _OverlayConfiguration(
        backgroundOpacity: backgroundOpacity,
        textColor: textColor,
        fontSize: fontSize,
        textAlignment: textAlignment,
        resetPosition: resetPosition,
      ),
    );
    return _status;
  }

  @override
  Future<LyricsOverlayStatus> show(String text) async {
    shownTexts.add(text);
    return _status = _status.copyWith(
      state: LyricsOverlayState.visible,
      isVisible: true,
    );
  }

  @override
  Future<LyricsOverlayStatus> update(String text) async {
    updatedTexts.add(text);
    return _status = _status.copyWith(
      state: LyricsOverlayState.updated,
      isVisible: true,
    );
  }

  @override
  Future<LyricsOverlayStatus> hide() async {
    hideCalls++;
    return _status = _status.copyWith(
      state: LyricsOverlayState.hidden,
      isVisible: false,
    );
  }

  @override
  Future<LyricsOverlayStatus> dispose() => hide();
}

class _OverlayConfiguration {
  const _OverlayConfiguration({
    required this.backgroundOpacity,
    required this.textColor,
    required this.fontSize,
    required this.textAlignment,
    required this.resetPosition,
  });

  final double backgroundOpacity;
  final int textColor;
  final double fontSize;
  final LyricsTextAlignment textAlignment;
  final bool resetPosition;
}

class _FakeLyricsApi extends LyricsApi {
  _FakeLyricsApi(this._lyrics) : super(Dio());

  final Lyrics _lyrics;

  @override
  Future<Lyrics> fetchLyrics(String trackId) async => _lyrics;
}

class _TestPlayerController extends PlayerController {
  _TestPlayerController()
      : super(
          backend: _FakeAudioPlayerBackend(),
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

extension on LyricsOverlayStatus {
  LyricsOverlayStatus copyWith({
    LyricsOverlayState? state,
    bool? isVisible,
  }) {
    return LyricsOverlayStatus(
      platform: platform,
      state: state ?? this.state,
      canDrawOverlays: canDrawOverlays,
      canPostNotifications: canPostNotifications,
      isVisible: isVisible ?? this.isVisible,
      message: message,
    );
  }
}
