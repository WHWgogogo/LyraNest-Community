import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../data/listening_api.dart';
import '../data/listening_outbox_store.dart';
import '../domain/listening_event.dart';

abstract interface class ListeningPlaybackTracker {
  void onPlaybackStarted(String trackId);

  void onPlaybackPaused();

  void onPlaybackStopped();

  void onPlaybackCompleted();

  Future<void> flushOutbox();
}

class NoopListeningPlaybackTracker implements ListeningPlaybackTracker {
  const NoopListeningPlaybackTracker();

  @override
  Future<void> flushOutbox() async {}

  @override
  void onPlaybackCompleted() {}

  @override
  void onPlaybackPaused() {}

  @override
  void onPlaybackStarted(String trackId) {}

  @override
  void onPlaybackStopped() {}
}

final listeningOutboxStoreProvider = Provider<ListeningOutboxStore>((ref) {
  final stores = ref.watch(_listeningOutboxStoreFactoryProvider);
  return _CurrentSessionListeningOutboxStore(stores.current);
});

final listeningTrackerProvider = Provider<ListeningPlaybackTracker>((ref) {
  final stores = ref.watch(_listeningOutboxStoreFactoryProvider);
  final tracker = ListeningTracker(
    outbox: ref.watch(listeningOutboxStoreProvider),
    api: ref.watch(listeningApiProvider),
    currentOutbox: stores.current,
  );
  final retryTimer = Timer.periodic(
    const Duration(minutes: 1),
    (_) => unawaited(tracker.flushOutbox()),
  );
  ref.onDispose(() {
    retryTimer.cancel();
    tracker.dispose();
  });
  unawaited(tracker.flushOutbox());
  return tracker;
});

final _listeningOutboxStoreFactoryProvider =
    Provider<_SessionListeningOutboxStoreFactory>((ref) {
  return _SessionListeningOutboxStoreFactory(
    session: () => ref.read(authControllerProvider).valueOrNull?.session,
  );
});

class ListeningTracker implements ListeningPlaybackTracker {
  ListeningTracker({
    required ListeningOutboxStore outbox,
    required ListeningApi api,
    DateTime Function()? now,
    String Function()? eventIdGenerator,
    ListeningOutboxStore? Function()? currentOutbox,
  })  : _outbox = outbox,
        _api = api,
        _now = now ?? DateTime.now,
        _eventIdGenerator = eventIdGenerator ?? _newEventId,
        _currentOutbox = currentOutbox;

  final ListeningOutboxStore _outbox;
  final ListeningApi _api;
  final DateTime Function() _now;
  final String Function() _eventIdGenerator;
  final ListeningOutboxStore? Function()? _currentOutbox;

  Future<void> _operationTail = Future<void>.value();
  ListeningOutboxStore? _activeOutbox;
  String? _activeTrackId;
  DateTime? _playedAt;
  DateTime? _segmentStartedAt;
  int _listenedMs = 0;
  bool _isPlaying = false;
  bool _completed = false;

  @override
  void onPlaybackStarted(String trackId) {
    final normalizedTrackId = trackId.trim();
    if (normalizedTrackId.isEmpty) {
      return;
    }
    if (_activeTrackId != null && _activeTrackId != normalizedTrackId) {
      _finish(completed: false);
      _clearActiveTrack();
    }
    if (_activeTrackId == null || _completed) {
      _activeTrackId = normalizedTrackId;
      _completed = false;
      _activeOutbox = _outboxForCurrentSession();
    }
    if (_isPlaying) {
      return;
    }
    final now = _now().toUtc();
    _playedAt ??= now;
    _segmentStartedAt = now;
    _isPlaying = true;
  }

  @override
  void onPlaybackPaused() {
    if (!_isPlaying) {
      return;
    }
    _accumulateSegment();
    _isPlaying = false;
    _finish(completed: false);
  }

  @override
  void onPlaybackStopped() {
    if (_activeTrackId == null) {
      return;
    }
    _accumulateSegment();
    _isPlaying = false;
    _finish(completed: false);
    _clearActiveTrack();
  }

  @override
  void onPlaybackCompleted() {
    if (_activeTrackId == null || _completed) {
      return;
    }
    _accumulateSegment();
    _isPlaying = false;
    _completed = true;
    _finish(completed: true);
    _clearActiveTrack();
  }

  @override
  Future<void> flushOutbox() {
    return _schedule(_flushPendingEvents);
  }

  void dispose() {
    onPlaybackStopped();
    unawaited(flushOutbox());
  }

  void _accumulateSegment() {
    final startedAt = _segmentStartedAt;
    if (startedAt == null) {
      return;
    }
    final elapsed = _now().toUtc().difference(startedAt).inMilliseconds;
    _listenedMs += max(0, elapsed);
    _segmentStartedAt = null;
  }

  void _finish({required bool completed}) {
    final trackId = _activeTrackId;
    final playedAt = _playedAt;
    if (trackId == null || playedAt == null) {
      return;
    }
    final event = ListeningEvent(
      eventId: _eventIdGenerator(),
      trackId: trackId,
      listenedMs: _listenedMs,
      completed: completed,
      playedAt: playedAt,
    );
    _playedAt = null;
    _segmentStartedAt = null;
    _listenedMs = 0;
    final activeOutbox = _activeOutbox;
    if (activeOutbox == null) {
      return;
    }
    unawaited(
      _schedule(() async {
        await activeOutbox.enqueue(event);
        await _flushPendingEvents();
      }).catchError((Object _) {}),
    );
  }

  void _clearActiveTrack() {
    _activeTrackId = null;
    _playedAt = null;
    _segmentStartedAt = null;
    _listenedMs = 0;
    _isPlaying = false;
    _activeOutbox = null;
  }

  Future<void> _schedule(Future<void> Function() operation) {
    final next = _operationTail.then((_) => operation());
    _operationTail = next.catchError((Object _) {});
    return next;
  }

  Future<void> _flushPendingEvents() async {
    final outbox = _outboxForCurrentSession();
    if (outbox == null) {
      return;
    }

    while (true) {
      final events = await outbox.read(limit: 50);
      if (events.isEmpty) {
        return;
      }
      if (!_isCurrentOutbox(outbox)) {
        return;
      }
      try {
        await _api.submitEvents(events);
      } catch (_) {
        return;
      }
      if (!_isCurrentOutbox(outbox)) {
        return;
      }
      await outbox.removeByIds(events.map((event) => event.eventId).toSet());
      if (events.length < 50) {
        return;
      }
    }
  }

  ListeningOutboxStore? _outboxForCurrentSession() {
    return _currentOutbox?.call() ?? _outbox;
  }

  bool _isCurrentOutbox(ListeningOutboxStore outbox) {
    return identical(outbox, _outboxForCurrentSession());
  }
}

String _newEventId() {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  final random = Random.secure().nextInt(1 << 32).toRadixString(16);
  return 'listen-$timestamp-${random.padLeft(8, '0')}';
}

class _SessionListeningOutboxStoreFactory {
  _SessionListeningOutboxStoreFactory({
    required AuthSession? Function() session,
  }) : _session = session;

  final AuthSession? Function() _session;
  final Map<ListeningOutboxScope, ListeningOutboxStore> _stores = {};

  ListeningOutboxStore? current() {
    final session = _session();
    if (session == null) {
      return null;
    }

    try {
      final scope = ListeningOutboxScope(
        serverBaseUrl: session.serverBaseUrl,
        userId: session.username,
      );
      return _stores.putIfAbsent(
        scope,
        () => SharedPreferencesListeningOutboxStore(
          serverBaseUrl: scope.serverBaseUrl,
          userId: scope.userId,
        ),
      );
    } on ArgumentError {
      return null;
    }
  }
}

class _CurrentSessionListeningOutboxStore implements ListeningOutboxStore {
  const _CurrentSessionListeningOutboxStore(this._currentOutbox);

  final ListeningOutboxStore? Function() _currentOutbox;

  @override
  Future<void> enqueue(ListeningEvent event) async {
    final outbox = _currentOutbox();
    if (outbox != null) {
      await outbox.enqueue(event);
    }
  }

  @override
  Future<List<ListeningEvent>> read({int limit = 50}) async {
    final outbox = _currentOutbox();
    if (outbox == null) {
      return const [];
    }
    return outbox.read(limit: limit);
  }

  @override
  Future<void> removeByIds(Set<String> eventIds) async {
    final outbox = _currentOutbox();
    if (outbox != null) {
      await outbox.removeByIds(eventIds);
    }
  }
}
