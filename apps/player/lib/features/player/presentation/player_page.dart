import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/l10n.dart';
import '../../collections/application/collections_controller.dart';
import '../../offline/application/offline_providers.dart';
import '../../offline/presentation/offline_download_button.dart';
import '../../preferences/player_preferences.dart';
import '../../tracks/data/tracks_api.dart';
import '../../tracks/domain/track.dart';
import '../application/player_controller.dart';
import '../domain/playback_state.dart';
import 'now_playing_lyrics.dart';
import 'playback_time.dart';
import 'queue_panel.dart';
import 'sleep_timer_controls.dart';
import 'track_artwork.dart';

const _selectedActionColor = Color(0xFFC6B8FF);

class PlayerPage extends ConsumerStatefulWidget {
  const PlayerPage({
    this.onClose,
    super.key,
  });

  final VoidCallback? onClose;

  @override
  ConsumerState<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends ConsumerState<PlayerPage> {
  var _showDesktopQueue = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = ref.watch(playerControllerProvider);

    final track = playback.currentTrack;
    final serverBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final isFavorite =
        track != null && ref.watch(isFavoriteTrackProvider(track.id));
    final localArtwork = track == null
        ? null
        : ref.watch(offlineCachedArtworkUriProvider(track.id));
    final artworkUrl = track == null
        ? null
        : localArtwork?.when(
            data: (uri) =>
                uri?.toString() ??
                track.artworkUrl ??
                buildArtworkUrl(serverBaseUrl, track.id),
            loading: () =>
                track.artworkUrl ?? buildArtworkUrl(serverBaseUrl, track.id),
            error: (error, stackTrace) =>
                track.artworkUrl ?? buildArtworkUrl(serverBaseUrl, track.id),
          );

    final playerPage = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          _closeToLibrary();
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF090B13),
        body: _ImmersiveBackdrop(
          artworkUrl: artworkUrl,
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 960;
                if (desktop) {
                  return _DesktopPlayerLayout(
                    playback: playback,
                    track: track,
                    artworkUrl: artworkUrl,
                    isFavorite: isFavorite,
                    queueVisible: _showDesktopQueue,
                    onQueueVisibilityChanged: () {
                      setState(() {
                        _showDesktopQueue = !_showDesktopQueue;
                      });
                    },
                    onClose: _closeToLibrary,
                    onCollections: () => _showCollectionsSheet(context),
                    onToggleFavorite: track == null
                        ? null
                        : () => _toggleFavorite(track.id, isFavorite),
                  );
                }

                return _MobilePlayerLayout(
                  playback: playback,
                  track: track,
                  artworkUrl: artworkUrl,
                  isFavorite: isFavorite,
                  onClose: _closeToLibrary,
                  onQueue: () => _showMobileQueue(context),
                  onCollections: () => _showCollectionsSheet(context),
                  onToggleFavorite: track == null
                      ? null
                      : () => _toggleFavorite(track.id, isFavorite),
                );
              },
            ),
          ),
        ),
      ),
    );
    if (Router.maybeOf(context) == null) {
      return playerPage;
    }
    return BackButtonListener(
      onBackButtonPressed: _handleBackButton,
      child: playerPage,
    );
  }

  void _closeToLibrary() {
    widget.onClose?.call();
    if (mounted) {
      context.go('/');
    }
  }

  Future<bool> _handleBackButton() async {
    if (ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    _closeToLibrary();
    return true;
  }

  void _toggleFavorite(String trackId, bool isFavorite) {
    final controller = ref.read(collectionsControllerProvider.notifier);
    unawaited(
      isFavorite
          ? controller.removeFavoriteTrack(trackId)
          : controller.addFavoriteTrack(trackId),
    );
  }

  void _showMobileQueue(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          top: false,
          child: Container(
            height: MediaQuery.sizeOf(context).height * .78,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: QueuePanel(
              compact: true,
              onClose: () => Navigator.of(context).pop(),
            ),
          ),
        );
      },
    );
  }

  void _showCollectionsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _CollectionsSheet(),
    );
  }
}

class _DesktopPlayerLayout extends StatelessWidget {
  const _DesktopPlayerLayout({
    required this.playback,
    required this.track,
    required this.artworkUrl,
    required this.isFavorite,
    required this.queueVisible,
    required this.onQueueVisibilityChanged,
    required this.onClose,
    required this.onCollections,
    required this.onToggleFavorite,
  });

  final PlaybackState playback;
  final Track? track;
  final String? artworkUrl;
  final bool isFavorite;
  final bool queueVisible;
  final VoidCallback onQueueVisibilityChanged;
  final VoidCallback onClose;
  final VoidCallback onCollections;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('desktop-player-layout'),
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _DesktopNavigation(
            onClose: onClose,
            onCollections: onCollections,
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              children: [
                _DesktopTopBar(
                  title: track?.localizedTitle(context.l10n),
                  queueVisible: queueVisible,
                  onQueue: onQueueVisibilityChanged,
                ),
                const SizedBox(height: 18),
                Expanded(
                  child: track == null
                      ? const _EmptyPlayerStage()
                      : _DesktopStage(
                          track: track!,
                          artworkUrl: artworkUrl!,
                          playback: playback,
                          isFavorite: isFavorite,
                          onToggleFavorite: onToggleFavorite!,
                          onViewLyrics: () => context.push(
                            '/player/lyrics/${Uri.encodeComponent(track!.id)}',
                          ),
                        ),
                ),
                if (track != null) ...[
                  const SizedBox(height: 18),
                  _PlaybackControls(
                    playback: playback,
                    compact: false,
                    isFavorite: isFavorite,
                    onFavorite: onToggleFavorite!,
                    onViewLyrics: () => context.push(
                      '/player/lyrics/${Uri.encodeComponent(track!.id)}',
                    ),
                    onQueue: onQueueVisibilityChanged,
                  ),
                ],
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: queueVisible
                ? Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: SizedBox(
                      key: const ValueKey('desktop-queue-panel'),
                      width: 328,
                      child: QueuePanel(
                        onClose: onQueueVisibilityChanged,
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.onClose,
    required this.onCollections,
  });

  final VoidCallback onClose;
  final VoidCallback onCollections;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 202,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xB8131624),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              children: [
                _RoundAction(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  icon: Icons.keyboard_arrow_down_rounded,
                  onPressed: onClose,
                ),
                const SizedBox(width: 9),
                Container(
                  width: 34,
                  height: 34,
                  decoration: const BoxDecoration(
                    color: Color(0xFF9A7DFF),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.graphic_eq_rounded, size: 20),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      context.l10n.appTitle,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            letterSpacing: 2,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 36),
        ],
      ),
    );
  }
}

class _DesktopTopBar extends StatelessWidget {
  const _DesktopTopBar({
    required this.title,
    required this.queueVisible,
    required this.onQueue,
  });

  final String? title;
  final bool queueVisible;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title ?? context.l10n.playerTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        _RoundAction(
          key: const ValueKey('desktop-queue-toggle'),
          tooltip:
              queueVisible ? context.l10n.hideQueue : context.l10n.showQueue,
          icon: queueVisible
              ? Icons.queue_music_rounded
              : Icons.queue_music_outlined,
          selected: queueVisible,
          onPressed: onQueue,
        ),
      ],
    );
  }
}

class _DesktopStage extends StatelessWidget {
  const _DesktopStage({
    required this.track,
    required this.artworkUrl,
    required this.playback,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onViewLyrics,
  });

  final Track track;
  final String artworkUrl;
  final PlaybackState playback;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onViewLyrics;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 10,
          child: Column(
            children: [
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math
                        .min(constraints.maxWidth, constraints.maxHeight)
                        .clamp(
                          constraints.maxHeight < 420 ? 180.0 : 240.0,
                          510.0,
                        )
                        .toDouble();
                    return Center(
                      child: SizedBox(
                        width: size,
                        height: size,
                        child: TrackArtwork(
                          artworkUrl: artworkUrl,
                          identity: track.id,
                          title: track.localizedTitle(context.l10n),
                          borderRadius: 38,
                          elevated: true,
                          showPlaybackPulse: true,
                          isPlaying: playback.isPlaying,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 20),
              _TrackIdentity(
                track: track,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(width: 32),
        Expanded(
          flex: 12,
          child: _LyricsCard(
            key: const ValueKey('desktop-lyrics-card'),
            trackId: track.id,
            fillHeight: true,
            onViewLyrics: onViewLyrics,
          ),
        ),
      ],
    );
  }
}

class _MobilePlayerLayout extends StatelessWidget {
  const _MobilePlayerLayout({
    required this.playback,
    required this.track,
    required this.artworkUrl,
    required this.isFavorite,
    required this.onClose,
    required this.onQueue,
    required this.onCollections,
    required this.onToggleFavorite,
  });

  final PlaybackState playback;
  final Track? track;
  final String? artworkUrl;
  final bool isFavorite;
  final VoidCallback onClose;
  final VoidCallback onQueue;
  final VoidCallback onCollections;
  final VoidCallback? onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('mobile-player-layout'),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        children: [
          _MobileTopBar(
            onClose: onClose,
            onQueue: onQueue,
            onCollections: onCollections,
          ),
          const SizedBox(height: 12),
          Expanded(
            child: track == null
                ? const _EmptyPlayerStage()
                : _MobilePlayerStage(
                    track: track!,
                    artworkUrl: artworkUrl!,
                    playback: playback,
                    isFavorite: isFavorite,
                    onToggleFavorite: onToggleFavorite!,
                    onViewLyrics: () => context.push(
                      '/player/lyrics/${Uri.encodeComponent(track!.id)}',
                    ),
                  ),
          ),
          if (track != null)
            _PlaybackControls(
              playback: playback,
              compact: true,
              isFavorite: isFavorite,
              onFavorite: onToggleFavorite!,
              onViewLyrics: () => context.push(
                '/player/lyrics/${Uri.encodeComponent(track!.id)}',
              ),
              onQueue: onQueue,
            ),
        ],
      ),
    );
  }
}

class _MobilePlayerStage extends StatefulWidget {
  const _MobilePlayerStage({
    required this.track,
    required this.artworkUrl,
    required this.playback,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onViewLyrics,
  });

  final Track track;
  final String artworkUrl;
  final PlaybackState playback;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onViewLyrics;

  @override
  State<_MobilePlayerStage> createState() => _MobilePlayerStageState();
}

class _MobilePlayerStageState extends State<_MobilePlayerStage> {
  static const _pageCount = 2;
  static const _pageSettleDuration = Duration(milliseconds: 220);
  static const _minimumSwipeDistance = 48.0;
  static const _maximumSwipeDistance = 88.0;
  static const _swipeDistanceFraction = .18;
  static const _minimumFlingVelocity = 420.0;

  late final PageController _pageController;
  var _currentPage = 0;
  int? _dragStartPage;
  var _dragDistance = 0.0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(
      initialPage: 0,
      keepPage: false,
    );
  }

  @override
  void didUpdateWidget(covariant _MobilePlayerStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.id == widget.track.id) {
      return;
    }

    _currentPage = 0;
    _dragStartPage = null;
    _dragDistance = 0;
    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _handleHorizontalDragStart,
      onHorizontalDragUpdate: _handleHorizontalDragUpdate,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onHorizontalDragCancel: _handleHorizontalDragCancel,
      child: PageView(
        controller: _pageController,
        key: const PageStorageKey('mobile-player-stage'),
        physics: const NeverScrollableScrollPhysics(),
        onPageChanged: (page) {
          _currentPage = page;
        },
        children: [
          _MobilePlayerOverview(
            track: widget.track,
            artworkUrl: widget.artworkUrl,
            playback: widget.playback,
            isFavorite: widget.isFavorite,
            onToggleFavorite: widget.onToggleFavorite,
            onViewLyrics: widget.onViewLyrics,
          ),
          Padding(
            key: const ValueKey('mobile-full-lyrics'),
            padding: const EdgeInsets.only(bottom: 8),
            child: _LyricsCard(
              key: const ValueKey('mobile-full-lyrics-card'),
              trackId: widget.track.id,
              fillHeight: true,
              onViewLyrics: widget.onViewLyrics,
            ),
          ),
        ],
      ),
    );
  }

  void _handleHorizontalDragStart(DragStartDetails details) {
    if (!_pageController.hasClients) {
      return;
    }

    _dragStartPage = _currentPage;
    _dragDistance = 0;
  }

  void _handleHorizontalDragUpdate(DragUpdateDetails details) {
    final dragStartPage = _dragStartPage;
    if (dragStartPage == null || !_pageController.hasClients) {
      return;
    }

    _dragDistance += details.primaryDelta ?? 0;
    final position = _pageController.position;
    final targetPixels =
        (dragStartPage * position.viewportDimension - _dragDistance).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _pageController.jumpTo(targetPixels.toDouble());
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    _finishHorizontalDrag(details.primaryVelocity ?? 0);
  }

  void _handleHorizontalDragCancel() {
    _finishHorizontalDrag(0);
  }

  void _finishHorizontalDrag(double velocity) {
    final dragStartPage = _dragStartPage;
    _dragStartPage = null;
    if (dragStartPage == null) {
      return;
    }

    final distanceReachedThreshold =
        _dragDistance.abs() >= _swipeDistanceThreshold;
    final velocityReachedThreshold = velocity.abs() >= _minimumFlingVelocity;
    final direction = distanceReachedThreshold
        ? _dragDistance.sign
        : velocityReachedThreshold
            ? velocity.sign
            : 0.0;
    final targetPage = direction == 0
        ? dragStartPage
        : _clampPage(dragStartPage - direction.toInt());
    _dragDistance = 0;
    _settlePage(targetPage);
  }

  double get _swipeDistanceThreshold {
    final viewport = _pageController.hasClients
        ? _pageController.position.viewportDimension
        : MediaQuery.sizeOf(context).width;
    return (viewport * _swipeDistanceFraction)
        .clamp(_minimumSwipeDistance, _maximumSwipeDistance)
        .toDouble();
  }

  int _clampPage(int page) => page.clamp(0, _pageCount - 1);

  void _settlePage(int targetPage) {
    _currentPage = targetPage;
    if (!_pageController.hasClients) {
      return;
    }
    unawaited(
      _pageController.animateToPage(
        targetPage,
        duration: _pageSettleDuration,
        curve: Curves.easeOutCubic,
      ),
    );
  }
}

class _MobilePlayerOverview extends StatelessWidget {
  const _MobilePlayerOverview({
    required this.track,
    required this.artworkUrl,
    required this.playback,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onViewLyrics,
  });

  final Track track;
  final String artworkUrl;
  final PlaybackState playback;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onViewLyrics;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const ValueKey('mobile-player-overview'),
      physics: const BouncingScrollPhysics(),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final size =
              (constraints.maxWidth * .78).clamp(208.0, 320.0).toDouble();
          return Column(
            children: [
              SizedBox(
                key: const ValueKey('mobile-track-artwork'),
                width: size,
                height: size,
                child: TrackArtwork(
                  artworkUrl: artworkUrl,
                  identity: track.id,
                  title: track.localizedTitle(context.l10n),
                  borderRadius: 34,
                  elevated: true,
                  showPlaybackPulse: true,
                  isPlaying: playback.isPlaying,
                ),
              ),
              const SizedBox(height: 24),
              _TrackIdentity(
                track: track,
                isFavorite: isFavorite,
                onToggleFavorite: onToggleFavorite,
                textAlign: TextAlign.left,
                compact: true,
              ),
              const SizedBox(height: 22),
              _LyricsCard(
                key: const ValueKey('mobile-compact-lyrics-card'),
                trackId: track.id,
                onViewLyrics: onViewLyrics,
                showHeader: false,
              ),
              const SizedBox(height: 18),
            ],
          );
        },
      ),
    );
  }
}

class _MobileTopBar extends StatelessWidget {
  const _MobileTopBar({
    required this.onClose,
    required this.onQueue,
    required this.onCollections,
  });

  final VoidCallback onClose;
  final VoidCallback onQueue;
  final VoidCallback onCollections;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _RoundAction(
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          icon: Icons.keyboard_arrow_down_rounded,
          onPressed: onClose,
        ),
        Expanded(
          child: Text(
            context.l10n.appTitle,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white.withValues(alpha: .66),
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        _RoundAction(
          tooltip: context.l10n.collections,
          icon: Icons.favorite_outline_rounded,
          onPressed: onCollections,
        ),
        const SizedBox(width: 8),
        _RoundAction(
          tooltip: context.l10n.queue,
          icon: Icons.queue_music_rounded,
          onPressed: onQueue,
        ),
      ],
    );
  }
}

class _TrackIdentity extends StatelessWidget {
  const _TrackIdentity({
    required this.track,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.textAlign,
    this.compact = false,
  });

  final Track track;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final TextAlign textAlign;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final aligned = textAlign == TextAlign.center
        ? CrossAxisAlignment.center
        : textAlign == TextAlign.right
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: aligned,
            children: [
              Text(
                key: compact ? const ValueKey('mobile-track-title') : null,
                track.localizedTitle(context.l10n),
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: (compact
                        ? Theme.of(context).textTheme.titleLarge
                        : Theme.of(context).textTheme.headlineSmall)
                    ?.copyWith(
                  fontWeight: FontWeight.w900,
                  height: compact ? 1.12 : 1.08,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                [
                  track.localizedArtist(context.l10n),
                  if (track.album?.trim().isNotEmpty == true) track.album!,
                ].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: textAlign,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white.withValues(alpha: .54),
                    ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: isFavorite
              ? context.l10n.removeFavorite
              : context.l10n.addFavorite,
          onPressed: onToggleFavorite,
          icon: Icon(
            isFavorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
            color: isFavorite
                ? const Color(0xFFFF91B6)
                : Colors.white.withValues(alpha: .72),
          ),
        ),
      ],
    );
  }
}

class _LyricsCard extends ConsumerWidget {
  const _LyricsCard({
    required this.trackId,
    required this.onViewLyrics,
    this.fillHeight = false,
    this.showHeader = true,
    super.key,
  });

  final String trackId;
  final VoidCallback onViewLyrics;
  final bool fillHeight;
  final bool showHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final textAlign = ref.watch(inAppLyricsTextAlignProvider);
    final alignment = _alignmentFor(textAlign);
    final viewport = MediaQuery.sizeOf(context);
    final tabletLandscape = !fillHeight &&
        viewport.shortestSide >= 600 &&
        viewport.width > viewport.height;
    final responsiveHeight = tabletLandscape
        ? (viewport.height * .55).clamp(300.0, 460.0).toDouble()
        : null;
    final expanded = fillHeight || responsiveHeight != null;
    final compactLyricsAction = showHeader && viewport.width < 480;

    return Container(
      width: double.infinity,
      height: fillHeight ? double.infinity : responsiveHeight,
      padding: EdgeInsets.all(fillHeight ? 34 : 22),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .065),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Column(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: _crossAxisFor(textAlign),
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    context.l10n.lyricsTitle.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white.withValues(alpha: .52),
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                if (compactLyricsAction)
                  IconButton(
                    tooltip: context.l10n.viewLyrics,
                    onPressed: onViewLyrics,
                    icon: const Icon(Icons.open_in_full_rounded),
                  )
                else
                  TextButton.icon(
                    onPressed: onViewLyrics,
                    icon: const Icon(Icons.open_in_full_rounded, size: 16),
                    label: Text(context.l10n.viewLyrics),
                  ),
              ],
            ),
            SizedBox(height: expanded ? 12 : 4),
          ],
          if (expanded)
            Expanded(
              child: NowPlayingLyrics(
                trackId: trackId,
                textAlign: textAlign,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: .46),
                activeStyle:
                    Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                inactiveStyle:
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                          height: 1.45,
                        ),
                expanded: true,
              ),
            )
          else
            Align(
              alignment: alignment,
              child: NowPlayingLyrics(
                trackId: trackId,
                textAlign: textAlign,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: .46),
                activeStyle:
                    Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.25,
                        ),
                inactiveStyle:
                    Theme.of(context).textTheme.titleMedium?.copyWith(
                          height: 1.45,
                        ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaybackControls extends ConsumerWidget {
  const _PlaybackControls({
    required this.playback,
    required this.compact,
    required this.isFavorite,
    required this.onFavorite,
    required this.onViewLyrics,
    required this.onQueue,
  });

  final PlaybackState playback;
  final bool compact;
  final bool isFavorite;
  final VoidCallback onFavorite;
  final VoidCallback onViewLyrics;
  final VoidCallback onQueue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(playerControllerProvider.notifier);
    final l10n = context.l10n;
    final isBusy = playback.isLoading;
    final canSeek = playback.canSeek && !isBusy;
    final secondarySize = compact ? 42.0 : 46.0;
    final primarySize = compact ? 64.0 : 70.0;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 22,
        compact ? 12 : 16,
        compact ? 14 : 22,
        compact ? 13 : 16,
      ),
      decoration: BoxDecoration(
        color: const Color(0xE8181B2A),
        borderRadius: BorderRadius.circular(compact ? 25 : 28),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (playback.errorMessage case final message?) ...[
            Text(
              message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            const SizedBox(height: 6),
          ],
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PlaybackTime(playback.position),
              if (isBusy)
                const SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                _PlaybackTime(
                  playback.canSeek ? playback.duration : Duration.zero,
                  empty: !playback.canSeek,
                ),
            ],
          ),
          _PlaybackSeekSlider(
            playback: playback,
            enabled: canSeek,
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              final auxiliaryActions = [
                _InlineAction(
                  key: const ValueKey('player-playback-mode-toggle'),
                  tooltip: _modeLabel(l10n, playback.playbackMode),
                  icon: _modeIcon(playback.playbackMode),
                  selected: playback.playbackMode != PlaybackMode.sequential,
                  onPressed: controller.cyclePlaybackMode,
                ),
                const SleepTimerButton(
                  iconSize: 20,
                  color: Colors.white70,
                ),
                _InlineAction(
                  key: const ValueKey('player-favorite-toggle'),
                  tooltip: isFavorite ? l10n.removeFavorite : l10n.addFavorite,
                  icon: isFavorite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  selected: isFavorite,
                  selectedColor: const Color(0xFFFF91B6),
                  onPressed: onFavorite,
                ),
                if (playback.currentTrack case final track?)
                  OfflineDownloadButton(
                    key: const ValueKey('player-current-track-download'),
                    track: track,
                  ),
                _InlineAction(
                  tooltip: l10n.viewLyrics,
                  icon: Icons.lyrics_outlined,
                  onPressed: onViewLyrics,
                ),
                _InlineAction(
                  tooltip: l10n.queue,
                  icon: Icons.queue_music_rounded,
                  onPressed: onQueue,
                ),
              ];
              final transportActions = [
                _TransportAction(
                  size: secondarySize,
                  tooltip: l10n.previous,
                  icon: Icons.skip_previous_rounded,
                  onPressed: playback.canSkipPrevious && !isBusy
                      ? () => unawaited(controller.previous())
                      : null,
                ),
                _TransportAction(
                  size: primarySize,
                  iconSize: compact ? 35 : 38,
                  tooltip: playback.isPlaying ? l10n.pause : l10n.play,
                  icon: playback.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  primary: true,
                  onPressed: isBusy
                      ? null
                      : () => unawaited(
                            playback.isPlaying
                                ? controller.pause()
                                : controller.play(),
                          ),
                ),
                _TransportAction(
                  size: secondarySize,
                  tooltip: l10n.next,
                  icon: Icons.skip_next_rounded,
                  onPressed: playback.canSkipNext && !isBusy
                      ? () => unawaited(controller.next())
                      : null,
                ),
              ];
              final stackActions = compact && constraints.maxWidth < 448;

              if (stackActions) {
                return Column(
                  key: const ValueKey('mobile-player-actions'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: auxiliaryActions,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: transportActions,
                    ),
                  ],
                );
              }

              return Row(
                key: compact ? const ValueKey('mobile-player-actions') : null,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ...auxiliaryActions.take(2),
                  ...transportActions,
                  ...auxiliaryActions.skip(2),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PlaybackSeekSlider extends ConsumerStatefulWidget {
  const _PlaybackSeekSlider({
    required this.playback,
    required this.enabled,
  });

  final PlaybackState playback;
  final bool enabled;

  @override
  ConsumerState<_PlaybackSeekSlider> createState() =>
      _PlaybackSeekSliderState();
}

class _PlaybackSeekSliderState extends ConsumerState<_PlaybackSeekSlider> {
  double? _dragValue;
  var _isDragging = false;

  @override
  void didUpdateWidget(covariant _PlaybackSeekSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final trackChanged =
        oldWidget.playback.currentTrack?.id != widget.playback.currentTrack?.id;
    if (!widget.enabled ||
        trackChanged ||
        oldWidget.playback.duration != widget.playback.duration) {
      _dragValue = null;
      _isDragging = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final maximum = _sliderMaximum(widget.playback);
    final value = (_dragValue ?? _sliderValue(widget.playback))
        .clamp(0.0, maximum)
        .toDouble();
    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        activeTrackColor: const Color(0xFFB8A7FF),
        inactiveTrackColor: Colors.white.withValues(alpha: .1),
        thumbColor: Colors.white,
        overlayColor: const Color(0x44B8A7FF),
        trackHeight: 3,
      ),
      child: Slider(
        key: const ValueKey('player-progress-slider'),
        value: value,
        max: maximum,
        onChangeStart: !widget.enabled
            ? null
            : (value) {
                setState(() {
                  _dragValue = value;
                  _isDragging = true;
                });
              },
        onChanged: !widget.enabled
            ? null
            : (value) {
                if (!_isDragging) {
                  return;
                }
                setState(() {
                  _dragValue = value;
                });
              },
        onChangeEnd: !widget.enabled
            ? null
            : (value) {
                if (!_isDragging) {
                  return;
                }
                final target = value
                    .clamp(0.0, _sliderMaximum(widget.playback))
                    .toDouble();
                setState(() {
                  _dragValue = null;
                  _isDragging = false;
                });
                unawaited(
                  ref
                      .read(playerControllerProvider.notifier)
                      .seek(Duration(milliseconds: target.round())),
                );
              },
      ),
    );
  }
}

class _PlaybackTime extends StatelessWidget {
  const _PlaybackTime(this.value, {this.empty = false});

  final Duration value;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    return Text(
      empty ? '--:--' : formatPlaybackTime(value),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Colors.white.withValues(alpha: .5),
          ),
    );
  }
}

class _TransportAction extends StatelessWidget {
  const _TransportAction({
    required this.size,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
    this.iconSize,
  });

  final double size;
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: primary ? null : Colors.white.withValues(alpha: .08),
        gradient: primary && enabled
            ? const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD0C4FF), Color(0xFF7D61F4)],
              )
            : null,
        boxShadow: primary && enabled
            ? const [
                BoxShadow(
                  color: Color(0x707D61F4),
                  blurRadius: 22,
                  offset: Offset(0, 9),
                ),
              ]
            : null,
      ),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        iconSize: iconSize ?? 27,
        color: primary ? const Color(0xFF18132A) : Colors.white,
        disabledColor: Colors.white.withValues(alpha: .26),
        icon: Icon(icon),
      ),
    );
  }
}

class _InlineAction extends StatelessWidget {
  const _InlineAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    this.selectedColor,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;
  final Color? selectedColor;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? selectedColor ?? _selectedActionColor
        : Colors.white.withValues(alpha: .62);
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
      icon: Icon(icon, size: 20, color: color),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.selected = false,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFF9A7DFF).withValues(alpha: .24)
          : Colors.white.withValues(alpha: .07),
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(
          icon,
          color: selected
              ? const Color(0xFFD1C6FF)
              : Colors.white.withValues(alpha: .84),
        ),
      ),
    );
  }
}

class _EmptyPlayerStage extends StatelessWidget {
  const _EmptyPlayerStage();

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      title: context.l10n.nothingPlayingTitle,
      message: context.l10n.nothingPlayingMessage,
      icon: Icons.play_circle_outline_rounded,
    );
  }
}

class _ImmersiveBackdrop extends StatelessWidget {
  const _ImmersiveBackdrop({
    required this.artworkUrl,
    required this.child,
  });

  final String? artworkUrl;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (artworkUrl != null)
          Opacity(
            opacity: .24,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 34, sigmaY: 34),
              child: Transform.scale(
                scale: 1.18,
                child: _backdropArtwork(artworkUrl!),
              ),
            ),
          ),
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xEE17112A),
                Color(0xF20D1020),
                Color(0xFA070910),
              ],
              stops: [0, .48, 1],
            ),
          ),
        ),
        const Positioned(
          top: -220,
          right: -180,
          child: _AmbientOrb(
            size: 500,
            color: Color(0x505C9DFF),
          ),
        ),
        const Positioned(
          bottom: -200,
          left: -150,
          child: _AmbientOrb(
            size: 440,
            color: Color(0x4047DFC5),
          ),
        ),
        child,
      ],
    );
  }
}

Widget _backdropArtwork(String artworkUrl) {
  final uri = Uri.tryParse(artworkUrl);
  if (uri?.scheme == 'file') {
    return Image.file(
      File(uri!.toFilePath()),
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
    );
  }
  return Image.network(
    artworkUrl,
    fit: BoxFit.cover,
    errorBuilder: (context, error, stackTrace) => const SizedBox.expand(),
  );
}

class _AmbientOrb extends StatelessWidget {
  const _AmbientOrb({
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, Colors.transparent],
          ),
        ),
      ),
    );
  }
}

class _CollectionsSheet extends ConsumerWidget {
  const _CollectionsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collections = ref.watch(collectionsControllerProvider).valueOrNull;
    final tracks = ref.watch(tracksProvider).valueOrNull?.tracks ?? const [];
    final tracksById = {for (final track in tracks) track.id: track};
    final favorites = (collections?.favoriteTrackIds ?? const <String>{})
        .map((trackId) => tracksById[trackId])
        .whereType<Track>()
        .toList(growable: false);
    final playlists = collections?.playlists ?? const [];

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .76,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFF171A29),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: Column(
          children: [
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.favorite_rounded, color: Color(0xFFFF91B6)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    context.l10n.yourCollection,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                IconButton(
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView(
                children: [
                  _CollectionPlayCard(
                    icon: Icons.favorite_rounded,
                    color: const Color(0xFFFF91B6),
                    title: context.l10n.favorites,
                    subtitle:
                        context.l10n.favoriteTracksCount(favorites.length),
                    onPlay: favorites.isEmpty
                        ? null
                        : () => _playTracks(context, ref, favorites),
                  ),
                  if (playlists.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Text(
                      context.l10n.playlists.toUpperCase(),
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Colors.white.withValues(alpha: .48),
                            letterSpacing: 1.1,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 8),
                    for (final playlist in playlists)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _CollectionPlayCard(
                          icon: Icons.queue_music_rounded,
                          color: const Color(0xFFC5B7FF),
                          title: playlist.name,
                          subtitle: context.l10n.trackCount(
                            playlist.trackIds.length,
                          ),
                          onPlay: () {
                            final playlistTracks = playlist.trackIds
                                .map((trackId) => tracksById[trackId])
                                .whereType<Track>()
                                .toList(growable: false);
                            if (playlistTracks.isNotEmpty) {
                              _playTracks(context, ref, playlistTracks);
                            }
                          },
                        ),
                      ),
                  ],
                  if (favorites.isEmpty && playlists.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 72),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_border_rounded,
                            size: 46,
                            color: Colors.white.withValues(alpha: .34),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            context.l10n.favoriteCollectionEmptyMessage,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.white.withValues(alpha: .5),
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _playTracks(
    BuildContext context,
    WidgetRef ref,
    List<Track> tracks,
  ) async {
    await ref.read(playerControllerProvider.notifier).setQueue(tracks);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _CollectionPlayCard extends StatelessWidget {
  const _CollectionPlayCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onPlay,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: .05),
      borderRadius: BorderRadius.circular(20),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .16),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(subtitle),
        trailing: IconButton(
          tooltip: context.l10n.playCollection,
          onPressed: onPlay,
          icon: const Icon(Icons.play_circle_fill_rounded),
        ),
        onTap: onPlay,
      ),
    );
  }
}

double _sliderValue(PlaybackState playback) {
  return playback.position.inMilliseconds
      .clamp(0, playback.duration.inMilliseconds)
      .toDouble();
}

double _sliderMaximum(PlaybackState playback) {
  return playback.canSeek ? playback.duration.inMilliseconds.toDouble() : 1;
}

IconData _modeIcon(PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.sequential => Icons.repeat_rounded,
    PlaybackMode.repeatAll => Icons.repeat_rounded,
    PlaybackMode.repeatOne => Icons.repeat_one_rounded,
    PlaybackMode.shuffle => Icons.shuffle_rounded,
  };
}

String _modeLabel(AppLocalizations l10n, PlaybackMode mode) {
  return switch (mode) {
    PlaybackMode.sequential => l10n.playbackModeSequential,
    PlaybackMode.repeatAll => l10n.playbackModeRepeatAll,
    PlaybackMode.repeatOne => l10n.playbackModeRepeatOne,
    PlaybackMode.shuffle => l10n.playbackModeShuffle,
  };
}

Alignment _alignmentFor(TextAlign textAlign) {
  return switch (textAlign) {
    TextAlign.left ||
    TextAlign.start ||
    TextAlign.justify =>
      Alignment.centerLeft,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.center,
  };
}

CrossAxisAlignment _crossAxisFor(TextAlign textAlign) {
  return switch (textAlign) {
    TextAlign.left ||
    TextAlign.start ||
    TextAlign.justify =>
      CrossAxisAlignment.start,
    TextAlign.right || TextAlign.end => CrossAxisAlignment.end,
    _ => CrossAxisAlignment.center,
  };
}
