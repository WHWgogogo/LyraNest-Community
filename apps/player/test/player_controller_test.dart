import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/offline/application/offline_playback_source_resolver.dart';
import 'package:player/features/player/application/audio_player_backend.dart';
import 'package:player/features/player/application/player_controller.dart';
import 'package:player/features/player/application/queue_repository.dart';
import 'package:player/features/player/domain/playback_state.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('buildTrackStreamUri', () {
    test('uses the configured server origin and stream endpoint', () {
      final uri = buildTrackStreamUri(
        baseUrl: 'https://music.example.test:8443/old/path?token=old',
        trackId: 'track 1',
      );

      expect(
        uri.toString(),
        'https://music.example.test:8443/api/v1/tracks/track%201/stream',
      );
    });
  });

  group('PlayerController', () {
    late _FakeAudioPlayerBackend backend;
    late PlayerController controller;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      backend = _FakeAudioPlayerBackend();
      controller = PlayerController(
        backend: backend,
        serverBaseUrl: () => 'http://10.0.2.2:8080',
        random: Random(7),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('select opens and starts the configured stream', () async {
      const track = Track(
        id: 'song-1',
        title: 'Song',
        durationSeconds: 120,
      );

      await controller.select(track);

      expect(backend.openedUris.single.toString(),
          'http://10.0.2.2:8080/api/v1/tracks/song-1/stream');
      expect(backend.openPlayValues.single, isTrue);
      expect(controller.state.currentTrack, same(track));
      expect(controller.state.status, PlaybackStatus.playing);
      expect(controller.state.duration, const Duration(minutes: 2));
    });

    test('select prefers an available local media file', () async {
      final localBackend = _FakeAudioPlayerBackend();
      final localController = PlayerController(
        backend: localBackend,
        serverBaseUrl: () => 'http://10.0.2.2:8080',
        offlinePlaybackSourceResolver: _FakeOfflinePlaybackSourceResolver(
          Uri.file(r'C:\offline\song.media'),
        ),
        isOfflineAuthenticated: () => true,
      );
      addTearDown(localController.dispose);

      await localController.select(const Track(id: 'song-1', title: 'Song'));

      expect(localBackend.openedUris.single.scheme, 'file');
      expect(localBackend.openedUris.single.path, contains('song.media'));
      expect(localController.state.status, PlaybackStatus.playing);
    });

    test('offline playback gives a clear error when media is not downloaded',
        () async {
      final offlineBackend = _FakeAudioPlayerBackend();
      final offlineController = PlayerController(
        backend: offlineBackend,
        serverBaseUrl: () => 'http://10.0.2.2:8080',
        offlinePlaybackSourceResolver: _FakeOfflinePlaybackSourceResolver(null),
        isOfflineAuthenticated: () => true,
      );
      addTearDown(offlineController.dispose);

      await offlineController.select(
        const Track(id: 'not-downloaded', title: 'Not downloaded'),
      );

      expect(offlineBackend.openedUris, isEmpty);
      expect(offlineController.state.status, PlaybackStatus.error);
      expect(offlineController.state.errorMessage, contains('没有可用的本地下载'));
    });

    test('selecting another track replaces playback state and media', () async {
      const first = Track(id: 'first', title: 'First');
      const second = Track(id: 'second', title: 'Second');

      await controller.select(first);
      backend.positions.add(const Duration(seconds: 30));
      await controller.select(second);

      expect(
        backend.openedUris.map((uri) => uri.path).toList(),
        [
          '/api/v1/tracks/first/stream',
          '/api/v1/tracks/second/stream',
        ],
      );
      expect(controller.state.currentTrack, same(second));
      expect(controller.state.position, Duration.zero);
    });

    test('setQueue selects an item and sequential navigation stops at ends',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
        Track(id: 'third', title: 'Third'),
      ];
      controller.setPlaybackMode(PlaybackMode.sequential);

      await controller.setQueue(
        tracks,
        initialIndex: 1,
        autoplay: false,
      );

      expect(controller.state.queue, tracks);
      expect(controller.state.currentIndex, 1);
      expect(controller.state.currentTrack, same(tracks[1]));
      expect(controller.state.status, PlaybackStatus.paused);
      expect(backend.openPlayValues.last, isFalse);

      await controller.next();
      expect(controller.state.currentTrack, same(tracks[2]));

      final openCountAtEnd = backend.openedUris.length;
      await controller.next();
      expect(controller.state.currentTrack, same(tracks[2]));
      expect(backend.openedUris, hasLength(openCountAtEnd));

      await controller.previous();
      expect(controller.state.currentTrack, same(tracks[1]));
    });

    test('default list loop navigation wraps in both directions', () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
        Track(id: 'third', title: 'Third'),
      ];
      await controller.setQueue(tracks, initialIndex: 2);

      await controller.next();
      expect(controller.state.currentTrack, same(tracks[0]));

      await controller.previous();
      expect(controller.state.currentTrack, same(tracks[2]));
    });

    test('select keeps the active queue when the track is present', () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
      ];
      await controller.setQueue(tracks);

      await controller.select(tracks[1], autoplay: false);

      expect(controller.state.queue, tracks);
      expect(controller.state.currentIndex, 1);
      expect(controller.state.currentTrack, same(tracks[1]));
      expect(controller.state.status, PlaybackStatus.paused);
    });

    test('adding to a playing queue preserves the current media position',
        () async {
      const first = Track(id: 'first', title: 'First');
      const current = Track(
        id: 'current',
        title: 'Current',
        durationSeconds: 120,
      );
      const updatedCurrent = Track(
        id: 'current',
        title: 'Updated current',
        durationSeconds: 120,
      );
      const added = Track(id: 'added', title: 'Added');
      await controller.setQueue(
        const [first, current],
        initialIndex: 1,
      );
      controller.setPlaybackMode(PlaybackMode.repeatAll);
      backend.positions.add(const Duration(seconds: 45));
      final openCount = backend.openedUris.length;

      await controller.setQueue(
        const [first, updatedCurrent, added],
        initialIndex: 1,
      );

      expect(backend.openedUris, hasLength(openCount));
      expect(controller.state.currentTrack, same(updatedCurrent));
      expect(controller.state.currentIndex, 1);
      expect(controller.state.position, const Duration(seconds: 45));
      expect(controller.state.status, PlaybackStatus.playing);
      expect(controller.state.playbackMode, PlaybackMode.repeatAll);
    });

    test('removing a non-current queue item preserves the playing media',
        () async {
      const first = Track(id: 'first', title: 'First');
      const current = Track(
        id: 'current',
        title: 'Current',
        durationSeconds: 120,
      );
      const third = Track(id: 'third', title: 'Third');
      await controller.setQueue(
        const [first, current, third],
        initialIndex: 1,
      );
      controller.setPlaybackMode(PlaybackMode.shuffle);
      backend.positions.add(const Duration(seconds: 45));
      final openCount = backend.openedUris.length;

      await controller.setQueue(
        const [current, third],
        initialIndex: 0,
      );

      expect(backend.openedUris, hasLength(openCount));
      expect(controller.state.currentTrack, same(current));
      expect(controller.state.currentIndex, 0);
      expect(controller.state.position, const Duration(seconds: 45));
      expect(controller.state.status, PlaybackStatus.playing);
      expect(controller.state.playbackMode, PlaybackMode.shuffle);
    });

    test('removing the current queue item opens its replacement', () async {
      const first = Track(id: 'first', title: 'First');
      const current = Track(
        id: 'current',
        title: 'Current',
        durationSeconds: 120,
      );
      const replacement = Track(id: 'replacement', title: 'Replacement');
      await controller.setQueue(
        const [first, current, replacement],
        initialIndex: 1,
      );
      controller.setPlaybackMode(PlaybackMode.repeatAll);
      backend.positions.add(const Duration(seconds: 45));
      final openCount = backend.openedUris.length;

      await controller.removeFromQueue(current);

      expect(backend.openedUris, hasLength(openCount + 1));
      expect(
        backend.openedUris.last.path,
        '/api/v1/tracks/replacement/stream',
      );
      expect(controller.state.currentTrack, same(replacement));
      expect(controller.state.currentIndex, 1);
      expect(controller.state.position, Duration.zero);
      expect(controller.state.status, PlaybackStatus.playing);
      expect(controller.state.playbackMode, PlaybackMode.repeatAll);
    });

    test('select accepts a queue and next advances from the selected item',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
        Track(id: 'third', title: 'Third'),
      ];

      await controller.select(
        tracks[1],
        queue: tracks,
        autoplay: false,
      );
      await controller.next(autoplay: false);

      expect(controller.state.queue, tracks);
      expect(controller.state.currentTrack, same(tracks[2]));
      expect(controller.state.currentIndex, 2);
    });

    test('stream events update loading progress duration and errors', () async {
      const track = Track(id: 'song-1', title: 'Song');
      await controller.select(track);

      backend.bufferingStates.add(true);
      backend.durations.add(const Duration(minutes: 3));
      backend.positions.add(const Duration(seconds: 45));

      expect(controller.state.isLoading, isTrue);
      expect(controller.state.duration, const Duration(minutes: 3));
      expect(controller.state.position, const Duration(seconds: 45));
      expect(controller.state.progress, closeTo(0.25, 0.001));

      backend.bufferingStates.add(false);
      backend.errorMessages.add('decoder failed');

      expect(controller.state.status, PlaybackStatus.error);
      expect(controller.state.errorMessage, 'decoder failed');
      expect(controller.state.isLoading, isFalse);
    });

    test('stop unloads media and play reopens the current track', () async {
      const track = Track(id: 'song-1', title: 'Song');
      await controller.select(track);

      await controller.stop();

      expect(backend.stopCalls, 1);
      expect(controller.state.status, PlaybackStatus.stopped);
      expect(controller.state.position, Duration.zero);

      await controller.play();

      expect(backend.openedUris, hasLength(2));
      expect(controller.state.status, PlaybackStatus.playing);
    });

    test('completed sequential queue stops at the final item', () async {
      const track = Track(
        id: 'song-1',
        title: 'Song',
        durationSeconds: 30,
      );
      controller.setPlaybackMode(PlaybackMode.sequential);
      await controller.select(track);
      backend.completedStates.add(true);

      expect(controller.state.status, PlaybackStatus.completed);
      expect(controller.state.position, const Duration(seconds: 30));

      await _flushAsync();

      expect(backend.seekPositions, isEmpty);
      expect(backend.playCalls, 0);
      expect(controller.state.position, const Duration(seconds: 30));
      expect(controller.state.status, PlaybackStatus.completed);
    });

    test('completed playback advances in sequential mode', () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
      ];
      controller.setPlaybackMode(PlaybackMode.sequential);
      await controller.setQueue(tracks);

      backend.completedStates.add(true);
      await _flushAsync();

      expect(controller.state.currentTrack, same(tracks[1]));
      expect(controller.state.currentIndex, 1);
      expect(backend.openedUris, hasLength(2));
      expect(controller.state.status, PlaybackStatus.playing);
    });

    test('default list loop advances then wraps after completion', () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
      ];
      await controller.setQueue(tracks);

      expect(controller.state.playbackMode, PlaybackMode.listLoop);

      backend.completedStates.add(true);
      await _flushAsync();

      expect(controller.state.currentTrack, same(tracks[1]));
      expect(controller.state.currentIndex, 1);

      backend.completedStates.add(true);
      await _flushAsync();

      expect(controller.state.currentTrack, same(tracks[0]));
      expect(controller.state.currentIndex, 0);
      expect(controller.state.status, PlaybackStatus.playing);
    });

    test('repeat-one completion restarts without changing queue item',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
      ];
      await controller.setQueue(tracks);
      controller.setPlaybackMode(PlaybackMode.repeatOne);

      backend.completedStates.add(true);
      await _flushAsync();

      expect(controller.state.currentTrack, same(tracks[0]));
      expect(controller.state.currentIndex, 0);
      expect(backend.openedUris, hasLength(1));
      expect(backend.seekPositions.last, Duration.zero);
      expect(backend.playCalls, 1);
    });

    test('shuffle next avoids the current item and previous uses history',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
        Track(id: 'third', title: 'Third'),
        Track(id: 'fourth', title: 'Fourth'),
      ];
      await controller.setQueue(tracks);
      controller.setPlaybackMode(PlaybackMode.shuffle);

      final visitedTrackIds = <String>{tracks[0].id};
      for (var index = 0; index < tracks.length - 1; index++) {
        await controller.next();
        visitedTrackIds.add(controller.state.currentTrack!.id);
      }
      final lastShuffledTrack = controller.state.currentTrack;

      expect(visitedTrackIds, hasLength(tracks.length));
      await controller.previous();
      expect(controller.state.currentTrack, isNot(same(lastShuffledTrack)));
    });

    test('cycles playback modes in UI order', () {
      expect(controller.state.playbackMode, PlaybackMode.repeatAll);
      expect(controller.cyclePlaybackMode(), PlaybackMode.repeatOne);
      expect(controller.cyclePlaybackMode(), PlaybackMode.shuffle);
      expect(controller.cyclePlaybackMode(), PlaybackMode.sequential);
      expect(controller.cyclePlaybackMode(), PlaybackMode.repeatAll);
    });

    test('previous switches to the prior item in one click past the threshold',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First', durationSeconds: 30),
        Track(id: 'second', title: 'Second', durationSeconds: 30),
      ];
      await controller.setQueue(tracks, initialIndex: 1);
      backend.positions.add(const Duration(seconds: 5));

      await controller.previous();

      expect(controller.state.currentTrack, same(tracks[0]));
      expect(controller.state.currentIndex, 0);
      expect(backend.seekPositions, isEmpty);
    });

    test(
        'previous switches to the prior item in one click before the threshold',
        () async {
      const tracks = [
        Track(id: 'first', title: 'First', durationSeconds: 30),
        Track(id: 'second', title: 'Second', durationSeconds: 30),
      ];
      await controller.setQueue(tracks, initialIndex: 1);
      backend.positions.add(const Duration(seconds: 1));

      await controller.previous();

      expect(controller.state.currentTrack, same(tracks[0]));
      expect(controller.state.currentIndex, 0);
      expect(backend.seekPositions, isEmpty);
    });

    test('next advances to the following item without regressing', () async {
      const tracks = [
        Track(id: 'first', title: 'First'),
        Track(id: 'second', title: 'Second'),
        Track(id: 'third', title: 'Third'),
      ];
      await controller.setQueue(tracks, initialIndex: 0, autoplay: false);

      await controller.next();

      expect(controller.state.currentTrack, same(tracks[1]));
      expect(controller.state.currentIndex, 1);

      await controller.next();

      expect(controller.state.currentTrack, same(tracks[2]));
      expect(controller.state.currentIndex, 2);
    });

    test('queue operations preserve the active item and support clearing',
        () async {
      const first = Track(id: 'first', title: 'First');
      const second = Track(id: 'second', title: 'Second');
      const third = Track(id: 'third', title: 'Third');
      const fourth = Track(id: 'fourth', title: 'Fourth');
      const fifth = Track(id: 'fifth', title: 'Fifth');
      await controller.setQueue(
        const [first, second, third],
        initialIndex: 1,
        autoplay: false,
      );

      expect(await controller.playNext(fourth), isTrue);
      expect(controller.state.queue, [first, second, fourth, third]);
      expect(await controller.addToQueue(fifth), isTrue);
      expect(
        controller.state.queue,
        [first, second, fourth, third, fifth],
      );

      expect(await controller.moveQueueItem(4, 0), isTrue);
      expect(
        controller.state.queue,
        [fifth, first, second, fourth, third],
      );
      expect(controller.state.currentTrack, same(second));
      expect(controller.state.currentIndex, 2);

      expect(await controller.removeFromQueue(first.id), isTrue);
      expect(controller.state.currentIndex, 1);
      expect(await controller.removeFromQueue(second), isTrue);
      expect(controller.state.currentTrack, same(fourth));
      expect(controller.state.status, PlaybackStatus.paused);

      await controller.clearQueue();
      expect(controller.state.queue, isEmpty);
      expect(controller.state.currentTrack, isNull);
      expect(controller.state.status, PlaybackStatus.idle);
    });

    test('playNow inserts a new item after the active item', () async {
      const first = Track(id: 'first', title: 'First');
      const second = Track(id: 'second', title: 'Second');
      const inserted = Track(id: 'inserted', title: 'Inserted');
      await controller.setQueue(
        const [first, second],
        autoplay: false,
      );

      await controller.playNow(inserted, autoplay: false);
      await controller.next(autoplay: false);

      expect(controller.state.queue, [first, inserted, second]);
      expect(controller.state.currentTrack, same(second));
    });

    test('restores and clears the queue through SharedPreferences', () async {
      const tracks = [
        Track(
          id: 'first',
          title: 'First',
          artist: 'Artist',
          genres: ['Rock'],
        ),
        Track(id: 'second', title: 'Second'),
      ];
      await controller.setQueue(tracks, autoplay: false);

      final restoredBackend = _FakeAudioPlayerBackend();
      final restoredController = PlayerController(
        backend: restoredBackend,
        serverBaseUrl: () => 'http://10.0.2.2:8080',
      );
      addTearDown(restoredController.dispose);
      await restoredController.restoreQueue();

      expect(restoredController.state.queue, hasLength(2));
      expect(restoredController.state.queue.first.id, 'first');
      expect(restoredController.state.queue.first.artist, 'Artist');
      expect(restoredController.state.currentTrack, isNull);

      await restoredController.clearQueue();
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.containsKey(playerQueuePreferencesKey), isFalse);
    });
  });
}

Future<void> _flushAsync() => Future<void>.delayed(Duration.zero);

class _FakeAudioPlayerBackend implements AudioPlayerBackend {
  final playingStates = StreamController<bool>.broadcast(sync: true);
  final bufferingStates = StreamController<bool>.broadcast(sync: true);
  final completedStates = StreamController<bool>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration>.broadcast(sync: true);
  final errorMessages = StreamController<String>.broadcast(sync: true);

  final List<Uri> openedUris = [];
  final List<bool> openPlayValues = [];
  final List<Duration> seekPositions = [];
  int playCalls = 0;
  int pauseCalls = 0;
  int stopCalls = 0;

  @override
  Stream<bool> get playing => playingStates.stream;

  @override
  Stream<bool> get buffering => bufferingStates.stream;

  @override
  Stream<bool> get completed => completedStates.stream;

  @override
  Stream<Duration> get position => positions.stream;

  @override
  Stream<Duration> get duration => durations.stream;

  @override
  Stream<String> get errors => errorMessages.stream;

  @override
  Future<void> open(Uri uri, {required bool play}) async {
    openedUris.add(uri);
    openPlayValues.add(play);
  }

  @override
  Future<void> play() async {
    playCalls++;
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }

  @override
  Future<void> seek(Duration position) async {
    seekPositions.add(position);
  }

  @override
  Future<void> dispose() async {
    await Future.wait([
      playingStates.close(),
      bufferingStates.close(),
      completedStates.close(),
      positions.close(),
      durations.close(),
      errorMessages.close(),
    ]);
  }
}

class _FakeOfflinePlaybackSourceResolver
    implements OfflinePlaybackSourceResolver {
  _FakeOfflinePlaybackSourceResolver(this.uri);

  final Uri? uri;

  @override
  Future<Uri?> resolve(String trackId) async => uri;
}
