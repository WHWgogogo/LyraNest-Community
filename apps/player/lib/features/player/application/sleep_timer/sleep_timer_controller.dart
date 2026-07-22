import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sleep_timer_scheduler.dart';
import 'sleep_timer_state.dart';

typedef SleepTimerPausePlayback = FutureOr<void> Function();
typedef SleepTimerCurrentTrackId = String? Function();

class SleepTimerController extends StateNotifier<SleepTimerState> {
  SleepTimerController({
    required SleepTimerPausePlayback pausePlayback,
    required SleepTimerCurrentTrackId currentTrackId,
    SleepTimerPausePlayback? pauseAfterCurrentTrack,
    DateTime Function()? now,
    SleepTimerScheduler? scheduler,
    Duration tickInterval = const Duration(seconds: 1),
  })  : _pausePlayback = pausePlayback,
        _pauseAfterCurrentTrack = pauseAfterCurrentTrack ?? pausePlayback,
        _currentTrackId = currentTrackId,
        _now = now ?? DateTime.now,
        _scheduler = scheduler ?? const SystemSleepTimerScheduler(),
        _tickInterval = tickInterval,
        super(const SleepTimerState()) {
    if (tickInterval <= Duration.zero) {
      throw ArgumentError.value(
        tickInterval,
        'tickInterval',
        'Must be greater than zero.',
      );
    }
  }

  final SleepTimerPausePlayback _pausePlayback;
  final SleepTimerPausePlayback _pauseAfterCurrentTrack;
  final SleepTimerCurrentTrackId _currentTrackId;
  final DateTime Function() _now;
  final SleepTimerScheduler _scheduler;
  final Duration _tickInterval;

  SleepTimerTask? _deadlineTask;
  SleepTimerTask? _tickerTask;
  var _generation = 0;
  var _isDisposed = false;

  void startFor(
    Duration duration, {
    SleepTimerStopMode stopMode = SleepTimerStopMode.immediately,
  }) {
    if (duration <= Duration.zero) {
      throw ArgumentError.value(
        duration,
        'duration',
        'Must be greater than zero.',
      );
    }
    startUntil(_now().add(duration), stopMode: stopMode);
  }

  void startUntil(
    DateTime endAt, {
    SleepTimerStopMode stopMode = SleepTimerStopMode.immediately,
  }) {
    _ensureNotDisposed();
    final remaining = _remainingUntil(endAt);
    if (remaining <= Duration.zero) {
      throw ArgumentError.value(
        endAt,
        'endAt',
        'Must be in the future.',
      );
    }

    _cancelTasks();
    final generation = ++_generation;
    state = SleepTimerState(
      endAt: endAt,
      remaining: remaining,
      stopMode: stopMode,
    );
    _deadlineTask = _scheduler.schedule(
      remaining,
      () => _handleDeadline(generation),
    );
    _tickerTask = _scheduler.schedulePeriodic(
      _tickInterval,
      () => _refreshCountdown(generation),
    );
  }

  void refresh() {
    if (_isDisposed || !state.isCountingDown) {
      return;
    }
    _refreshCountdown(_generation);
  }

  Future<void> notifyCurrentTrackCompleted(String? trackId) async {
    if (_isDisposed || !state.waitingForCurrentTrackEnd) {
      return;
    }

    final waitingTrackId = state.waitingTrackId;
    if (waitingTrackId != null && trackId != waitingTrackId) {
      return;
    }

    _cancelTasks();
    ++_generation;
    state = const SleepTimerState();
    await _pauseSafely(_pauseAfterCurrentTrack);
  }

  void cancel() {
    if (_isDisposed) {
      return;
    }
    _cancelTasks();
    ++_generation;
    state = const SleepTimerState();
  }

  void _refreshCountdown(int generation) {
    if (!_isCurrent(generation) || !state.isCountingDown) {
      return;
    }

    final endAt = state.endAt;
    if (endAt == null) {
      return;
    }

    final remaining = _remainingUntil(endAt);
    if (remaining <= Duration.zero) {
      _handleDeadline(generation);
      return;
    }
    if (remaining != state.remaining) {
      state = state.copyWith(remaining: remaining);
    }
  }

  void _handleDeadline(int generation) {
    if (!_isCurrent(generation) || !state.isCountingDown) {
      return;
    }

    final endAt = state.endAt;
    if (endAt == null) {
      return;
    }
    final remaining = _remainingUntil(endAt);
    if (remaining > Duration.zero) {
      _deadlineTask?.cancel();
      _deadlineTask = _scheduler.schedule(
        remaining,
        () => _handleDeadline(generation),
      );
      _refreshCountdown(generation);
      return;
    }

    _cancelTasks();
    if (state.stopMode == SleepTimerStopMode.afterCurrentTrack) {
      final trackId = _currentTrackId();
      if (trackId != null) {
        state = SleepTimerState(
          stopMode: SleepTimerStopMode.afterCurrentTrack,
          waitingForCurrentTrackEnd: true,
          waitingTrackId: trackId,
        );
        return;
      }
    }

    ++_generation;
    state = const SleepTimerState();
    unawaited(_pauseSafely(_pausePlayback));
  }

  Duration _remainingUntil(DateTime endAt) {
    final remaining = endAt.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool _isCurrent(int generation) {
    return !_isDisposed && generation == _generation;
  }

  void _cancelTasks() {
    _deadlineTask?.cancel();
    _tickerTask?.cancel();
    _deadlineTask = null;
    _tickerTask = null;
  }

  Future<void> _pauseSafely(SleepTimerPausePlayback callback) async {
    try {
      await callback();
    } catch (_) {}
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('SleepTimerController has been disposed.');
    }
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _cancelTasks();
    super.dispose();
  }
}
