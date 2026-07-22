import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/empty_state.dart';
import '../../collections/application/collections_controller.dart';
import '../../collections/domain/playlist.dart';
import '../../tracks/data/tracks_api.dart';
import '../../tracks/domain/track.dart';
import '../../tracks/domain/track_list.dart';
import '../../tracks/presentation/library_ui.dart';
import '../../tracks/presentation/track_workflow.dart';

class HomePage extends ConsumerStatefulWidget {
  const HomePage({super.key});

  @override
  ConsumerState<HomePage> createState() => _HomePageState();
}

class _HomePageState extends ConsumerState<HomePage> {
  var _selectedDestination = MusicNavigationDestination.home;

  @override
  Widget build(BuildContext context) {
    final tracks = ref.watch(tracksProvider);
    final favoriteTrackIds = ref.watch(favoriteTrackIdsProvider);
    final playlists = ref.watch(playlistsProvider);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    return ResponsivePlayerScaffold(
      title: _selectedDestination.label,
      selectedDestination: _selectedDestination,
      onDestinationSelected: (destination) {
        setState(() {
          _selectedDestination = destination;
        });
      },
      actions: [
        IconButton(
          tooltip: '管理曲库',
          onPressed: () => context.push('/management'),
          icon: const Icon(Icons.library_music_outlined),
        ),
        IconButton(
          tooltip: '设置',
          onPressed: () => context.push('/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      child: tracks.when(
        data: (trackList) => _HomeDestinationView(
          selectedDestination: _selectedDestination,
          trackList: trackList,
          favoriteTrackIds: favoriteTrackIds,
          playlists: playlists,
          artworkBaseUrl: artworkBaseUrl,
          onSelectDestination: (destination) {
            setState(() {
              _selectedDestination = destination;
            });
          },
          ref: ref,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => _HomeLoadError(
          onRetry: () => ref.invalidate(tracksProvider),
        ),
      ),
    );
  }
}

class _HomeDestinationView extends StatelessWidget {
  const _HomeDestinationView({
    required this.selectedDestination,
    required this.trackList,
    required this.favoriteTrackIds,
    required this.playlists,
    required this.artworkBaseUrl,
    required this.onSelectDestination,
    required this.ref,
  });

  final MusicNavigationDestination selectedDestination;
  final TrackList trackList;
  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;
  final String artworkBaseUrl;
  final ValueChanged<MusicNavigationDestination> onSelectDestination;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final workflow = TrackWorkflow(context: context, ref: ref);

    return switch (selectedDestination) {
      MusicNavigationDestination.home => _HomeOverview(
          tracks: trackList.tracks,
          favoriteTrackIds: favoriteTrackIds,
          playlists: playlists,
          artworkBaseUrl: artworkBaseUrl,
          onPlay: workflow.playNow,
          onSelectDestination: onSelectDestination,
        ),
      MusicNavigationDestination.library => _LibraryOverview(
          tracks: trackList.tracks,
          favoriteTrackIds: favoriteTrackIds,
          playlists: playlists,
          onOpenFavorites: () {
            onSelectDestination(MusicNavigationDestination.favorites);
          },
        ),
      MusicNavigationDestination.favorites => _FavoritesOverview(
          tracks: trackList.tracks,
          favoriteTrackIds: favoriteTrackIds,
          artworkBaseUrl: artworkBaseUrl,
          onPlayTracks: workflow.playTracks,
          onToggleFavorite: workflow.toggleFavorite,
        ),
      MusicNavigationDestination.profile => const _ProfileOverview(),
    };
  }
}

class _HomeOverview extends StatelessWidget {
  const _HomeOverview({
    required this.tracks,
    required this.favoriteTrackIds,
    required this.playlists,
    required this.artworkBaseUrl,
    required this.onPlay,
    required this.onSelectDestination,
  });

  final List<Track> tracks;
  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;
  final String artworkBaseUrl;
  final ValueChanged<Track> onPlay;
  final ValueChanged<MusicNavigationDestination> onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final recentTracks = tracks.take(6).toList(growable: false);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        _SectionHeading(
          title: '为你准备',
          subtitle: '从熟悉的声音开始今天的播放',
        ),
        const SizedBox(height: 16),
        if (tracks.isEmpty)
          const _HomeEmptyLibrary()
        else
          _FeaturedMediaCard(
            track: tracks.first,
            artworkBaseUrl: artworkBaseUrl,
            onPlay: () => onPlay(tracks.first),
          ),
        const SizedBox(height: 28),
        const _SectionHeading(title: '最近加入', actionLabel: '查看曲库'),
        const SizedBox(height: 12),
        if (recentTracks.isEmpty)
          const _InlineEmptyState(message: '曲库为空，扫描音乐后会显示在这里。')
        else
          _RecentTrackGrid(
            tracks: recentTracks,
            artworkBaseUrl: artworkBaseUrl,
            onPlay: onPlay,
          ),
        const SizedBox(height: 28),
        const _SectionHeading(title: '快捷入口'),
        const SizedBox(height: 12),
        _QuickEntryGrid(
          tracks: tracks,
          favoriteTrackIds: favoriteTrackIds,
          playlists: playlists,
          onSelectDestination: onSelectDestination,
        ),
      ],
    );
  }
}

class _FeaturedMediaCard extends StatelessWidget {
  const _FeaturedMediaCard({
    required this.track,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final Track track;
  final String artworkBaseUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primaryContainer.withValues(alpha: 0.9),
            colors.tertiaryContainer.withValues(alpha: 0.74),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 460;
            final artwork = TrackArtwork(
              track: track,
              artworkBaseUrl: artworkBaseUrl,
              size: stacked ? 92 : 128,
            );
            final details = _FeaturedMediaDetails(track: track, onPlay: onPlay);

            return stacked
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      artwork,
                      const SizedBox(height: 20),
                      details,
                    ],
                  )
                : Row(
                    children: [
                      artwork,
                      const SizedBox(width: 20),
                      Expanded(child: details),
                    ],
                  );
          },
        ),
      ),
    );
  }
}

class _FeaturedMediaDetails extends StatelessWidget {
  const _FeaturedMediaDetails({
    required this.track,
    required this.onPlay,
  });

  final Track track;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '今日推荐',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.onPrimaryContainer.withValues(alpha: 0.72),
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          track.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: colors.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 5),
        Text(
          track.artist?.trim().isNotEmpty == true ? track.artist! : '未知艺术家',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: colors.onPrimaryContainer.withValues(alpha: 0.75),
              ),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: onPlay,
          icon: const Icon(Icons.play_arrow_rounded),
          label: const Text('立即播放'),
          style: FilledButton.styleFrom(
            backgroundColor: colors.onPrimaryContainer,
            foregroundColor: colors.primaryContainer,
          ),
        ),
      ],
    );
  }
}

class _RecentTrackGrid extends StatelessWidget {
  const _RecentTrackGrid({
    required this.tracks,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final ValueChanged<Track> onPlay;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = switch (constraints.maxWidth) {
          >= 980 => 3,
          >= 620 => 2,
          _ => 1,
        };
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 12)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final track in tracks)
              SizedBox(
                width: itemWidth,
                child: _RecentTrackCard(
                  track: track,
                  artworkBaseUrl: artworkBaseUrl,
                  onPlay: () => onPlay(track),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _RecentTrackCard extends StatelessWidget {
  const _RecentTrackCard({
    required this.track,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final Track track;
  final String artworkBaseUrl;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onPlay,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              TrackArtwork(
                track: track,
                artworkBaseUrl: artworkBaseUrl,
                size: 54,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist?.trim().isNotEmpty == true
                          ? track.artist!
                          : '未知艺术家',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.play_circle_outline_rounded,
                color: colors.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickEntryGrid extends StatelessWidget {
  const _QuickEntryGrid({
    required this.tracks,
    required this.favoriteTrackIds,
    required this.playlists,
    required this.onSelectDestination,
  });

  final List<Track> tracks;
  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;
  final ValueChanged<MusicNavigationDestination> onSelectDestination;

  @override
  Widget build(BuildContext context) {
    final items = [
      _QuickEntry(
        icon: Icons.library_music_outlined,
        label: '全部歌曲',
        detail: '${tracks.length} 首',
        color: Theme.of(context).colorScheme.primaryContainer,
        onTap: () => onSelectDestination(MusicNavigationDestination.library),
      ),
      _QuickEntry(
        icon: Icons.favorite_border,
        label: '我喜欢的',
        detail: '${favoriteTrackIds.length} 首',
        color: Theme.of(context).colorScheme.secondaryContainer,
        onTap: () => onSelectDestination(MusicNavigationDestination.favorites),
      ),
      _QuickEntry(
        icon: Icons.queue_music_outlined,
        label: '歌单',
        detail: '${playlists.length} 个',
        color: Theme.of(context).colorScheme.tertiaryContainer,
        onTap: () => context.push('/collections'),
      ),
      _QuickEntry(
        icon: Icons.album_outlined,
        label: '专辑',
        detail: '${_distinctAlbums(tracks)} 张',
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        onTap: () => context.push('/albums'),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 4 : 2;
        final itemWidth =
            (constraints.maxWidth - ((columns - 1) * 12)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(width: itemWidth, child: _QuickEntryCard(item: item)),
          ],
        );
      },
    );
  }
}

class _QuickEntry {
  const _QuickEntry({
    required this.icon,
    required this.label,
    required this.detail,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String detail;
  final Color color;
  final VoidCallback onTap;
}

class _QuickEntryCard extends StatelessWidget {
  const _QuickEntryCard({required this.item});

  final _QuickEntry item;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: item.color,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(item.icon, color: colors.onSurface),
              const SizedBox(height: 22),
              Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                item.detail,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryOverview extends StatelessWidget {
  const _LibraryOverview({
    required this.tracks,
    required this.favoriteTrackIds,
    required this.playlists,
    required this.onOpenFavorites,
  });

  final List<Track> tracks;
  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;
  final VoidCallback onOpenFavorites;

  @override
  Widget build(BuildContext context) {
    final entries = [
      _LibraryEntry(
        title: '全部歌曲',
        subtitle: '${tracks.length} 首歌曲',
        icon: Icons.music_note_outlined,
        onTap: () => context.go('/'),
      ),
      _LibraryEntry(
        title: '收藏',
        subtitle: '${favoriteTrackIds.length} 首喜欢的歌曲',
        icon: Icons.favorite_border,
        onTap: onOpenFavorites,
      ),
      _LibraryEntry(
        title: '歌单',
        subtitle: '${playlists.length} 个歌单',
        icon: Icons.queue_music_outlined,
        onTap: () => context.push('/collections'),
      ),
      _LibraryEntry(
        title: '专辑',
        subtitle: '${_distinctAlbums(tracks)} 张专辑',
        icon: Icons.album_outlined,
        onTap: () => context.push('/albums'),
      ),
      _LibraryEntry(
        title: '艺术家',
        subtitle: '${_distinctArtists(tracks)} 位艺术家',
        icon: Icons.person_outline,
        onTap: () => context.push('/artists'),
      ),
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _SectionHeading(
          title: '我的曲库',
          subtitle: '收藏、歌单、专辑和艺术家仍可在曲库页同屏切换。',
        ),
        const SizedBox(height: 18),
        for (final entry in entries) ...[
          _LibraryEntryCard(entry: entry),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _LibraryEntry {
  const _LibraryEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
}

class _LibraryEntryCard extends StatelessWidget {
  const _LibraryEntryCard({required this.entry});

  final _LibraryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colors.primaryContainer.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(entry.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _FavoritesOverview extends StatelessWidget {
  const _FavoritesOverview({
    required this.tracks,
    required this.favoriteTrackIds,
    required this.artworkBaseUrl,
    required this.onPlayTracks,
    required this.onToggleFavorite,
  });

  final List<Track> tracks;
  final Set<String> favoriteTrackIds;
  final String artworkBaseUrl;
  final void Function(List<Track>, {int initialIndex}) onPlayTracks;
  final ValueChanged<Track> onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final favorites = tracks
        .where((track) => favoriteTrackIds.contains(track.id))
        .toList(growable: false);

    if (favorites.isEmpty) {
      return const _HomeEmptyFavorites();
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      itemCount: favorites.length + 1,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SectionHeading(
            title: '我的收藏',
            subtitle: '${favorites.length} 首喜欢的歌曲',
          );
        }
        final trackIndex = index - 1;
        final track = favorites[trackIndex];
        return TrackListCard(
          track: track,
          artworkBaseUrl: artworkBaseUrl,
          onTap: () => onPlayTracks(favorites, initialIndex: trackIndex),
          actions: [
            IconButton(
              tooltip: '取消收藏',
              onPressed: () => onToggleFavorite(track),
              icon: const Icon(Icons.favorite),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileOverview extends StatelessWidget {
  const _ProfileOverview();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      children: [
        const _SectionHeading(
          title: '我的',
          subtitle: '管理你的服务与本地音乐库。',
        ),
        const SizedBox(height: 18),
        _ProfileActionCard(
          icon: Icons.settings_outlined,
          title: '服务器设置',
          subtitle: '连接与账户配置',
          color: colors.primaryContainer,
          onTap: () => context.push('/settings'),
        ),
        const SizedBox(height: 12),
        _ProfileActionCard(
          icon: Icons.library_music_outlined,
          title: '管理曲库',
          subtitle: '扫描与维护本地音乐',
          color: colors.secondaryContainer,
          onTap: () => context.push('/management'),
        ),
      ],
    );
  }
}

class _ProfileActionCard extends StatelessWidget {
  const _ProfileActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: color,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, size: 28, color: colors.onSurface),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.subtitle,
    this.actionLabel,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ],
            ],
          ),
        ),
        if (actionLabel != null)
          Text(
            actionLabel!,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: colors.primary,
                  fontWeight: FontWeight.w700,
                ),
          ),
      ],
    );
  }
}

class _HomeLoadError extends StatelessWidget {
  const _HomeLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: FilledButton.icon(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('重新加载曲库'),
        ),
      ),
    );
  }
}

class _HomeEmptyLibrary extends StatelessWidget {
  const _HomeEmptyLibrary();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 42),
      child: EmptyState(
        title: '曲库为空',
        message: '扫描本地音乐后，首页会为你整理最近加入的内容。',
        icon: Icons.library_music_outlined,
      ),
    );
  }
}

class _HomeEmptyFavorites extends StatelessWidget {
  const _HomeEmptyFavorites();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: EmptyState(
        title: '还没有收藏',
        message: '在曲库中点按爱心，喜欢的歌曲会显示在这里。',
        icon: Icons.favorite_border,
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  const _InlineEmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

int _distinctAlbums(List<Track> tracks) {
  return tracks
      .map((track) => track.album?.trim())
      .whereType<String>()
      .where((album) => album.isNotEmpty)
      .toSet()
      .length;
}

int _distinctArtists(List<Track> tracks) {
  return tracks
      .map((track) => track.artist?.trim())
      .whereType<String>()
      .where((artist) => artist.isNotEmpty)
      .toSet()
      .length;
}
