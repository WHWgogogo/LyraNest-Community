import 'package:flutter/foundation.dart';

enum SleepTimerStopMode {
  immediately,
  afterCurrentTrack,
}

@immutable
class SleepTimerState {
  const SleepTimerState({
    this.endAt,
    this.remaining = Duration.zero,
    this.stopMode = SleepTimerStopMode.immediately,
    this.waitingForCurrentTrackEnd = false,
    this.waitingTrackId,
  });

  final DateTime? endAt;
  final Duration remaining;
  final SleepTimerStopMode stopMode;
  final bool waitingForCurrentTrackEnd;
  final String? waitingTrackId;

  bool get isActive => endAt != null || waitingForCurrentTrackEnd;

  bool get isCountingDown => endAt != null;

  SleepTimerState copyWith({
    DateTime? endAt,
    Duration? remaining,
    SleepTimerStopMode? stopMode,
    bool? waitingForCurrentTrackEnd,
    String? waitingTrackId,
    bool clearEndAt = false,
    bool clearWaitingTrackId = false,
  }) {
    return SleepTimerState(
      endAt: clearEndAt ? null : endAt ?? this.endAt,
      remaining: remaining ?? this.remaining,
      stopMode: stopMode ?? this.stopMode,
      waitingForCurrentTrackEnd:
          waitingForCurrentTrackEnd ?? this.waitingForCurrentTrackEnd,
      waitingTrackId:
          clearWaitingTrackId ? null : waitingTrackId ?? this.waitingTrackId,
    );
  }
}
