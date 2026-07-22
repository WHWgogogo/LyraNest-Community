import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../auth/application/auth_controller.dart';
import '../../listening/application/listening_tracker.dart';
import '../../offline/application/offline_playback_source_resolver.dart';
import '../../offline/application/offline_providers.dart';
import '../../tracks/domain/track.dart';
import '../domain/playback_state.dart';
import 'audio_player_backend.dart';
import 'queue_repository.dart';

final playerControllerProvider =
    StateNotifierProvider<PlayerController, PlaybackState>(
  (ref) {
    final controller = PlayerController(
      backend: MediaKitAudioPlayerBackend(),
      serverBaseUrl: () {
        return ref.read(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
      },
      queueRepository: ref.read(queueRepositoryProvider),
      offlinePlaybackSourceResolver:
          ref.read(offlinePlaybackSourceResolverProvider),
      isOfflineAuthenticated: () {
        return ref
                .read(authControllerProvider)
                .valueOrNull
                ?.isOfflineAuthenticated ??
            false;
      },
      listeningTracker: ref.read(listeningTrackerProvider),
    );
    unawaited(controller.restoreQueue());
    return controller;
  },
);

class PlayerController extends StateNotifier<PlaybackState> {
  PlayerController({
    required AudioPlayerBackend backend,
    required String Function() serverBaseUrl,
    Random? random,
    QueueRepository? queueRepository,
    OfflinePlaybackSourceResolver? offlinePlaybackSourceResolver,
    bool Function()? isOfflineAuthenticated,
    ListeningPlaybackTracker? listeningTracker,
  })  : _backend = backend,
        _serverBaseUrl = serverBaseUrl,
        _random = random ?? Random(),
        _queueRepository =
            queueRepository ?? SharedPreferencesQueueRepository(),
        _offlinePlaybackSourceResolver = offlinePlaybackSourceResolver ??
            _NoopOfflinePlaybackSourceResolver(),
        _isOfflineAuthenticated = isOfflineAuthenticated ?? _alwaysOnline,
        _listeningTracker =
            listeningTracker ?? const NoopListeningPlaybackTracker(),
        super(const PlaybackState()) {
    _subscriptions.addAll([
      _backend.playing.listen(_handlePlaying),
      _backend.buffering.listen(_handleBuffering),
      _backend.completed.listen(_handleCompleted),
      _backend.position.listen(_handlePosition),
      _backend.duration.listen(_handleDuration),
      _backend.errors.listen(_handleError),
    ]);
  }

  final AudioPlayerBackend _backend;
  final String Function() _serverBaseUrl;
  final Random _random;
  final QueueRepository _queueRepository;
  final OfflinePlaybackSourceResolver _offlinePlaybackSourceResolver;
  final bool Function() _isOfflineAuthenticated;
  final ListeningPlaybackTracker _listeningTracker;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<int> _shuffleHistory = [];
  final List<int> _shuffleRemaining = [];

  int _mediaOperation = 0;
  int _queueRevision = 0;
  int _shuffleHistoryIndex = -1;
  bool _isDisposed = false;
  bool _usingLocalSource = false;
  Future<void> _queuePersistence = Future.value();

  Future<void> restoreQueue() async {
    final revision = _queueRevision;
    List<Track> queue;
    try {
      queue = await _queueRepository.loadQueue();
    } catch (_) {
      return;
    }
    if (_isDisposed ||
        revision != _queueRevision ||
        state.queue.isNotEmpty ||
        queue.isEmpty) {
      return;
    }

    final restoredQueue = List<Track>.unmodifiable(queue);
    state = PlaybackState(
      queue: restoredQueue,
      playbackMode: state.playbackMode,
    );
    _resetShuffleHistory(-1, restoredQueue.length);
  }

  Future<void> select(
    Track track, {
    Iterable<Track>? queue,
    bool autoplay = true,
  }) async {
    final nextQueue = List<Track>.of(queue ?? state.queue, growable: true);
    var selectedIndex = _indexOfTrack(nextQueue, track);
    if (selectedIndex >= 0) {
      nextQueue[selectedIndex] = track;
    } else {
      if (queue == null && nextQueue.isNotEmpty && state.currentTrack != null) {
        selectedIndex = min(_resolvedCurrentIndex() + 1, nextQueue.length);
        nextQueue.insert(selectedIndex, track);
      } else {
        nextQueue.add(track);
        selectedIndex = nextQueue.length - 1;
      }
    }

    await _selectQueueTrack(
      queue: List<Track>.unmodifiable(nextQueue),
      index: selectedIndex,
      autoplay: autoplay,
      resetShuffleHistory: true,
    );
  }

  Future<void> playNow(
    Track track, {
    Iterable<Track>? queue,
    bool autoplay = true,
  }) {
    return select(track, queue: queue, autoplay: autoplay);
  }

  Future<void> setQueue(
    Iterable<Track> tracks, {
    int initialIndex = 0,
    bool autoplay = true,
  }) async {
    final queue = List<Track>.unmodifiable(tracks);
    if (queue.isEmpty) {
      await clearQueue();
      return;
    }
    _checkQueueIndex(initialIndex, queue.length);
    await _selectQueueTrack(
      queue: queue,
      index: initialIndex,
      autoplay: autoplay,
      resetShuffleHistory: true,
    );
  }

  Future<void> selectQueueIndex(
    int index, {
    bool autoplay = true,
  }) async {
    _checkQueueIndex(index, state.queue.length);
    await _selectQueueTrack(
      queue: state.queue,
      index: index,
      autoplay: autoplay,
      resetShuffleHistory: true,
    );
  }

  Future<void> next({bool autoplay = true}) async {
    final queue = state.queue;
    if (queue.isEmpty) {
      return;
    }

    if (state.currentTrack == null) {
      await _selectQueueTrack(
        queue: queue,
        index: 0,
        autoplay: autoplay,
        resetShuffleHistory: true,
      );
      return;
    }

    final currentIndex = _resolvedCurrentIndex();
    final nextIndex = _nextIndex(
      queueLength: queue.length,
      currentIndex: currentIndex,
      wrapSequential: state.playbackMode == PlaybackMode.repeatAll,
    );
    if (nextIndex == null || nextIndex == currentIndex) {
      return;
    }
    await _selectQueueTrack(
      queue: queue,
      index: nextIndex,
      autoplay: autoplay,
      resetShuffleHistory: false,
    );
  }

  Future<void> previous({bool autoplay = true}) async {
    final queue = state.queue;
    if (queue.isEmpty) {
      return;
    }

    if (state.currentTrack == null) {
      await _selectQueueTrack(
        queue: queue,
        index: 0,
        autoplay: autoplay,
        resetShuffleHistory: true,
      );
      return;
    }

    final currentIndex = _resolvedCurrentIndex();
    final previousIndex = _previousIndex(
      queueLength: queue.length,
      currentIndex: currentIndex,
    );
    if (previousIndex == null || previousIndex == currentIndex) {
      if (state.position > Duration.zero) {
        await _restartCurrentTrack(autoplay: autoplay);
      }
      return;
    }
    await _selectQueueTrack(
      queue: queue,
      index: previousIndex,
      autoplay: autoplay,
      resetShuffleHistory: false,
    );
  }

  void setPlaybackMode(PlaybackMode mode) {
    if (_isDisposed || state.playbackMode == mode) {
      return;
    }
    state = state.copyWith(playbackMode: mode);
    _resetShuffleHistory(state.currentIndex, state.queue.length);
  }

  PlaybackMode cyclePlaybackMode() {
    const modes = [
      PlaybackMode.sequential,
      PlaybackMode.repeatAll,
      PlaybackMode.repeatOne,
      PlaybackMode.shuffle,
    ];
    final currentModeIndex = modes.indexOf(state.playbackMode);
    final nextMode = modes[(currentModeIndex + 1) % modes.length];
    setPlaybackMode(nextMode);
    return nextMode;
  }

  Future<bool> playNext(Track track) async {
    final queue = List<Track>.of(state.queue, growable: true);
    var currentIndex =
        state.currentTrack == null ? -1 : _resolvedCurrentIndex();
    final existingIndex = _indexOfTrack(queue, track);
    if (existingIndex == currentIndex && currentIndex >= 0) {
      queue[existingIndex] = track;
      state = state.copyWith(
        currentTrack: track,
        queue: List.unmodifiable(queue),
      );
      _markQueueChanged();
      await _persistQueue(queue);
      return false;
    }
    if (existingIndex >= 0) {
      queue.removeAt(existingIndex);
      if (existingIndex < currentIndex) {
        currentIndex--;
      }
    }

    final insertionIndex =
        currentIndex < 0 ? 0 : min(currentIndex + 1, queue.length);
    queue.insert(insertionIndex, track);
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: currentIndex,
    );
    _markQueueChanged();
    await _persistQueue(queue);
    return true;
  }

  Future<bool> addToQueue(Track track) async {
    final queue = List<Track>.of(state.queue, growable: true);
    final existingIndex = _indexOfTrack(queue, track);
    if (existingIndex >= 0) {
      queue[existingIndex] = track;
      state = state.copyWith(
        currentTrack:
            existingIndex == state.currentIndex ? track : state.currentTrack,
        queue: List.unmodifiable(queue),
      );
      _markQueueChanged();
      await _persistQueue(queue);
      return false;
    }

    queue.add(track);
    state = state.copyWith(queue: List.unmodifiable(queue));
    _markQueueChanged();
    await _persistQueue(queue);
    return true;
  }

  Future<bool> removeFromQueue(Object trackOrId) async {
    final queue = List<Track>.of(state.queue, growable: true);
    final index = _resolveQueueItemIndex(queue, trackOrId);
    if (index < 0) {
      return false;
    }

    final currentIndex =
        state.currentTrack == null ? -1 : _resolvedCurrentIndex();
    final removingCurrent = currentIndex == index;
    queue.removeAt(index);
    if (queue.isEmpty) {
      await clearQueue();
      return true;
    }

    if (removingCurrent) {
      final replacementIndex = min(index, queue.length - 1);
      final autoplay =
          state.isPlaying || state.status == PlaybackStatus.loading;
      await _selectQueueTrack(
        queue: List.unmodifiable(queue),
        index: replacementIndex,
        autoplay: autoplay,
        resetShuffleHistory: true,
      );
      return true;
    }

    final nextCurrentIndex =
        currentIndex > index ? currentIndex - 1 : currentIndex;
    state = state.copyWith(
      queue: List.unmodifiable(queue),
      currentIndex: nextCurrentIndex,
    );
    _markQueueChanged();
    await _persistQueue(queue);
    return true;
  }

  Future<bool> moveQueueItem(int oldIndex, int newIndex) async {
    final queue = List<Track>.of(state.queue, growable: true);
    _checkQueueIndex(oldIndex, queue.length);
    if (newIndex < 0 || newIndex > queue.length) {
      throw RangeError.range(newIndex, 0, queue.length, 'newIndex');
    }

    final targetIndex = min(newIndex, queue.length - 1);
    if (oldIndex == targetIndex) {
      return false;
    }

    final currentTrack = state.currentTrack;
    final item = queue.removeAt(oldIndex);
    queue.insert(min(newIndex, queue.length), item);
    final nextCurrentIndex =
        currentTrack == null ? -1 : _indexOfIdenticalTrack(queue, currentTrack);
    state = state.copyWith(
      currentTrack: nextCurrentIndex < 0 ? null : queue[nextCurrentIndex],
      queue: List.unmodifiable(queue),
      currentIndex: nextCurrentIndex,
      clearTrack: nextCurrentIndex < 0,
    );
    _markQueueChanged();
    await _persistQueue(queue);
    return true;
  }

  Future<void> clearQueue() async {
    ++_mediaOperation;
    _listeningTracker.onPlaybackStopped();
    final playbackMode = state.playbackMode;
    state = PlaybackState(playbackMode: playbackMode);
    _markQueueChanged();
    try {
      await Future.wait([
        _backend.stop(),
        _clearPersistedQueue(),
      ]);
    } catch (_) {
      if (!_isDisposed) {
        state = PlaybackState(playbackMode: playbackMode);
      }
    }
  }

  Future<void> _selectQueueTrack({
    required List<Track> queue,
    required int index,
    required bool autoplay,
    required bool resetShuffleHistory,
  }) async {
    _checkQueueIndex(index, queue.length);
    final track = queue[index];
    if (state.currentTrack?.id == track.id &&
        state.status != PlaybackStatus.stopped &&
        state.status != PlaybackStatus.error) {
      _queueRevision++;
      if (resetShuffleHistory) {
        _resetShuffleHistory(index, queue.length);
      }
      state = state.copyWith(
        currentTrack: track,
        queue: queue,
        currentIndex: index,
      );
      await _persistQueue(queue);
      return;
    }

    final operation = ++_mediaOperation;
    if (state.currentTrack != null && state.currentTrack!.id != track.id) {
      _listeningTracker.onPlaybackStopped();
    }
    _queueRevision++;
    if (resetShuffleHistory) {
      _resetShuffleHistory(index, queue.length);
    }
    state = PlaybackState(
      currentTrack: track,
      queue: queue,
      currentIndex: index,
      playbackMode: state.playbackMode,
      status: PlaybackStatus.loading,
      duration: _trackDuration(track),
    );
    final persistence = _persistQueue(queue);

    try {
      Uri? localUri;
      try {
        localUri = await _offlinePlaybackSourceResolver.resolve(track.id);
      } catch (_) {
        localUri = null;
      }
      if (!_isCurrent(operation)) {
        return;
      }
      if (localUri == null && _isOfflineAuthenticated()) {
        throw OfflinePlaybackUnavailableException(track);
      }
      _usingLocalSource = localUri != null;
      await _backend.open(
        localUri ??
            buildTrackStreamUri(
              baseUrl: _serverBaseUrl(),
              trackId: track.id,
            ),
        play: autoplay,
      );
      if (!_isCurrent(operation) || state.hasError) {
        return;
      }

      state = state.copyWith(
        status: autoplay ? PlaybackStatus.playing : PlaybackStatus.paused,
        clearError: true,
      );
      if (autoplay) {
        _listeningTracker.onPlaybackStarted(track.id);
      }
    } catch (error) {
      _setOperationError(operation, error);
    } finally {
      await persistence;
    }
  }

  Future<void> play() async {
    final track = state.currentTrack;
    if (track == null || state.status == PlaybackStatus.loading) {
      return;
    }

    if (state.status == PlaybackStatus.stopped ||
        state.status == PlaybackStatus.error) {
      await select(track);
      return;
    }

    try {
      if (state.status == PlaybackStatus.completed) {
        await _backend.seek(Duration.zero);
      }
      await _backend.play();
      if (!_isDisposed) {
        state = state.copyWith(
          status: PlaybackStatus.playing,
          position: state.status == PlaybackStatus.completed
              ? Duration.zero
              : state.position,
          clearError: true,
        );
        _listeningTracker.onPlaybackStarted(track.id);
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> pause() async {
    if (state.currentTrack == null ||
        state.status == PlaybackStatus.loading ||
        !state.isPlaying) {
      return;
    }

    try {
      await _backend.pause();
      if (!_isDisposed) {
        state = state.copyWith(status: PlaybackStatus.paused);
        _listeningTracker.onPlaybackPaused();
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> stop() async {
    if (state.currentTrack == null) {
      return;
    }

    ++_mediaOperation;
    _listeningTracker.onPlaybackStopped();
    try {
      await _backend.stop();
      if (!_isDisposed) {
        state = state.copyWith(
          status: PlaybackStatus.stopped,
          position: Duration.zero,
          isBuffering: false,
          clearError: true,
        );
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> seek(Duration position) async {
    if (!state.canSeek) {
      return;
    }

    final target = _clampPosition(position, state.duration);
    try {
      await _backend.seek(target);
      if (!_isDisposed) {
        state = state.copyWith(position: target);
      }
    } catch (error) {
      _setError(error);
    }
  }

  Future<void> clear() => clearQueue();

  void _handlePlaying(bool playing) {
    if (_isDisposed || state.currentTrack == null) {
      return;
    }

    if (playing) {
      state = state.copyWith(
        status: PlaybackStatus.playing,
        clearError: true,
      );
      _listeningTracker.onPlaybackStarted(state.currentTrack!.id);
    } else if (state.status == PlaybackStatus.playing) {
      state = state.copyWith(status: PlaybackStatus.paused);
      _listeningTracker.onPlaybackPaused();
    }
  }

  void _handleBuffering(bool buffering) {
    if (_isDisposed || state.currentTrack == null) {
      return;
    }
    state = state.copyWith(isBuffering: buffering);
  }

  void _handleCompleted(bool completed) {
    if (_isDisposed || !completed) {
      return;
    }
    if (state.currentTrack == null ||
        state.status == PlaybackStatus.loading ||
        state.status == PlaybackStatus.completed ||
        state.status == PlaybackStatus.stopped ||
        state.status == PlaybackStatus.error) {
      return;
    }
    state = state.copyWith(
      status: PlaybackStatus.completed,
      position: state.duration,
      isBuffering: false,
    );
    _listeningTracker.onPlaybackCompleted();
    unawaited(_advanceAfterCompletion());
  }

  Future<void> _advanceAfterCompletion() async {
    if (_isDisposed || state.currentTrack == null) {
      return;
    }

    switch (state.playbackMode) {
      case PlaybackMode.repeatOne:
        await _restartCurrentTrack(autoplay: true);
        return;
      case PlaybackMode.repeatAll:
        if (state.queue.length <= 1) {
          await _restartCurrentTrack(autoplay: true);
        } else {
          await next();
        }
        return;
      case PlaybackMode.shuffle:
        if (state.queue.length <= 1) {
          await _restartCurrentTrack(autoplay: true);
        } else {
          await next();
        }
        return;
      case PlaybackMode.sequential:
        final currentIndex = _resolvedCurrentIndex();
        if (currentIndex < state.queue.length - 1) {
          await next();
        }
        return;
    }
  }

  Future<void> _restartCurrentTrack({required bool autoplay}) async {
    final operation = ++_mediaOperation;
    try {
      await _backend.seek(Duration.zero);
      if (!_isCurrent(operation)) {
        return;
      }
      if (autoplay) {
        await _backend.play();
      } else if (state.isPlaying) {
        await _backend.pause();
      }
      if (_isCurrent(operation)) {
        state = state.copyWith(
          status: autoplay ? PlaybackStatus.playing : PlaybackStatus.paused,
          position: Duration.zero,
          isBuffering: false,
          clearError: true,
        );
        if (autoplay) {
          _listeningTracker.onPlaybackStarted(state.currentTrack!.id);
        }
      }
    } catch (error) {
      _setOperationError(operation, error);
    }
  }

  void _handlePosition(Duration position) {
    if (_isDisposed || state.currentTrack == null) {
      return;
    }
    state = state.copyWith(
      position:
          state.canSeek ? _clampPosition(position, state.duration) : position,
    );
  }

  void _handleDuration(Duration duration) {
    if (_isDisposed ||
        state.currentTrack == null ||
        duration <= Duration.zero) {
      return;
    }
    state = state.copyWith(
      duration: duration,
      position: _clampPosition(state.position, duration),
    );
  }

  void _handleError(String message) {
    if (message.trim().isEmpty) {
      return;
    }
    _setError(message);
  }

  void _setOperationError(int operation, Object error) {
    if (_isCurrent(operation)) {
      _setError(error);
    }
  }

  void _setError(Object error) {
    if (_isDisposed || state.currentTrack == null) {
      return;
    }
    _listeningTracker.onPlaybackStopped();
    final message = !_usingLocalSource && _isOfflineAuthenticated()
        ? OfflinePlaybackUnavailableException(state.currentTrack!).toString()
        : error.toString();
    state = state.copyWith(
      status: PlaybackStatus.error,
      isBuffering: false,
      errorMessage: message,
    );
  }

  bool _isCurrent(int operation) {
    return !_isDisposed && operation == _mediaOperation;
  }

  int _resolvedCurrentIndex() {
    final currentIndex = state.currentIndex;
    if (currentIndex >= 0 && currentIndex < state.queue.length) {
      return currentIndex;
    }
    final track = state.currentTrack;
    if (track == null) {
      return 0;
    }
    final queueIndex = _indexOfTrack(state.queue, track);
    return queueIndex == -1 ? 0 : queueIndex;
  }

  int? _nextIndex({
    required int queueLength,
    required int currentIndex,
    required bool wrapSequential,
  }) {
    if (state.playbackMode == PlaybackMode.shuffle) {
      return _nextShuffleIndex(queueLength, currentIndex);
    }
    if (currentIndex < queueLength - 1) {
      return currentIndex + 1;
    }
    return wrapSequential && queueLength > 1 ? 0 : null;
  }

  int? _previousIndex({
    required int queueLength,
    required int currentIndex,
  }) {
    if (state.playbackMode == PlaybackMode.shuffle) {
      return _previousShuffleIndex(queueLength, currentIndex);
    }
    if (currentIndex > 0) {
      return currentIndex - 1;
    }
    if (state.playbackMode == PlaybackMode.repeatAll && queueLength > 1) {
      return queueLength - 1;
    }
    return null;
  }

  int? _nextShuffleIndex(int queueLength, int currentIndex) {
    if (queueLength <= 1) {
      return null;
    }
    _ensureShuffleHistory(currentIndex, queueLength);
    if (_shuffleHistoryIndex < _shuffleHistory.length - 1) {
      _shuffleHistoryIndex++;
      return _shuffleHistory[_shuffleHistoryIndex];
    }

    if (_shuffleRemaining.isEmpty) {
      _shuffleRemaining.addAll(
        List.generate(queueLength, (index) => index)
            .where((index) => index != currentIndex),
      );
    }
    final remainingIndex = _random.nextInt(_shuffleRemaining.length);
    final nextIndex = _shuffleRemaining.removeAt(remainingIndex);
    _shuffleHistory.add(nextIndex);
    _shuffleHistoryIndex++;
    if (_shuffleHistory.length > 100) {
      _shuffleHistory.removeAt(0);
      _shuffleHistoryIndex--;
    }
    return nextIndex;
  }

  int? _previousShuffleIndex(int queueLength, int currentIndex) {
    if (queueLength <= 1) {
      return null;
    }
    _ensureShuffleHistory(currentIndex, queueLength);
    if (_shuffleHistoryIndex <= 0) {
      return null;
    }

    _shuffleHistoryIndex--;
    return _shuffleHistory[_shuffleHistoryIndex];
  }

  void _ensureShuffleHistory(int currentIndex, int queueLength) {
    if (_shuffleHistoryIndex < 0 ||
        _shuffleHistoryIndex >= _shuffleHistory.length ||
        _shuffleHistory[_shuffleHistoryIndex] != currentIndex) {
      _resetShuffleHistory(currentIndex, queueLength);
    }
  }

  void _resetShuffleHistory(int currentIndex, int queueLength) {
    _shuffleHistory.clear();
    _shuffleRemaining.clear();
    if (currentIndex < 0 || currentIndex >= queueLength) {
      _shuffleHistoryIndex = -1;
      return;
    }

    _shuffleHistory.add(currentIndex);
    _shuffleRemaining.addAll(
      List.generate(queueLength, (index) => index)
          .where((index) => index != currentIndex),
    );
    _shuffleHistoryIndex = 0;
  }

  void _markQueueChanged() {
    _queueRevision++;
    _resetShuffleHistory(state.currentIndex, state.queue.length);
  }

  Future<void> _persistQueue(Iterable<Track> queue) {
    final snapshot = List<Track>.unmodifiable(queue);
    _queuePersistence = _queuePersistence.then((_) async {
      try {
        await _queueRepository.saveQueue(snapshot);
      } catch (_) {}
    });
    return _queuePersistence;
  }

  Future<void> _clearPersistedQueue() {
    _queuePersistence = _queuePersistence.then((_) async {
      try {
        await _queueRepository.clearQueue();
      } catch (_) {}
    });
    return _queuePersistence;
  }

  @override
  void dispose() {
    _isDisposed = true;
    _listeningTracker.onPlaybackStopped();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    unawaited(_backend.dispose());
    super.dispose();
  }
}

class OfflinePlaybackUnavailableException implements Exception {
  OfflinePlaybackUnavailableException(this.track);

  final Track track;

  @override
  String toString() {
    return '当前处于离线状态，且“${track.title}”没有可用的本地下载。'
        '请先联网下载后再播放。';
  }
}

class _NoopOfflinePlaybackSourceResolver
    implements OfflinePlaybackSourceResolver {
  @override
  Future<Uri?> resolve(String trackId) async => null;
}

bool _alwaysOnline() => false;

int _indexOfTrack(List<Track> queue, Track track) {
  return queue.indexWhere((item) => item.id == track.id);
}

int _indexOfIdenticalTrack(List<Track> queue, Track track) {
  final identicalIndex = queue.indexWhere((item) => identical(item, track));
  return identicalIndex >= 0 ? identicalIndex : _indexOfTrack(queue, track);
}

int _resolveQueueItemIndex(List<Track> queue, Object trackOrId) {
  if (trackOrId is int) {
    return trackOrId >= 0 && trackOrId < queue.length ? trackOrId : -1;
  }
  if (trackOrId is Track) {
    return _indexOfTrack(queue, trackOrId);
  }
  if (trackOrId is String) {
    return queue.indexWhere((track) => track.id == trackOrId);
  }
  throw ArgumentError.value(
    trackOrId,
    'trackOrId',
    'Must be a Track, track ID, or queue index.',
  );
}

void _checkQueueIndex(int index, int queueLength) {
  if (index < 0 || index >= queueLength) {
    throw RangeError.range(index, 0, queueLength - 1, 'index');
  }
}

Uri buildTrackStreamUri({
  required String baseUrl,
  required String trackId,
}) {
  final baseUri = Uri.parse(baseUrl);
  return Uri(
    scheme: baseUri.scheme,
    userInfo: baseUri.userInfo,
    host: baseUri.host,
    port: baseUri.hasPort ? baseUri.port : null,
    pathSegments: ['api', 'v1', 'tracks', trackId, 'stream'],
  );
}

Duration _trackDuration(Track track) {
  final seconds = track.durationSeconds;
  return seconds == null ? Duration.zero : Duration(seconds: seconds);
}

Duration _clampPosition(Duration position, Duration duration) {
  if (position < Duration.zero) {
    return Duration.zero;
  }
  if (position > duration) {
    return duration;
  }
  return position;
}
