import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/application/lyrics_offset_controller.dart';
import '../../lyrics/data/lyrics_api.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';
import '../../preferences/player_preferences.dart';
import '../data/android_lyrics_overlay.dart';
import '../data/unsupported_lyrics_overlay.dart';
import '../data/windows_lyrics_overlay.dart';
import '../domain/desktop_lyrics_overlay.dart';
import '../domain/overlay_capability.dart';
import 'desktop_lyrics_controller.dart';

final _currentTrackLyricsOffsetProvider =
    Provider<AsyncValue<Duration>?>((ref) {
  final trackId = ref.watch(
    playerControllerProvider.select((playback) => playback.currentTrack?.id),
  );
  return trackId == null ? null : ref.watch(lyricsOffsetProvider(trackId));
});

final desktopLyricsOverlayProvider = Provider<DesktopLyricsOverlay>((ref) {
  final DesktopLyricsOverlay overlay;
  if (Platform.isWindows) {
    overlay = const WindowsLyricsOverlay();
  } else if (Platform.isAndroid) {
    overlay = const AndroidLyricsOverlay();
  } else {
    overlay = const UnsupportedLyricsOverlay();
  }

  ref.onDispose(() {
    unawaited(overlay.dispose());
  });
  return overlay;
});

final desktopLyricsCapabilityProvider =
    FutureProvider<LyricsOverlayCapability>((ref) {
  return ref.watch(desktopLyricsOverlayProvider).getCapability();
});

final desktopLyricsControllerProvider = StateNotifierProvider.autoDispose<
    DesktopLyricsController, DesktopLyricsState>(
  (ref) {
    ref.keepAlive();
    final overlay = ref.watch(desktopLyricsOverlayProvider);
    final controller = DesktopLyricsController(
      overlay: overlay,
      loadLyrics: (trackId) {
        return ref.read(lyricsApiProvider).fetchLyrics(trackId);
      },
      configure: ({required resetPosition}) async {
        final preferences = await ref.read(playerPreferencesProvider.future);
        return overlay.configure(
          backgroundOpacity: preferences.desktopLyricsBackgroundOpacity,
          textColor: preferences.lyricsColorArgb,
          fontSize: preferences.desktopLyricsFontSize,
          textAlignment:
              preferences.desktopLyricsAlignment.desktopLyricsTextAlignment,
          resetPosition: resetPosition && preferences.resetPositionOnOpen,
        );
      },
    );
    ref.onCancel(() {
      controller.setUiListenerActive(false);
    });
    ref.onResume(() {
      controller.setUiListenerActive(true);
    });
    ref.listen<PlaybackState>(
      playerControllerProvider,
      (_, playback) {
        unawaited(controller.updatePlayback(playback));
      },
      fireImmediately: true,
    );
    ref.listen<DesktopLyricsLineMode>(
      desktopLyricsLineModeProvider,
      (_, lineMode) {
        unawaited(controller.setLineMode(lineMode));
      },
      fireImmediately: true,
    );
    ref.listen<AsyncValue<Duration>?>(
      _currentTrackLyricsOffsetProvider,
      (_, offset) {
        unawaited(
          controller.setLyricsOffset(offset?.valueOrNull ?? Duration.zero),
        );
      },
      fireImmediately: true,
    );
    return controller;
  },
);
