import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_controller.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_overlay_provider.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/application/queue_repository.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/system_media/application/system_media_controller.dart';
import 'package:player/features/system_media/application/system_media_provider.dart';
import 'package:player/features/system_media/data/system_media_platform.dart';
import 'package:player/features/system_media/domain/system_media_action.dart';
import 'package:player/features/system_media/domain/system_media_state.dart';

void main() {
  test('acknowledges pause after the Flutter pause callback completes',
      () async {
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    final pauseCompletion = Completer<void>();
    var pauseCalls = 0;
    final controller = SystemMediaController(
      platform: platform,
      artworkUrlResolver: (_) => null,
      onPrevious: () async {},
      onPlay: () async {},
      onPause: () {
        pauseCalls++;
        return pauseCompletion.future;
      },
      onNext: () async {},
      onCyclePlaybackMode: () async {},
      onToggleDesktopLyrics: () async {},
    );
    addTearDown(() async {
      await controller.dispose();
      await actions.close();
    });

    actions.add(SystemMediaAction.pause);
    await _drainEvents();

    expect(pauseCalls, 1);
    expect(platform.acknowledgements, isEmpty);

    pauseCompletion.complete();
    await _drainEvents();

    expect(
      platform.acknowledgements,
      [(SystemMediaAction.pause, true)],
    );
  });

  test('serializes actions and reports a failed callback to Android', () async {
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    final pauseCompletion = Completer<void>();
    final calls = <SystemMediaAction>[];
    final controller = SystemMediaController(
      platform: platform,
      artworkUrlResolver: (_) => null,
      onPrevious: () async {},
      onPlay: () async {
        calls.add(SystemMediaAction.play);
      },
      onPause: () {
        calls.add(SystemMediaAction.pause);
        return pauseCompletion.future;
      },
      onNext: () async {
        throw StateError('next failed');
      },
      onCyclePlaybackMode: () async {},
      onToggleDesktopLyrics: () async {},
    );
    addTearDown(() async {
      await controller.dispose();
      await actions.close();
    });

    actions
      ..add(SystemMediaAction.pause)
      ..add(SystemMediaAction.play)
      ..add(SystemMediaAction.next);
    await _drainEvents();

    expect(calls, [SystemMediaAction.pause]);

    pauseCompletion.complete();
    await _drainEvents();

    expect(
      calls,
      [SystemMediaAction.pause, SystemMediaAction.play],
    );
    expect(
      platform.acknowledgements,
      [
        (SystemMediaAction.pause, true),
        (SystemMediaAction.play, true),
        (SystemMediaAction.next, false),
      ],
    );
  });

  test('play and pause actions synchronize the notification presentation',
      () async {
    const track = Track(id: 'song-1', title: 'Song');
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    var isPlaying = false;
    late SystemMediaController controller;

    PlaybackState playback() {
      return PlaybackState(
        currentTrack: track,
        queue: const [track],
        currentIndex: 0,
        status: isPlaying ? PlaybackStatus.playing : PlaybackStatus.paused,
      );
    }

    controller = SystemMediaController(
      platform: platform,
      artworkUrlResolver: (_) => null,
      onPrevious: () async {},
      onPlay: () async {
        isPlaying = true;
        await controller.syncPlayback(playback());
      },
      onPause: () async {
        isPlaying = false;
        await controller.syncPlayback(playback());
      },
      onNext: () async {},
      onCyclePlaybackMode: () async {},
      onToggleDesktopLyrics: () async {},
    );
    addTearDown(() async {
      await controller.dispose();
      await actions.close();
    });

    await controller.syncPlayback(playback());
    actions.add(SystemMediaAction.play);
    await _drainEvents();

    expect(platform.updates.last.status, 'playing');
    expect(platform.acknowledgements, [(SystemMediaAction.play, true)]);

    actions.add(SystemMediaAction.pause);
    await _drainEvents();

    expect(platform.updates.last.status, 'paused');
    expect(
      platform.acknowledgements,
      [
        (SystemMediaAction.play, true),
        (SystemMediaAction.pause, true),
      ],
    );
  });

  test('synchronizes desktop lyric state and routes custom actions', () async {
    const track = Track(id: 'song-1', title: 'Song');
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    final calls = <SystemMediaAction>[];
    final controller = SystemMediaController(
      platform: platform,
      artworkUrlResolver: (_) => null,
      onPrevious: () async {},
      onPlay: () async {},
      onPause: () async {},
      onNext: () async {},
      onCyclePlaybackMode: () async {
        calls.add(SystemMediaAction.playbackMode);
      },
      onToggleDesktopLyrics: () async {
        calls.add(SystemMediaAction.desktopLyrics);
      },
    );
    addTearDown(() async {
      await controller.dispose();
      await actions.close();
    });

    await controller.syncPlayback(
      const PlaybackState(
        currentTrack: track,
        queue: [track],
        currentIndex: 0,
        playbackMode: PlaybackMode.repeatAll,
      ),
    );
    await controller.syncDesktopLyricsEnabled(true);
    await _drainEvents();

    expect(platform.updates.last.playbackMode, 'repeatAll');
    expect(platform.updates.last.desktopLyricsEnabled, isTrue);

    actions
      ..add(SystemMediaAction.playbackMode)
      ..add(SystemMediaAction.desktopLyrics);
    await _drainEvents();

    expect(
      calls,
      [SystemMediaAction.playbackMode, SystemMediaAction.desktopLyrics],
    );
    expect(
      platform.acknowledgements,
      [
        (SystemMediaAction.playbackMode, true),
        (SystemMediaAction.desktopLyrics, true),
      ],
    );
  });

  test('provider routes play and pause events to PlayerController', () async {
    const track = Track(id: 'song-1', title: 'Song');
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    final backend = _FakeAudioPlayerBackend();
    final playerController = PlayerController(
      backend: backend,
      serverBaseUrl: () => 'http://127.0.0.1:8080',
      queueRepository: _FakeQueueRepository(),
    );
    final container = ProviderContainer(
      overrides: [
        systemMediaPlatformProvider.overrideWithValue(platform),
        playerControllerProvider.overrideWith((ref) => playerController),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await actions.close();
    });

    container.read(systemMediaControllerProvider);
    await playerController.select(track, autoplay: false);
    await _drainEvents();

    actions.add(SystemMediaAction.play);
    await _drainEvents();

    expect(backend.playCalls, 1);
    expect(playerController.state.status, PlaybackStatus.playing);
    expect(platform.updates.last.status, 'playing');

    actions.add(SystemMediaAction.pause);
    await _drainEvents();

    expect(backend.pauseCalls, 1);
    expect(playerController.state.status, PlaybackStatus.paused);
    expect(platform.updates.last.status, 'paused');
    expect(
      platform.acknowledgements,
      [
        (SystemMediaAction.play, true),
        (SystemMediaAction.pause, true),
      ],
    );
  });

  test(
      'provider cycles all playback modes and toggles desktop lyrics from notification',
      () async {
    const track = Track(id: 'song-1', title: 'Song');
    final actions = StreamController<SystemMediaAction>();
    final platform = _FakeSystemMediaPlatform(actions.stream);
    final backend = _FakeAudioPlayerBackend();
    final playerController = PlayerController(
      backend: backend,
      serverBaseUrl: () => 'http://127.0.0.1:8080',
      queueRepository: _FakeQueueRepository(),
    );
    final desktopLyrics = DesktopLyricsController(
      overlay: const _FakeDesktopLyricsOverlay(),
      loadLyrics: (_) async => const Lyrics(
        trackId: 'song-1',
        path: null,
        encoding: null,
        content: '',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        systemMediaPlatformProvider.overrideWithValue(platform),
        playerControllerProvider.overrideWith((ref) => playerController),
        desktopLyricsControllerProvider.overrideWith((ref) => desktopLyrics),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await actions.close();
    });

    container.read(systemMediaControllerProvider);
    playerController.setPlaybackMode(PlaybackMode.sequential);
    await playerController.select(track, autoplay: false);
    await _drainEvents();

    for (final expectedMode in [
      PlaybackMode.repeatAll,
      PlaybackMode.repeatOne,
      PlaybackMode.shuffle,
      PlaybackMode.sequential,
    ]) {
      actions.add(SystemMediaAction.playbackMode);
      await _drainEvents();
      expect(playerController.state.playbackMode, expectedMode);
      expect(platform.updates.last.playbackMode, expectedMode.name);
    }

    actions.add(SystemMediaAction.desktopLyrics);
    await _drainEvents();

    expect(desktopLyrics.state.isEnabled, isTrue);
    expect(platform.updates.last.desktopLyricsEnabled, isTrue);

    actions.add(SystemMediaAction.desktopLyrics);
    await _drainEvents();

    expect(desktopLyrics.state.isEnabled, isFalse);
    expect(platform.updates.last.desktopLyricsEnabled, isFalse);
  });
}

Future<void> _drainEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

class _FakeSystemMediaPlatform implements SystemMediaPlatform {
  _FakeSystemMediaPlatform(this.actions);

  @override
  final Stream<SystemMediaAction> actions;

  final acknowledgements = <(SystemMediaAction, bool)>[];
  final updates = <SystemMediaState>[];

  @override
  Future<void> acknowledgeAction(
    SystemMediaAction action, {
    required bool handled,
  }) async {
    acknowledgements.add((action, handled));
  }

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}

  @override
  Future<void> update(SystemMediaState state) async {
    updates.add(state);
  }
}

class _FakeAudioPlayerBackend implements AudioPlayerBackend {
  int pauseCalls = 0;
  int playCalls = 0;

  @override
  Stream<bool> get buffering => const Stream<bool>.empty();

  @override
  Stream<bool> get completed => const Stream<bool>.empty();

  @override
  Stream<Duration> get duration => const Stream<Duration>.empty();

  @override
  Stream<String> get errors => const Stream<String>.empty();

  @override
  Stream<bool> get playing => const Stream<bool>.empty();

  @override
  Stream<Duration> get position => const Stream<Duration>.empty();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> open(Uri uri, {required bool play}) async {}

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> seek(Duration position) async {}

  @override
  Future<void> stop() async {}
}

class _FakeQueueRepository implements QueueRepository {
  @override
  Future<void> clearQueue() async {}

  @override
  Future<List<Track>> loadQueue() async => const [];

  @override
  Future<void> saveQueue(Iterable<Track> queue) async {}
}

class _FakeDesktopLyricsOverlay implements DesktopLyricsOverlay {
  const _FakeDesktopLyricsOverlay();

  static const _status = LyricsOverlayStatus(
    platform: LyricsOverlayPlatform.windows,
    state: LyricsOverlayState.updated,
    canDrawOverlays: true,
    canPostNotifications: true,
    isVisible: false,
    message: 'ok',
  );

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) async =>
      _status;

  @override
  Future<LyricsOverlayStatus> dispose() async => _status;

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    return const LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.windows,
      supportsSystemOverlay: true,
      supportsTransparentWindow: true,
      supportsClickThrough: true,
      supportsLockPosition: true,
      requiresRuntimePermission: false,
      notes: 'ok',
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() async => _status;

  @override
  Future<LyricsOverlayStatus> hide() async => _status;

  @override
  Future<LyricsOverlayStatus> requestPermission() async => _status;

  @override
  Future<LyricsOverlayStatus> show(String text) async => _status;

  @override
  Future<LyricsOverlayStatus> update(String text) async => _status;
}
