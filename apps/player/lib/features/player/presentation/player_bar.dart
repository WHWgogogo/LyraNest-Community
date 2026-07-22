import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../l10n/l10n.dart';
import '../application/player_controller.dart';
import 'track_artwork.dart';

class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = GoRouter.of(context);

    return AnimatedBuilder(
      animation: router.routeInformationProvider,
      builder: (context, _) {
        final path = router.routeInformationProvider.value.uri.path;
        if (path == '/player' || path.startsWith('/player/lyrics/')) {
          return const SizedBox.shrink();
        }

        return const _PlayerBarContent();
      },
    );
  }
}

class _PlayerBarContent extends ConsumerWidget {
  const _PlayerBarContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    final track = playback.currentTrack;
    if (track == null) {
      return const SizedBox.shrink();
    }

    final controller = ref.read(playerControllerProvider.notifier);
    final serverBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final compact = MediaQuery.sizeOf(context).width < 620;
    final artworkSize = compact ? 48.0 : 52.0;
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(compact ? 8 : 14, 0, compact ? 8 : 14, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xF0171A29),
            borderRadius: BorderRadius.circular(compact ? 22 : 25),
            border: Border.all(color: Colors.white.withValues(alpha: .1)),
            boxShadow: const [
              BoxShadow(
                color: Color(0x7A000000),
                blurRadius: 28,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(compact ? 22 : 25),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => context.go('/player'),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 3,
                      child: playback.isLoading
                          ? const LinearProgressIndicator()
                          : LinearProgressIndicator(
                              value: playback.progress,
                              color: const Color(0xFFC1B2FF),
                              backgroundColor:
                                  Colors.white.withValues(alpha: .08),
                            ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        compact ? 10 : 12,
                        compact ? 8 : 9,
                        compact ? 6 : 10,
                        compact ? 8 : 9,
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: artworkSize,
                            height: artworkSize,
                            child: TrackArtwork(
                              artworkUrl: track.artworkUrl ??
                                  buildArtworkUrl(serverBaseUrl, track.id),
                              identity: track.id,
                              title: track.localizedTitle(l10n),
                              borderRadius: compact ? 14 : 16,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  track.localizedTitle(l10n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  track.localizedArtist(l10n),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Colors.white.withValues(
                                          alpha: .52,
                                        ),
                                      ),
                                ),
                              ],
                            ),
                          ),
                          if (!compact)
                            IconButton(
                              tooltip: 'Previous',
                              onPressed: playback.canSkipPrevious &&
                                      !playback.isLoading
                                  ? () => unawaited(controller.previous())
                                  : null,
                              icon: const Icon(Icons.skip_previous_rounded),
                            ),
                          if (playback.isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 15),
                              child: SizedBox.square(
                                dimension: 19,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          else
                            _MiniPlayButton(
                              isPlaying: playback.isPlaying,
                              tooltip:
                                  playback.isPlaying ? l10n.pause : l10n.play,
                              onPressed: () => unawaited(
                                playback.isPlaying
                                    ? controller.pause()
                                    : controller.play(),
                              ),
                            ),
                          if (!compact)
                            IconButton(
                              tooltip: 'Next',
                              onPressed:
                                  playback.canSkipNext && !playback.isLoading
                                      ? () => unawaited(controller.next())
                                      : null,
                              icon: const Icon(Icons.skip_next_rounded),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPlayButton extends StatelessWidget {
  const _MiniPlayButton({
    required this.isPlaying,
    required this.tooltip,
    required this.onPressed,
  });

  final bool isPlaying;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFCFC2FF), Color(0xFF8063F4)],
        ),
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
          color: const Color(0xFF17132A),
        ),
      ),
    );
  }
}
