import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../player/application/player_controller.dart';
import '../../player/domain/playback_state.dart';
import '../../tracks/domain/track.dart';
import '../data/android_system_media_platform.dart';
import '../data/system_media_platform.dart';
import 'system_media_controller.dart';

final systemMediaPlatformProvider = Provider<SystemMediaPlatform>((ref) {
  final SystemMediaPlatform platform;
  if (Platform.isAndroid) {
    platform = const AndroidSystemMediaPlatform();
  } else {
    platform = const UnsupportedSystemMediaPlatform();
  }
  ref.onDispose(() {
    unawaited(platform.dispose());
  });
  return platform;
});

final systemMediaControllerProvider = Provider<SystemMediaController>((ref) {
  final controller = SystemMediaController(
    platform: ref.watch(systemMediaPlatformProvider),
    artworkUrlResolver: (track) {
      final baseUrl =
          ref.read(serverConfigControllerProvider).valueOrNull?.baseUrl ??
              ServerConfig.preferredDefaultBaseUrl;
      return buildSystemMediaArtworkUri(
        baseUrl: baseUrl,
        track: track,
      )?.toString();
    },
    onPrevious: () => ref.read(playerControllerProvider.notifier).previous(),
    onPlay: () => ref.read(playerControllerProvider.notifier).play(),
    onPause: () => ref.read(playerControllerProvider.notifier).pause(),
    onNext: () => ref.read(playerControllerProvider.notifier).next(),
    onCyclePlaybackMode: () async {
      final playback = ref.read(playerControllerProvider);
      ref
          .read(playerControllerProvider.notifier)
          .setPlaybackMode(_nextSystemMediaPlaybackMode(playback.playbackMode));
    },
    onToggleDesktopLyrics: () async {},
  );
  ref.listen<PlaybackState>(
    playerControllerProvider,
    (_, playback) {
      unawaited(controller.syncPlayback(playback));
    },
    fireImmediately: true,
  );
  ref.onDispose(() {
    unawaited(controller.dispose());
  });
  return controller;
});

PlaybackMode _nextSystemMediaPlaybackMode(PlaybackMode currentMode) {
  return switch (currentMode) {
    PlaybackMode.sequential => PlaybackMode.repeatAll,
    PlaybackMode.repeatAll => PlaybackMode.repeatOne,
    PlaybackMode.repeatOne => PlaybackMode.shuffle,
    PlaybackMode.shuffle => PlaybackMode.sequential,
  };
}

Uri? buildSystemMediaArtworkUri({
  required String baseUrl,
  required Track track,
}) {
  try {
    final baseUri = Uri.parse(baseUrl);
    if (baseUri.scheme.isEmpty || baseUri.host.isEmpty) {
      return null;
    }
    return Uri(
      scheme: baseUri.scheme,
      userInfo: baseUri.userInfo,
      host: baseUri.host,
      port: baseUri.hasPort ? baseUri.port : null,
      pathSegments: ['api', 'v1', 'tracks', track.id, 'artwork'],
    );
  } on FormatException {
    return null;
  }
}
