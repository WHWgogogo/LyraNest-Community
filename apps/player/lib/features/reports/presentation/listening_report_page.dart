import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../l10n/l10n.dart';
import '../../tracks/presentation/library_ui.dart';
import '../../tracks/presentation/track_workflow.dart';
import '../data/listening_report_api.dart';
import '../domain/listening_report.dart';

class ListeningReportPage extends ConsumerWidget {
  const ListeningReportPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final year = DateTime.now().year;
    final report = ref.watch(listeningReportProvider(year));
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    return report.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _ReportError(
        onRetry: () => ref.invalidate(listeningReportProvider(year)),
      ),
      data: (data) => _ReportContent(
        report: data,
        artworkBaseUrl: artworkBaseUrl,
        onRefresh: () async {
          ref.invalidate(listeningReportProvider(year));
          await ref.read(listeningReportProvider(year).future);
        },
      ),
    );
  }
}

class _ReportContent extends ConsumerWidget {
  const _ReportContent({
    required this.report,
    required this.artworkBaseUrl,
    required this.onRefresh,
  });

  final ListeningReport report;
  final String artworkBaseUrl;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final workflow = TrackWorkflow(context: context, ref: ref);

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
            l10n.reportTitle,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: -.6,
                ),
          ),
          const SizedBox(height: 5),
          Text(
            l10n.reportSubtitle(report.year),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 20),
          _ListeningTimeHero(report: report),
          const SizedBox(height: 18),
          _ReportStats(report: report),
          const SizedBox(height: 26),
          Text(
            l10n.listeningHeatmap,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          _HeatmapCard(report: report),
          if (!report.hasListeningHistory) ...[
            const SizedBox(height: 14),
            _NoHistoryNotice(
              title: l10n.reportNoDataTitle,
              message: l10n.reportNoDataMessage,
            ),
          ],
          const SizedBox(height: 28),
          Text(
            l10n.popularTracks,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 12),
          if (report.topTracks.isEmpty)
            _NoHistoryNotice(
              title: l10n.reportNoDataTitle,
              message: l10n.reportNoDataMessage,
            )
          else
            _TopTracksCard(
              rankedTracks: report.topTracks,
              artworkBaseUrl: artworkBaseUrl,
              onPlay: (ranked) => workflow.playNow(ranked.track),
            ),
        ],
      ),
    );
  }
}

class _ListeningTimeHero extends StatelessWidget {
  const _ListeningTimeHero({required this.report});

  final ListeningReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final duration = Duration(seconds: report.totalListeningSeconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4D427E), Color(0xFF1B1D30)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x52000000),
            blurRadius: 24,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(Icons.headphones_rounded, size: 30),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.totalListeningTime,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.white.withValues(alpha: .64),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.listeningDuration(hours, minutes),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w900,
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
}

class _ReportStats extends StatelessWidget {
  const _ReportStats({required this.report});

  final ListeningReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final items = [
      _StatItem(
        icon: Icons.play_circle_outline_rounded,
        label: l10n.listeningTimes,
        value: report.playCount.toString(),
      ),
      _StatItem(
        icon: Icons.calendar_month_outlined,
        label: l10n.listeningDays,
        value: report.activeDays.toString(),
      ),
      _StatItem(
        icon: Icons.music_note_outlined,
        label: l10n.songsListened,
        value: report.songCount.toString(),
      ),
      _StatItem(
        icon: Icons.album_outlined,
        label: l10n.albumsListened,
        value: report.albumCount.toString(),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;

        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final item in items)
              SizedBox(width: width, child: _StatCard(item: item)),
          ],
        );
      },
    );
  }
}

class _StatItem {
  const _StatItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.item});

  final _StatItem item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: _reportGlassDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(item.icon, color: colors.primary),
            const SizedBox(height: 15),
            Text(
              item.value,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.report});

  final ListeningReport report;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: _reportGlassDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${report.year}',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Text(
                  'Less',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
                const SizedBox(width: 7),
                for (final intensity in const [.08, .23, .45, .78])
                  Container(
                    width: 11,
                    height: 11,
                    margin: const EdgeInsets.only(left: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(3),
                      color: Color.lerp(
                        colors.surfaceContainerHighest,
                        const Color(0xFFB8A7FF),
                        intensity,
                      ),
                    ),
                  ),
                const SizedBox(width: 7),
                Text(
                  'More',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _ListeningHeatmap(
              year: report.year,
              entries: report.heatmap,
            ),
          ],
        ),
      ),
    );
  }
}

class _ListeningHeatmap extends StatelessWidget {
  const _ListeningHeatmap({
    required this.year,
    required this.entries,
  });

  final int year;
  final List<ListeningHeatmapEntry> entries;

  @override
  Widget build(BuildContext context) {
    final counts = <DateTime, int>{
      for (final entry in entries)
        DateTime(entry.date.year, entry.date.month, entry.date.day):
            entry.playCount,
    };
    final maximum = math.max(
      1,
      counts.values.fold<int>(0, math.max),
    );
    final firstDay = DateTime(year);
    final start = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final lastDay = DateTime(year + 1).subtract(const Duration(days: 1));
    final end = lastDay.add(Duration(days: 6 - lastDay.weekday % 7));
    final weekCount = end.difference(start).inDays ~/ 7 + 1;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var week = 0; week < weekCount; week++) ...[
            Column(
              children: [
                for (var weekday = 0; weekday < 7; weekday++)
                  _HeatmapCell(
                    date: start.add(Duration(days: week * 7 + weekday)),
                    playCount:
                        counts[start.add(Duration(days: week * 7 + weekday))] ??
                            0,
                    maximum: maximum,
                  ),
              ],
            ),
            if (week != weekCount - 1) const SizedBox(width: 3),
          ],
        ],
      ),
    );
  }
}

class _HeatmapCell extends StatelessWidget {
  const _HeatmapCell({
    required this.date,
    required this.playCount,
    required this.maximum,
  });

  final DateTime date;
  final int playCount;
  final int maximum;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final intensity = playCount == 0
        ? .05
        : .18 + .82 * (math.log(playCount + 1) / math.log(maximum + 1));
    final color = Color.lerp(
      colors.surfaceContainerHighest,
      const Color(0xFFB8A7FF),
      intensity,
    );

    return Tooltip(
      message: '${date.year}-${date.month}-${date.day}: $playCount',
      child: Container(
        width: 11,
        height: 11,
        margin: const EdgeInsets.only(bottom: 3),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(3),
        ),
      ),
    );
  }
}

class _TopTracksCard extends StatelessWidget {
  const _TopTracksCard({
    required this.rankedTracks,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final List<RankedTrack> rankedTracks;
  final String artworkBaseUrl;
  final ValueChanged<RankedTrack> onPlay;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _reportGlassDecoration(),
      child: Column(
        children: [
          for (final (index, ranked) in rankedTracks.indexed) ...[
            ListTile(
              onTap: () => onPlay(ranked),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 5,
              ),
              leading: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text(
                      '${index + 1}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: index < 3
                                ? const Color(0xFFD5C8FF)
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                    ),
                  ),
                  const SizedBox(width: 9),
                  TrackArtwork(
                    track: ranked.track,
                    artworkBaseUrl: artworkBaseUrl,
                    size: 48,
                  ),
                ],
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
              trailing: Text(
                context.l10n.listeningPlayCount(ranked.playCount),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
            if (index != rankedTracks.length - 1)
              Divider(
                height: 1,
                indent: 76,
                color: Colors.white.withValues(alpha: .06),
              ),
          ],
        ],
      ),
    );
  }
}

class _NoHistoryNotice extends StatelessWidget {
  const _NoHistoryNotice({
    required this.title,
    required this.message,
  });

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _reportGlassDecoration(),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            const Icon(Icons.insights_outlined),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
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
}

class _ReportError extends StatelessWidget {
  const _ReportError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 14),
            Text(
              context.l10n.requestFailedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              context.l10n.networkRequestFailed,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.retry),
            ),
          ],
        ),
      ),
    );
  }
}

BoxDecoration _reportGlassDecoration() {
  return BoxDecoration(
    color: const Color(0xFF171A29).withValues(alpha: .9),
    borderRadius: BorderRadius.circular(24),
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
