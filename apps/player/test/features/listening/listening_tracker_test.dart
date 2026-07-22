import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/listening/application/listening_tracker.dart';
import 'package:player/features/listening/data/listening_api.dart';
import 'package:player/features/listening/data/listening_outbox_store.dart';
import 'package:player/features/listening/domain/listening_event.dart';

void main() {
  group('ListeningTracker', () {
    test('records one idempotent pause event for active playback', () async {
      var clock = DateTime.utc(2026, 7, 20, 12);
      final outbox = _MemoryOutboxStore();
      final api = _RecordingListeningApi();
      final tracker = ListeningTracker(
        outbox: outbox,
        api: api,
        now: () => clock,
        eventIdGenerator: () => 'event-1',
      );

      tracker.onPlaybackStarted('track-1');
      clock = clock.add(const Duration(seconds: 12));
      tracker.onPlaybackPaused();
      tracker.onPlaybackPaused();
      await tracker.flushOutbox();

      expect(api.batches, hasLength(1));
      final event = api.batches.single.single;
      expect(event.eventId, 'event-1');
      expect(event.trackId, 'track-1');
      expect(event.listenedMs, 12000);
      expect(event.completed, isFalse);
      expect(event.playedAt, DateTime.utc(2026, 7, 20, 12));
      expect(await outbox.read(), isEmpty);
    });

    test('keeps events locally while offline and retries in batches of fifty',
        () async {
      final outbox = _MemoryOutboxStore();
      for (var index = 0; index < 51; index++) {
        await outbox.enqueue(
          ListeningEvent(
            eventId: 'event-$index',
            trackId: 'track-$index',
            listenedMs: 1000,
            completed: false,
            playedAt: DateTime.utc(2026, 7, 20),
          ),
        );
      }
      final api = _RecordingListeningApi(failRequests: true);
      final tracker = ListeningTracker(outbox: outbox, api: api);

      await tracker.flushOutbox();
      expect((await outbox.read(limit: 100)).length, 51);

      api.failRequests = false;
      await tracker.flushOutbox();

      expect(api.batches.map((batch) => batch.length), [50, 50, 1]);
      expect(await outbox.read(limit: 100), isEmpty);
    });

    test('flushes a completed event before beginning the next track', () async {
      var clock = DateTime.utc(2026, 7, 20, 12);
      final api = _RecordingListeningApi();
      final tracker = ListeningTracker(
        outbox: _MemoryOutboxStore(),
        api: api,
        now: () => clock,
        eventIdGenerator: () => 'completed-event',
      );

      tracker.onPlaybackStarted('track-1');
      clock = clock.add(const Duration(minutes: 3));
      tracker.onPlaybackCompleted();
      tracker.onPlaybackStarted('track-2');
      await tracker.flushOutbox();

      final event = api.batches.single.single;
      expect(event.trackId, 'track-1');
      expect(event.listenedMs, const Duration(minutes: 3).inMilliseconds);
      expect(event.completed, isTrue);
    });

    test('keeps an active playback event in its original account outbox',
        () async {
      var clock = DateTime.utc(2026, 7, 20, 12);
      final aliceOutbox = _MemoryOutboxStore();
      final bobOutbox = _MemoryOutboxStore();
      var currentOutbox = aliceOutbox;
      final api = _RecordingListeningApi();
      final tracker = ListeningTracker(
        outbox: aliceOutbox,
        currentOutbox: () => currentOutbox,
        api: api,
        now: () => clock,
        eventIdGenerator: () => 'alice-event',
      );

      tracker.onPlaybackStarted('track-1');
      clock = clock.add(const Duration(seconds: 10));
      currentOutbox = bobOutbox;
      tracker.onPlaybackPaused();
      await tracker.flushOutbox();

      expect(await aliceOutbox.read(), hasLength(1));
      expect(await bobOutbox.read(), isEmpty);
      expect(api.batches, isEmpty);

      currentOutbox = aliceOutbox;
      await tracker.flushOutbox();

      expect(api.batches.single.single.eventId, 'alice-event');
      expect(await aliceOutbox.read(), isEmpty);
    });
  });
}

class _MemoryOutboxStore implements ListeningOutboxStore {
  final List<ListeningEvent> events = [];

  @override
  Future<void> enqueue(ListeningEvent event) async {
    if (events.any((item) => item.eventId == event.eventId)) {
      return;
    }
    events.add(event);
  }

  @override
  Future<List<ListeningEvent>> read({int limit = 50}) async {
    return List<ListeningEvent>.unmodifiable(events.take(limit));
  }

  @override
  Future<void> removeByIds(Set<String> eventIds) async {
    events.removeWhere((event) => eventIds.contains(event.eventId));
  }
}

class _RecordingListeningApi implements ListeningApi {
  _RecordingListeningApi({this.failRequests = false});

  bool failRequests;
  final List<List<ListeningEvent>> batches = [];

  @override
  Future<void> submitEvents(List<ListeningEvent> events) async {
    batches.add(List<ListeningEvent>.unmodifiable(events));
    if (failRequests) {
      throw StateError('offline');
    }
  }
}
