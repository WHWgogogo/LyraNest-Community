import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player_controller.dart';
import '../../domain/playback_state.dart';
import 'sleep_timer_controller.dart';
import 'sleep_timer_state.dart';

final sleepTimerControllerProvider =
    StateNotifierProvider<SleepTimerController, SleepTimerState>(
  (ref) {
    String? pauseWhenPlaybackResumesForTrackId;

    Future<void> pauseAfterCurrentTrack() async {
      pauseWhenPlaybackResumesForTrackId =
          ref.read(playerControllerProvider).currentTrack?.id;
      await Future<void>.delayed(Duration.zero);

      final playback = ref.read(playerControllerProvider);
      if (playback.status == PlaybackStatus.completed ||
          playback.status == PlaybackStatus.idle ||
          playback.status == PlaybackStatus.stopped ||
          playback.status == PlaybackStatus.error) {
        pauseWhenPlaybackResumesForTrackId = null;
      }
    }

    final controller = SleepTimerController(
      pausePlayback: () => ref.read(playerControllerProvider.notifier).pause(),
      pauseAfterCurrentTrack: pauseAfterCurrentTrack,
      currentTrackId: () => ref.read(playerControllerProvider).currentTrack?.id,
    );
    ref.listen<PlaybackState>(
      playerControllerProvider,
      (previous, playback) {
        final didCompleteTrack = playback.status == PlaybackStatus.completed &&
            previous?.status != PlaybackStatus.completed;
        if (didCompleteTrack) {
          unawaited(
            controller.notifyCurrentTrackCompleted(playback.currentTrack?.id),
          );
        }

        if (pauseWhenPlaybackResumesForTrackId != null &&
            playback.status == PlaybackStatus.playing) {
          pauseWhenPlaybackResumesForTrackId = null;
          unawaited(ref.read(playerControllerProvider.notifier).pause());
        }
      },
    );
    return controller;
  },
);
