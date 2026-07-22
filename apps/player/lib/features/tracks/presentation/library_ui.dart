import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../offline/presentation/offline_download_button.dart';
import '../domain/track.dart';

String trackArtworkUrl(String baseUrl, String trackId) {
  final normalizedBaseUrl = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  return '$normalizedBaseUrl/api/v1/tracks/'
      '${Uri.encodeComponent(trackId)}/artwork';
}

String formatTrackDuration(int? totalSeconds) {
  if (totalSeconds == null || totalSeconds < 0) {
    return '';
  }

  final minutes = totalSeconds ~/ 60;
  final seconds = totalSeconds % 60;
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

extension TrackPresentationX on Track {
  bool get hasAlbumName => album?.trim().isNotEmpty == true;

  bool get hasArtistName => artist?.trim().isNotEmpty == true;
}

class TrackArtwork extends StatelessWidget {
  const TrackArtwork({
    required this.track,
    required this.artworkBaseUrl,
    this.size = 58,
    super.key,
  });

  final Track track;
  final String artworkBaseUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Image.network(
          trackArtworkUrl(artworkBaseUrl, track.id),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return Stack(
              fit: StackFit.expand,
              children: [
                _ArtworkPlaceholder(track: track),
                const Center(
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            );
          },
          errorBuilder: (context, error, stackTrace) {
            return _ArtworkPlaceholder(track: track);
          },
        ),
      ),
    );
  }
}

class TrackListCard extends StatelessWidget {
  const TrackListCard({
    required this.track,
    required this.artworkBaseUrl,
    required this.onTap,
    this.actions = const [],
    this.showAlbum = true,
    this.showMetadata = true,
    this.onLongPress,
    this.selected = false,
    super.key,
  });

  final Track track;
  final String artworkBaseUrl;
  final VoidCallback onTap;
  final List<Widget> actions;
  final bool showAlbum;
  final bool showMetadata;
  final VoidCallback? onLongPress;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final subtitleParts = [
      track.localizedArtist(l10n),
      if (showAlbum && track.hasAlbumName) track.album!.trim(),
    ];
    final metadata = [
      formatTrackDuration(track.durationSeconds),
      if (track.genres.isNotEmpty) track.genres.join(' · '),
    ].where((value) => value.isNotEmpty).join(' · ');

    return Semantics(
      selected: selected,
      child: Card(
        color: selected ? theme.colorScheme.secondaryContainer : null,
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                TrackArtwork(track: track, artworkBaseUrl: artworkBaseUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.localizedTitle(l10n),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitleParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (showMetadata && metadata.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (actions.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: actions,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class LibraryBreakpoints {
  const LibraryBreakpoints._();

  static const compact = 720.0;
  static const desktop = 1024.0;

  static bool usesCompactNavigation(double width) => width < compact;

  static bool usesDesktopNavigation(double width) => width >= desktop;
}

enum MusicNavigationDestination {
  home,
  library,
  favorites,
  profile,
}

extension MusicNavigationDestinationX on MusicNavigationDestination {
  String get label {
    return switch (this) {
      MusicNavigationDestination.home => '首页',
      MusicNavigationDestination.library => '曲库',
      MusicNavigationDestination.favorites => '收藏',
      MusicNavigationDestination.profile => '我的',
    };
  }

  IconData get icon {
    return switch (this) {
      MusicNavigationDestination.home => Icons.home_outlined,
      MusicNavigationDestination.library => Icons.library_music_outlined,
      MusicNavigationDestination.favorites => Icons.favorite_border,
      MusicNavigationDestination.profile => Icons.person_outline,
    };
  }

  IconData get selectedIcon {
    return switch (this) {
      MusicNavigationDestination.home => Icons.home_rounded,
      MusicNavigationDestination.library => Icons.library_music_rounded,
      MusicNavigationDestination.favorites => Icons.favorite_rounded,
      MusicNavigationDestination.profile => Icons.person_rounded,
    };
  }
}

class ResponsivePlayerScaffold extends StatefulWidget {
  const ResponsivePlayerScaffold({
    required this.title,
    required this.selectedDestination,
    required this.onDestinationSelected,
    required this.child,
    this.actions = const [],
    this.desktopPlayer,
    this.compactPlayer,
    super.key,
  });

  final String title;
  final MusicNavigationDestination selectedDestination;
  final ValueChanged<MusicNavigationDestination> onDestinationSelected;
  final Widget child;
  final List<Widget> actions;
  final Widget? desktopPlayer;
  final Widget? compactPlayer;

  @override
  State<ResponsivePlayerScaffold> createState() =>
      _ResponsivePlayerScaffoldState();
}

class _ResponsivePlayerScaffoldState extends State<ResponsivePlayerScaffold> {
  var _isNavigationCollapsed = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (LibraryBreakpoints.usesDesktopNavigation(width)) {
          return _buildDesktopLayout(context);
        }

        return _buildCompactLayout(
          context,
          isCompact: LibraryBreakpoints.usesCompactNavigation(width),
        );
      },
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: Row(
        children: [
          _DesktopNavigation(
            selectedDestination: widget.selectedDestination,
            collapsed: _isNavigationCollapsed,
            onCollapsedChanged: () {
              setState(() {
                _isNavigationCollapsed = !_isNavigationCollapsed;
              });
            },
            onDestinationSelected: widget.onDestinationSelected,
          ),
          VerticalDivider(
            width: 1,
            thickness: 1,
            color: colors.outlineVariant.withValues(alpha: 0.32),
          ),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _LibraryTopBar(title: widget.title, actions: widget.actions),
                  Expanded(child: widget.child),
                  widget.desktopPlayer ??
                      const BottomPlayerReservation(compact: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactLayout(
    BuildContext context, {
    required bool isCompact,
  }) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _LibraryTopBar(
              title: widget.title,
              actions: widget.actions,
              compact: isCompact,
            ),
            Expanded(child: widget.child),
            widget.compactPlayer ?? BottomPlayerReservation(compact: isCompact),
            _CompactNavigation(
              selectedDestination: widget.selectedDestination,
              onDestinationSelected: widget.onDestinationSelected,
            ),
          ],
        ),
      ),
    );
  }
}

class BottomPlayerReservation extends StatelessWidget {
  const BottomPlayerReservation({
    this.compact = false,
    super.key,
  });

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final content = Row(
      children: [
        Container(
          width: compact ? 42 : 46,
          height: compact ? 42 : 46,
          decoration: BoxDecoration(
            color: colors.primaryContainer.withValues(alpha: 0.62),
            borderRadius: BorderRadius.circular(compact ? 14 : 16),
          ),
          child: Icon(
            Icons.graphic_eq_rounded,
            color: colors.onPrimaryContainer,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                compact ? '迷你播放器' : '播放器控制区',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 2),
              Text(
                compact ? '播放内容将在这里显示' : '底部播放器将在这里显示',
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
    );

    return SafeArea(
      top: false,
      child: Padding(
        padding:
            EdgeInsets.fromLTRB(compact ? 12 : 20, 6, compact ? 12 : 20, 8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerHigh.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(compact ? 20 : 24),
            border: Border.all(
              color: colors.outlineVariant.withValues(alpha: 0.35),
            ),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 16,
              vertical: compact ? 10 : 12,
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

class _DesktopNavigation extends StatelessWidget {
  const _DesktopNavigation({
    required this.selectedDestination,
    required this.collapsed,
    required this.onCollapsedChanged,
    required this.onDestinationSelected,
  });

  final MusicNavigationDestination selectedDestination;
  final bool collapsed;
  final VoidCallback onCollapsedChanged;
  final ValueChanged<MusicNavigationDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: collapsed ? 88 : 248,
      color: colors.surface.withValues(alpha: 0.68),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(collapsed ? 16 : 20, 12, 12, 18),
              child: collapsed
                  ? IconButton(
                      tooltip: '展开导航',
                      onPressed: onCollapsedChanged,
                      icon: const Icon(
                        Icons.keyboard_double_arrow_right_rounded,
                      ),
                    )
                  : Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                colors.primary,
                                colors.tertiary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.multitrack_audio_rounded,
                            color: colors.onPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            context.l10n.appTitle,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: '收起导航',
                          onPressed: onCollapsedChanged,
                          icon: const Icon(
                            Icons.keyboard_double_arrow_left_rounded,
                          ),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  for (final destination in MusicNavigationDestination.values)
                    _DesktopNavigationItem(
                      destination: destination,
                      selected: destination == selectedDestination,
                      collapsed: collapsed,
                      onTap: () => onDestinationSelected(destination),
                    ),
                ],
              ),
            ),
            if (!collapsed)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Text(
                  '你的音乐，随时可听',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurfaceVariant,
                      ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNavigationItem extends StatelessWidget {
  const _DesktopNavigationItem({
    required this.destination,
    required this.selected,
    required this.collapsed,
    required this.onTap,
  });

  final MusicNavigationDestination destination;
  final bool selected;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final foreground =
        selected ? colors.onSecondaryContainer : colors.onSurfaceVariant;
    final tile = InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.only(bottom: 8),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 14 : 16,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment:
              collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              color: foreground,
            ),
            if (!collapsed) ...[
              const SizedBox(width: 14),
              Text(
                destination.label,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: foreground,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
              ),
            ],
          ],
        ),
      ),
    );

    return collapsed ? Tooltip(message: destination.label, child: tile) : tile;
  }
}

class _CompactNavigation extends StatelessWidget {
  const _CompactNavigation({
    required this.selectedDestination,
    required this.onDestinationSelected,
  });

  final MusicNavigationDestination selectedDestination;
  final ValueChanged<MusicNavigationDestination> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedDestination.index,
      onDestinationSelected: (index) {
        onDestinationSelected(MusicNavigationDestination.values[index]);
      },
      destinations: [
        for (final destination in MusicNavigationDestination.values)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
          ),
      ],
    );
  }
}

class _LibraryTopBar extends StatelessWidget {
  const _LibraryTopBar({
    required this.title,
    required this.actions,
    this.compact = false,
  });

  final String title;
  final List<Widget> actions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 16 : 28, 10, compact ? 8 : 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

enum TrackMenuAction {
  playNow,
  playNext,
  addToQueue,
  addToPlaylist,
  viewAlbum,
  viewArtist,
  information,
  toggleFavorite,
  lyrics,
  download,
  deleteDownload,
}

class TrackActionMenu extends StatelessWidget {
  const TrackActionMenu({
    required this.track,
    required this.isFavorite,
    required this.onPlayNow,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onViewAlbum,
    required this.onViewArtist,
    required this.onInformation,
    required this.onToggleFavorite,
    required this.onLyrics,
    this.showDownloadButton = true,
    this.onDownload,
    this.onDeleteDownload,
    super.key,
  }) : assert(showDownloadButton || onDownload != null);

  final Track track;
  final bool isFavorite;
  final VoidCallback onPlayNow;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback onAddToPlaylist;
  final VoidCallback onViewAlbum;
  final VoidCallback onViewArtist;
  final VoidCallback onInformation;
  final VoidCallback onToggleFavorite;
  final VoidCallback onLyrics;
  final bool showDownloadButton;
  final VoidCallback? onDownload;
  final VoidCallback? onDeleteDownload;

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    final l10n = context.l10n;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showDownloadButton) OfflineDownloadButton(track: track),
        PopupMenuButton<TrackMenuAction>(
          tooltip: labels.moreOptions,
          onSelected: (action) {
            switch (action) {
              case TrackMenuAction.playNow:
                onPlayNow();
              case TrackMenuAction.playNext:
                onPlayNext();
              case TrackMenuAction.addToQueue:
                onAddToQueue();
              case TrackMenuAction.addToPlaylist:
                onAddToPlaylist();
              case TrackMenuAction.viewAlbum:
                onViewAlbum();
              case TrackMenuAction.viewArtist:
                onViewArtist();
              case TrackMenuAction.information:
                onInformation();
              case TrackMenuAction.toggleFavorite:
                onToggleFavorite();
              case TrackMenuAction.lyrics:
                onLyrics();
              case TrackMenuAction.download:
                onDownload?.call();
              case TrackMenuAction.deleteDownload:
                onDeleteDownload?.call();
            }
          },
          itemBuilder: (context) => [
            _trackMenuItem(
              TrackMenuAction.playNow,
              Icons.play_circle_outline,
              labels.playNow,
            ),
            _trackMenuItem(
              TrackMenuAction.playNext,
              Icons.skip_next_outlined,
              labels.playNext,
            ),
            _trackMenuItem(
              TrackMenuAction.addToQueue,
              Icons.queue_music_outlined,
              labels.addToQueue,
            ),
            _trackMenuItem(
              TrackMenuAction.addToPlaylist,
              Icons.playlist_add_outlined,
              labels.addToPlaylist,
            ),
            _trackMenuItem(
              TrackMenuAction.viewAlbum,
              Icons.album_outlined,
              labels.viewAlbum,
              enabled: track.hasAlbumName,
            ),
            _trackMenuItem(
              TrackMenuAction.viewArtist,
              Icons.person_outline,
              labels.viewArtist,
              enabled: track.hasArtistName,
            ),
            _trackMenuItem(
              TrackMenuAction.information,
              Icons.info_outline,
              labels.songInformation,
            ),
            const PopupMenuDivider(),
            _trackMenuItem(
              TrackMenuAction.toggleFavorite,
              isFavorite ? Icons.favorite_border : Icons.favorite_outline,
              isFavorite ? labels.removeFavorite : labels.addFavorite,
            ),
            _trackMenuItem(
              TrackMenuAction.lyrics,
              Icons.lyrics_outlined,
              l10n.lyricsTooltip,
            ),
            if (!showDownloadButton)
              _trackMenuItem(
                TrackMenuAction.download,
                Icons.download_outlined,
                l10n.download,
              ),
            if (onDeleteDownload != null)
              _trackMenuItem(
                TrackMenuAction.deleteDownload,
                Icons.delete_outline,
                l10n.deleteDownloadedTrack,
              ),
          ],
        ),
      ],
    );
  }

  PopupMenuItem<TrackMenuAction> _trackMenuItem(
    TrackMenuAction action,
    IconData icon,
    String label, {
    bool enabled = true,
  }) {
    return PopupMenuItem(
      value: action,
      enabled: enabled,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class MediaLibraryStrings {
  const MediaLibraryStrings._(this._l10n);

  factory MediaLibraryStrings.of(BuildContext context) {
    return MediaLibraryStrings._(context.l10n);
  }

  final AppLocalizations _l10n;

  String get all => _l10n.all;
  String get allTracks => _l10n.allTracks;
  String get downloadedTracks => _l10n.downloadedTracks;
  String get albums => _l10n.albums;
  String get artists => _l10n.artists;
  String get playlists => _l10n.playlists;
  String get searchHint => _l10n.searchTracksArtistsAlbums;
  String get favorites => _l10n.favorites;
  String get sortTracks => _l10n.sortTracks;
  String get sortByTitle => _l10n.sortByTitle;
  String get sortByArtist => _l10n.sortByArtist;
  String get sortByAlbum => _l10n.sortByAlbum;
  String get sortAscending => _l10n.sortAscending;
  String get sortDescending => _l10n.sortDescending;
  String get exitSelection => _l10n.exitSelection;
  String get selectAll => _l10n.selectAll;
  String get downloadSelectedTracks => _l10n.downloadSelectedTracks;
  String get download => _l10n.download;
  String get noDownloadedTracks => _l10n.noDownloadedTracks;
  String get noDownloadedTracksMessage => _l10n.noDownloadedTracksMessage;
  String get deleteDownloadedTrack => _l10n.deleteDownloadedTrack;
  String get moreOptions => _l10n.moreOptions;
  String get playNow => _l10n.playNow;
  String get playNext => _l10n.playNext;
  String get addToQueue => _l10n.addToQueue;
  String get queue => _l10n.queue;
  String get clearQueue => _l10n.clearQueue;
  String get removeFromQueue => _l10n.removeFromQueue;
  String get emptyQueueMessage => _l10n.emptyQueueMessage;
  String get yourLibrary => _l10n.yourLibrary;
  String get favoritesFirst => _l10n.favoritesFirst;
  String get addToPlaylist => _l10n.addToPlaylist;
  String get viewAlbum => _l10n.viewAlbum;
  String get viewArtist => _l10n.viewArtist;
  String get songInformation => _l10n.songInformation;
  String get addFavorite => _l10n.addFavorite;
  String get removeFavorite => _l10n.removeFavorite;
  String get newPlaylist => _l10n.newPlaylist;
  String get playlistName => _l10n.playlistName;
  String get create => _l10n.create;
  String get noPlaylists => _l10n.noPlaylists;
  String get noPlaylistTracks => _l10n.noPlaylistTracks;
  String get noAlbums => _l10n.noAlbums;
  String get noArtists => _l10n.noArtists;
  String get noTracksInAlbum => _l10n.noTracksInAlbum;
  String get noTracksByArtist => _l10n.noTracksByArtist;
  String get noMatchingTracks => _l10n.noMatchingTracks;
  String get noFavorites => _l10n.noFavorites;
  String get noFavoritesMessage => _l10n.noFavoritesMessage;
  String get tryAnotherSearch => _l10n.tryAnotherSearch;
  String get playPlaylist => _l10n.playPlaylist;
  String get playAlbum => _l10n.playAlbum;
  String get playArtist => _l10n.playArtist;
  String get removeFromPlaylist => _l10n.removeFromPlaylist;
  String get deletePlaylist => _l10n.deletePlaylist;
  String get deletePlaylistPrompt => _l10n.deletePlaylistPrompt;
  String get cancel => _l10n.cancel;
  String get delete => _l10n.delete;
  String get unknownAlbum => _l10n.unknownAlbum;
  String get unknownArtist => _l10n.unknownArtist;
  String get title => _l10n.trackInfoTitle;
  String get artist => _l10n.trackInfoArtist;
  String get album => _l10n.trackInfoAlbum;
  String get genre => _l10n.trackInfoGenre;
  String get duration => _l10n.trackInfoDuration;
  String get identifier => _l10n.trackInfoIdentifier;
  String get queuedNext => _l10n.queuedNext;
  String get addedToQueue => _l10n.addedToQueue;
  String get alreadyPlaying => _l10n.alreadyPlaying;
  String get alreadyInQueue => _l10n.alreadyInQueue;
  String get playlistUpdateFailed => _l10n.playlistUpdateFailed;
  String get trackAddedToPlaylist => _l10n.trackAddedToPlaylist;
  String get trackAlreadyInPlaylist => _l10n.trackAlreadyInPlaylist;

  String selectedTracks(int count) => _l10n.selectedTracks(count);

  String selectionSummary(int total, int selected) =>
      _l10n.selectionSummary(total, selected);

  String batchOperationCompleted(int succeeded, int total) =>
      _l10n.batchOperationCompleted(succeeded, total);

  String batchDownloadQueued(int succeeded, int total) =>
      _l10n.batchDownloadQueued(succeeded, total);

  String batchSkipped(int count) => _l10n.batchSkipped(count);

  String batchFailed(int count) => _l10n.batchFailed(count);

  String trackCount(int count) => _l10n.trackCount(count);

  String albumCount(int count) => _l10n.albumCount(count);

  String queueSummary(int count) => _l10n.queueSummary(count);
}

class _ArtworkPlaceholder extends StatelessWidget {
  const _ArtworkPlaceholder({required this.track});

  final Track track;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final palette = [
      (colors.primaryContainer, colors.onPrimaryContainer),
      (colors.secondaryContainer, colors.onSecondaryContainer),
      (colors.tertiaryContainer, colors.onTertiaryContainer),
    ];
    final title = track.hasAlbumName
        ? track.album!.trim()
        : track.localizedTitle(context.l10n);
    final paletteIndex =
        title.codeUnits.fold<int>(0, (sum, codeUnit) => sum + codeUnit) %
            palette.length;
    final (background, foreground) = palette[paletteIndex];

    return DecoratedBox(
      decoration: BoxDecoration(color: background),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            right: -8,
            bottom: -10,
            child: Icon(
              Icons.album,
              size: 52,
              color: foreground.withValues(alpha: 0.24),
            ),
          ),
          Text(
            title.isEmpty ? '♪' : title[0].toUpperCase(),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
