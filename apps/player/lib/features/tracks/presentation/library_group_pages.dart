import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../collections/application/collections_controller.dart';
import '../data/tracks_api.dart';
import '../domain/track.dart';
import '../domain/track_list.dart';
import 'library_ui.dart';
import 'track_workflow.dart';

class AlbumsPage extends ConsumerWidget {
  const AlbumsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    return Scaffold(
      appBar: AppBar(title: Text(labels.albums)),
      body: AsyncValueView<TrackList>(
        value: ref.watch(tracksProvider),
        data: (trackList) => AlbumLibraryView(
          tracks: trackList.tracks,
          artworkBaseUrl: artworkBaseUrl,
        ),
      ),
    );
  }
}

class AlbumLibraryView extends StatelessWidget {
  const AlbumLibraryView({
    required this.tracks,
    required this.artworkBaseUrl,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    super.key,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    final albums = _groupTracks(
      tracks,
      (track) => track.album?.trim() ?? '',
    );

    if (albums.isEmpty) {
      return EmptyState(
        title: labels.albums,
        message: labels.noAlbums,
        icon: Icons.album_outlined,
      );
    }

    return ListView.separated(
      padding: padding,
      itemCount: albums.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final album = albums[index];
        final artists = _uniqueValues(
          album.tracks.map((track) => track.artist?.trim()),
        );
        return _GroupCard(
          icon: Icons.album_outlined,
          title: album.name,
          subtitle: [
            if (artists.isNotEmpty) artists.join(' · '),
            labels.trackCount(album.tracks.length),
          ].join(' · '),
          coverTrack: album.tracks.first,
          artworkBaseUrl: artworkBaseUrl,
          onTap: () => context.push(
            '/albums/${Uri.encodeComponent(album.name)}',
          ),
        );
      },
    );
  }
}

class ArtistsPage extends ConsumerWidget {
  const ArtistsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    return Scaffold(
      appBar: AppBar(title: Text(labels.artists)),
      body: AsyncValueView<TrackList>(
        value: ref.watch(tracksProvider),
        data: (trackList) => ArtistLibraryView(
          tracks: trackList.tracks,
          artworkBaseUrl: artworkBaseUrl,
        ),
      ),
    );
  }
}

class ArtistLibraryView extends StatelessWidget {
  const ArtistLibraryView({
    required this.tracks,
    required this.artworkBaseUrl,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    super.key,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    final artists = _groupTracks(
      tracks,
      (track) => track.artist?.trim() ?? '',
    );

    if (artists.isEmpty) {
      return EmptyState(
        title: labels.artists,
        message: labels.noArtists,
        icon: Icons.person_outline,
      );
    }

    return ListView.separated(
      padding: padding,
      itemCount: artists.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final artist = artists[index];
        final albumCount = _uniqueValues(
          artist.tracks.map((track) => track.album?.trim()),
        ).length;
        return _GroupCard(
          icon: Icons.person_outline,
          title: artist.name,
          subtitle: [
            labels.albumCount(albumCount),
            labels.trackCount(artist.tracks.length),
          ].join(' · '),
          coverTrack: artist.tracks.first,
          artworkBaseUrl: artworkBaseUrl,
          onTap: () => context.push(
            '/artists/${Uri.encodeComponent(artist.name)}',
          ),
        );
      },
    );
  }
}

class AlbumDetailPage extends StatelessWidget {
  const AlbumDetailPage({
    required this.albumName,
    super.key,
  });

  final String albumName;

  @override
  Widget build(BuildContext context) {
    return _TrackGroupDetailPage(
      groupName: albumName,
      groupType: _TrackGroupType.album,
    );
  }
}

class ArtistDetailPage extends StatelessWidget {
  const ArtistDetailPage({
    required this.artistName,
    super.key,
  });

  final String artistName;

  @override
  Widget build(BuildContext context) {
    return _TrackGroupDetailPage(
      groupName: artistName,
      groupType: _TrackGroupType.artist,
    );
  }
}

class _TrackGroupDetailPage extends ConsumerWidget {
  const _TrackGroupDetailPage({
    required this.groupName,
    required this.groupType,
  });

  final String groupName;
  final _TrackGroupType groupType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final favoriteTrackIds = ref.watch(favoriteTrackIdsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(groupName)),
      body: AsyncValueView<TrackList>(
        value: ref.watch(tracksProvider),
        data: (trackList) {
          final matchingTracks = trackList.tracks
              .where((track) => _matchesGroup(track))
              .toList(growable: false);
          if (matchingTracks.isEmpty) {
            return EmptyState(
              title: groupName,
              message: groupType == _TrackGroupType.album
                  ? labels.noTracksInAlbum
                  : labels.noTracksByArtist,
              icon: groupType == _TrackGroupType.album
                  ? Icons.album_outlined
                  : Icons.person_outline,
            );
          }

          final workflow = TrackWorkflow(context: context, ref: ref);
          final supportingValues = groupType == _TrackGroupType.album
              ? _uniqueValues(
                  matchingTracks.map((track) => track.artist?.trim()),
                ).join(' · ')
              : labels.albumCount(
                  _uniqueValues(
                    matchingTracks.map((track) => track.album?.trim()),
                  ).length,
                );

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _DetailHeader(
                track: matchingTracks.first,
                artworkBaseUrl: artworkBaseUrl,
                title: groupName,
                subtitle: [
                  if (supportingValues.isNotEmpty) supportingValues,
                  labels.trackCount(matchingTracks.length),
                ].join(' · '),
                actionLabel: groupType == _TrackGroupType.album
                    ? labels.playAlbum
                    : labels.playArtist,
                onPlay: () => workflow.playTracks(matchingTracks),
              ),
              const SizedBox(height: 22),
              for (final (index, track) in matchingTracks.indexed) ...[
                TrackListCard(
                  track: track,
                  artworkBaseUrl: artworkBaseUrl,
                  showAlbum: groupType == _TrackGroupType.artist,
                  onTap: () => workflow.playTracks(
                    matchingTracks,
                    initialIndex: index,
                  ),
                  actions: [
                    IconButton(
                      tooltip: labels.favorites,
                      onPressed: () => workflow.toggleFavorite(track),
                      icon: Icon(
                        favoriteTrackIds.contains(track.id)
                            ? Icons.favorite
                            : Icons.favorite_border,
                        color: favoriteTrackIds.contains(track.id)
                            ? Theme.of(context).colorScheme.primary
                            : null,
                      ),
                    ),
                    TrackActionMenu(
                      track: track,
                      isFavorite: favoriteTrackIds.contains(track.id),
                      onPlayNow: () => workflow.playNow(track),
                      onPlayNext: () => workflow.playNext(track),
                      onAddToQueue: () => workflow.addToQueue(track),
                      onAddToPlaylist: () => workflow.showPlaylistPicker(track),
                      onViewAlbum: () => workflow.viewAlbum(track),
                      onViewArtist: () => workflow.viewArtist(track),
                      onInformation: () => workflow.showInformation(track),
                      onToggleFavorite: () => workflow.toggleFavorite(track),
                      onLyrics: () => workflow.showLyrics(track),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ],
          );
        },
      ),
    );
  }

  bool _matchesGroup(Track track) {
    final value = switch (groupType) {
      _TrackGroupType.album => track.album,
      _TrackGroupType.artist => track.artist,
    };
    return _normalizedName(value) == _normalizedName(groupName);
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.coverTrack,
    required this.artworkBaseUrl,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Track coverTrack;
  final String artworkBaseUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              TrackArtwork(
                track: coverTrack,
                artworkBaseUrl: artworkBaseUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              Icon(icon, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailHeader extends StatelessWidget {
  const _DetailHeader({
    required this.track,
    required this.artworkBaseUrl,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onPlay,
  });

  final Track track;
  final String artworkBaseUrl;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: TrackArtwork(
                track: track,
                artworkBaseUrl: artworkBaseUrl,
                size: 156,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: Text(actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TrackGroupType {
  album,
  artist,
}

class _TrackGroup {
  const _TrackGroup({
    required this.name,
    required this.tracks,
  });

  final String name;
  final List<Track> tracks;
}

List<_TrackGroup> _groupTracks(
  List<Track> tracks,
  String Function(Track track) groupName,
) {
  final groups = <String, List<Track>>{};
  final displayNames = <String, String>{};

  for (final track in tracks) {
    final name = groupName(track).trim();
    if (name.isEmpty) {
      continue;
    }
    final key = _normalizedName(name);
    groups.putIfAbsent(key, () => []).add(track);
    displayNames.putIfAbsent(key, () => name);
  }

  return groups.entries
      .map(
        (entry) => _TrackGroup(
          name: displayNames[entry.key]!,
          tracks: List.unmodifiable(entry.value),
        ),
      )
      .toList()
    ..sort(
      (first, second) => first.name.toLowerCase().compareTo(
            second.name.toLowerCase(),
          ),
    );
}

List<String> _uniqueValues(Iterable<String?> values) {
  final seen = <String>{};
  final result = <String>[];
  for (final value in values) {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty || !seen.add(_normalizedName(trimmed))) {
      continue;
    }
    result.add(trimmed);
  }
  return result;
}

String _normalizedName(String? value) => (value ?? '').trim().toLowerCase();
