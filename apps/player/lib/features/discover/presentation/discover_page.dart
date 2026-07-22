import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../l10n/l10n.dart';
import '../../reports/data/listening_report_api.dart';
import '../../reports/domain/listening_report.dart';
import '../../tracks/data/tracks_api.dart';
import '../../tracks/domain/track.dart';
import '../../tracks/presentation/library_ui.dart';
import '../../tracks/presentation/track_workflow.dart';
import '../data/discovery_api.dart';
import '../domain/discovery_data.dart';

class DiscoverPage extends ConsumerStatefulWidget {
  const DiscoverPage({super.key});

  @override
  ConsumerState<DiscoverPage> createState() => _DiscoverPageState();
}

class _DiscoverPageState extends ConsumerState<DiscoverPage> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final year = DateTime.now().year;
    final discovery = ref.watch(discoveryProvider);
    final library = ref.watch(tracksProvider);
    final listeningReport = ref.watch(listeningReportProvider(year));
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final fallbackTracks = library.valueOrNull?.tracks ?? const <Track>[];
    final data = discovery.valueOrNull ?? const DiscoveryData();
    final workflow = TrackWorkflow(context: context, ref: ref);
    final recommendations = _ResolvedRecommendations.from(
      data: data,
      fallbackTracks: fallbackTracks,
    );

    if (discovery.isLoading && library.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            l10n.discoverTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.discoverSubtitle,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          _DiscoverSearchField(
            controller: _searchController,
            hintText: l10n.discoverSearchHint,
            onSubmitted: _openSearch,
          ),
          if (discovery.hasError) ...[
            const SizedBox(height: 12),
            _FallbackNotice(message: l10n.discoverFallbackMessage),
          ],
          const SizedBox(height: 26),
          _SectionHeading(
            title: l10n.guessYouLike,
            actionLabel: l10n.viewAll,
            onAction: _openTracks,
          ),
          const SizedBox(height: 12),
          _TrackRail(
            tracks: recommendations.guessYouLike,
            artworkBaseUrl: artworkBaseUrl,
            emptyMessage: l10n.noRecommendations,
            onPlay: workflow.playNow,
          ),
          const SizedBox(height: 28),
          _DailyRecommendationCard(
            tracks: recommendations.dailyRecommendations,
            artworkBaseUrl: artworkBaseUrl,
            title: l10n.dailyRecommendations,
            subtitle: l10n.dailyRecommendationsSubtitle,
            emptyMessage: l10n.noRecommendations,
            onPlay: workflow.playNow,
            onPlayAll: () => workflow.playTracks(
              recommendations.dailyRecommendations,
            ),
          ),
          const SizedBox(height: 28),
          _SectionHeading(
            title: l10n.listeningRanking,
            actionLabel: l10n.viewAll,
            onAction: () => context.go('/report'),
          ),
          const SizedBox(height: 12),
          _RankingList(
            rankedTracks: listeningReport.valueOrNull?.topTracks ?? const [],
            artworkBaseUrl: artworkBaseUrl,
            emptyMessage: l10n.noListeningRanking,
            onPlay: (ranked) => workflow.playNow(ranked.track),
          ),
          const SizedBox(height: 28),
          _SectionHeading(
            title: l10n.recentListeningRecommendations,
            actionLabel: l10n.viewAll,
            onAction: _openTracks,
          ),
          const SizedBox(height: 12),
          _TrackRail(
            tracks: recommendations.recentRecommendations,
            artworkBaseUrl: artworkBaseUrl,
            emptyMessage: l10n.noRecommendations,
            onPlay: workflow.playNow,
          ),
          const SizedBox(height: 28),
          _SectionHeading(
            title: l10n.moreRecommendedSongs,
            actionLabel: l10n.viewAll,
            onAction: _openTracks,
          ),
          const SizedBox(height: 12),
          _TrackRail(
            tracks: recommendations.moreRecommendations,
            artworkBaseUrl: artworkBaseUrl,
            emptyMessage: l10n.noRecommendations,
            onPlay: workflow.playNow,
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    final year = DateTime.now().year;
    ref
      ..invalidate(discoveryProvider)
      ..invalidate(listeningReportProvider(year))
      ..invalidate(tracksProvider);
    await Future.wait([
      ref.read(discoveryProvider.future),
      ref.read(listeningReportProvider(year).future),
    ]);
  }

  void _openSearch(String value) {
    final query = value.trim();
    final uri = Uri(
      path: '/tracks',
      queryParameters: query.isEmpty ? null : {'q': query},
    );
    context.go(uri.toString());
  }

  void _openTracks() {
    context.go('/tracks');
  }
}

class _ResolvedRecommendations {
  const _ResolvedRecommendations({
    required this.guessYouLike,
    required this.dailyRecommendations,
    required this.recentRecommendations,
    required this.moreRecommendations,
  });

  final List<Track> guessYouLike;
  final List<Track> dailyRecommendations;
  final List<Track> recentRecommendations;
  final List<Track> moreRecommendations;

  factory _ResolvedRecommendations.from({
    required DiscoveryData data,
    required List<Track> fallbackTracks,
  }) {
    List<Track> resolve(List<Track> tracks, Iterable<Track> fallback) {
      return tracks.isNotEmpty ? tracks : fallback.toList(growable: false);
    }

    return _ResolvedRecommendations(
      guessYouLike: resolve(data.guessYouLike, fallbackTracks.take(12)),
      dailyRecommendations: resolve(
        data.dailyRecommendations,
        fallbackTracks.take(30),
      ).take(30).toList(growable: false),
      recentRecommendations: resolve(
        data.recentRecommendations,
        fallbackTracks.skip(3).take(12),
      ),
      moreRecommendations: resolve(
        data.moreRecommendations,
        fallbackTracks.skip(6).take(16),
      ),
    );
  }
}

class _DiscoverSearchField extends StatelessWidget {
  const _DiscoverSearchField({
    required this.controller,
    required this.hintText,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF181B2B).withValues(alpha: .9),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.white.withValues(alpha: .09)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        onSubmitted: onSubmitted,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: IconButton(
            tooltip: context.l10n.navigationTracks,
            onPressed: () => onSubmitted(controller.text),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 17),
        ),
      ),
    );
  }
}

class _FallbackNotice extends StatelessWidget {
  const _FallbackNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.library_music_outlined, size: 18),
            const SizedBox(width: 9),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    required this.actionLabel,
    required this.onAction,
  });

  final String title;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
        TextButton(
          onPressed: onAction,
          child: Text(actionLabel),
        ),
      ],
    );
  }
}

class _TrackRail extends StatelessWidget {
  const _TrackRail({
    required this.tracks,
    required this.artworkBaseUrl,
    required this.emptyMessage,
    required this.onPlay,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final String emptyMessage;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    if (tracks.isEmpty) {
      return _EmptyRecommendationCard(message: emptyMessage);
    }

    return SizedBox(
      height: 210,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: tracks.length,
        separatorBuilder: (context, index) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return _TrackPoster(
            track: tracks[index],
            artworkBaseUrl: artworkBaseUrl,
            onPlay: () => onPlay(tracks[index]),
          );
        },
      ),
    );
  }
}

class _TrackPoster extends StatelessWidget {
  const _TrackPoster({
    required this.track,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final Track track;
  final String artworkBaseUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 138,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF171A29),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: .07)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: TrackArtwork(
                          track: track,
                          artworkBaseUrl: artworkBaseUrl,
                          size: 122,
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: _PlayBadge(onPressed: onPlay),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 9),
                Text(
                  track.localizedTitle(context.l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  track.localizedArtist(context.l10n),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DailyRecommendationCard extends StatelessWidget {
  const _DailyRecommendationCard({
    required this.tracks,
    required this.artworkBaseUrl,
    required this.title,
    required this.subtitle,
    required this.emptyMessage,
    required this.onPlay,
    required this.onPlayAll,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final String title;
  final String subtitle;
  final String emptyMessage;
  final ValueChanged<Track> onPlay;
  final VoidCallback onPlayAll;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF433A74), Color(0xFF191B2D)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(Icons.today_rounded),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: .64),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton.filled(
                  tooltip: context.l10n.play,
                  onPressed: tracks.isEmpty ? null : onPlayAll,
                  icon: const Icon(Icons.play_arrow_rounded),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (tracks.isEmpty)
              _EmptyRecommendationCard(message: emptyMessage)
            else
              SizedBox(
                height: 78,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: tracks.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    return _DailyTrackTile(
                      index: index + 1,
                      track: track,
                      artworkBaseUrl: artworkBaseUrl,
                      onPlay: () => onPlay(track),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DailyTrackTile extends StatelessWidget {
  const _DailyTrackTile({
    required this.index,
    required this.track,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final int index;
  final Track track;
  final String artworkBaseUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Material(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onPlay,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Text(
                  index.toString().padLeft(2, '0'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: Colors.white.withValues(alpha: .48),
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 8),
                TrackArtwork(
                  track: track,
                  artworkBaseUrl: artworkBaseUrl,
                  size: 50,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.localizedTitle(context.l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.localizedArtist(context.l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: .58),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RankingList extends StatelessWidget {
  const _RankingList({
    required this.rankedTracks,
    required this.artworkBaseUrl,
    required this.emptyMessage,
    required this.onPlay,
  });

  final List<RankedTrack> rankedTracks;
  final String artworkBaseUrl;
  final String emptyMessage;
  final ValueChanged<RankedTrack> onPlay;

  @override
  Widget build(BuildContext context) {
    if (rankedTracks.isEmpty) {
      return _EmptyRecommendationCard(message: emptyMessage);
    }

    return DecoratedBox(
      decoration: _glassDecoration(),
      child: Column(
        children: [
          for (final (index, ranked) in rankedTracks.take(5).indexed) ...[
            ListTile(
              onTap: () => onPlay(ranked),
              leading: SizedBox(
                width: 30,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: index < 3
                            ? const Color(0xFFD5C8FF)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              title: Text(
                ranked.track.localizedTitle(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                ranked.track.localizedArtist(context.l10n),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _PlayBadge(onPressed: () => onPlay(ranked)),
            ),
            if (index != rankedTracks.take(5).length - 1)
              Divider(
                height: 1,
                indent: 60,
                color: Colors.white.withValues(alpha: .06),
              ),
          ],
        ],
      ),
    );
  }
}

class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFE0D8FF),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(14),
        child: const Padding(
          padding: EdgeInsets.all(7),
          child: Icon(
            Icons.play_arrow_rounded,
            color: Color(0xFF17132A),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _EmptyRecommendationCard extends StatelessWidget {
  const _EmptyRecommendationCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _glassDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(
              Icons.auto_awesome_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _glassDecoration({double borderRadius = 24}) {
  return BoxDecoration(
    color: const Color(0xFF171A29).withValues(alpha: .9),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(color: Colors.white.withValues(alpha: .08)),
    boxShadow: const [
      BoxShadow(
        color: Color(0x3D000000),
        blurRadius: 20,
        offset: Offset(0, 8),
      ),
    ],
  );
}
