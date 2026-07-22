import 'package:flutter/foundation.dart';

import '../../tracks/domain/track.dart';

enum PlaybackStatus {
  idle,
  loading,
  playing,
  paused,
  stopped,
  completed,
  error,
}

enum PlaybackMode {
  sequential,
  repeatOne,
  shuffle,
  repeatAll;

  static const PlaybackMode listLoop = PlaybackMode.repeatAll;
  static const PlaybackMode singleLoop = PlaybackMode.repeatOne;
  static const PlaybackMode random = PlaybackMode.shuffle;
}

@immutable
class PlaybackState {
  const PlaybackState({
    this.currentTrack,
    this.queue = const [],
    this.currentIndex = -1,
    this.playbackMode = PlaybackMode.listLoop,
    this.status = PlaybackStatus.idle,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isBuffering = false,
    this.errorMessage,
  });

  final Track? currentTrack;
  final List<Track> queue;
  final int currentIndex;
  final PlaybackMode playbackMode;
  final PlaybackStatus status;
  final Duration position;
  final Duration duration;
  final bool isBuffering;
  final String? errorMessage;

  bool get isPlaying => status == PlaybackStatus.playing;
  bool get isLoading => status == PlaybackStatus.loading || isBuffering;
  bool get hasError => status == PlaybackStatus.error;
  bool get canSeek => duration > Duration.zero;
  bool get hasQueue => queue.isNotEmpty;
  bool get canSkipNext {
    if (currentTrack == null || queue.isEmpty) {
      return false;
    }
    if (playbackMode == PlaybackMode.shuffle ||
        playbackMode == PlaybackMode.repeatAll) {
      return queue.length > 1;
    }
    return currentIndex >= 0 && currentIndex < queue.length - 1;
  }

  bool get canSkipPrevious {
    if (currentTrack == null || queue.isEmpty) {
      return false;
    }
    if (position > Duration.zero) {
      return true;
    }
    if (playbackMode == PlaybackMode.shuffle ||
        playbackMode == PlaybackMode.repeatAll) {
      return queue.length > 1;
    }
    return currentIndex > 0;
  }

  double get progress {
    if (!canSeek) {
      return 0;
    }
    return (position.inMilliseconds / duration.inMilliseconds)
        .clamp(0, 1)
        .toDouble();
  }

  PlaybackState copyWith({
    Track? currentTrack,
    List<Track>? queue,
    int? currentIndex,
    PlaybackMode? playbackMode,
    PlaybackStatus? status,
    Duration? position,
    Duration? duration,
    bool? isBuffering,
    String? errorMessage,
    bool clearTrack = false,
    bool clearError = false,
  }) {
    return PlaybackState(
      currentTrack: clearTrack ? null : currentTrack ?? this.currentTrack,
      queue: queue ?? this.queue,
      currentIndex: currentIndex ?? this.currentIndex,
      playbackMode: playbackMode ?? this.playbackMode,
      status: status ?? this.status,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isBuffering: isBuffering ?? this.isBuffering,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}
