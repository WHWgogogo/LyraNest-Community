import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../tracks/data/tracks_api.dart';
import '../../tracks/domain/track.dart';
import '../../tracks/domain/track_list.dart';
import '../../tracks/presentation/library_ui.dart';
import '../../tracks/presentation/track_workflow.dart';
import '../application/collections_controller.dart';
import '../domain/playlist.dart';

class CollectionsPage extends ConsumerWidget {
  const CollectionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final workflow = TrackWorkflow(context: context, ref: ref);

    return Scaffold(
      appBar: AppBar(
        title: Text(labels.playlists),
        actions: [
          IconButton(
            tooltip: labels.newPlaylist,
            onPressed: workflow.createPlaylist,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
      body: AsyncValueView<TrackList>(
        value: ref.watch(tracksProvider),
        data: (trackList) => PlaylistLibraryView(
          tracks: trackList.tracks,
          artworkBaseUrl: artworkBaseUrl,
        ),
      ),
    );
  }
}

class PlaylistLibraryView extends ConsumerWidget {
  const PlaylistLibraryView({
    required this.tracks,
    required this.artworkBaseUrl,
    this.showCreateAction = false,
    super.key,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;
  final bool showCreateAction;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final workflow = TrackWorkflow(context: context, ref: ref);
    final content = ref.watch(collectionsControllerProvider).when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => EmptyState(
            title: labels.playlists,
            message: labels.playlistUpdateFailed,
            icon: Icons.error_outline,
          ),
          data: (collections) => _PlaylistList(
            playlists: collections.playlists,
            tracks: tracks,
            artworkBaseUrl: artworkBaseUrl,
            labels: labels,
            onPlay: workflow.playTracks,
          ),
        );

    if (!showCreateAction) {
      return content;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  labels.playlists,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              FilledButton.tonalIcon(
                onPressed: workflow.createPlaylist,
                icon: const Icon(Icons.add),
                label: Text(labels.newPlaylist),
              ),
            ],
          ),
        ),
        Expanded(child: content),
      ],
    );
  }
}

class _PlaylistList extends StatelessWidget {
  const _PlaylistList({
    required this.playlists,
    required this.tracks,
    required this.artworkBaseUrl,
    required this.labels,
    required this.onPlay,
  });

  final List<Playlist> playlists;
  final List<Track> tracks;
  final String artworkBaseUrl;
  final MediaLibraryStrings labels;
  final Future<void> Function(List<Track> tracks) onPlay;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return EmptyState(
        title: labels.playlists,
        message: labels.noPlaylists,
        icon: Icons.queue_music_outlined,
      );
    }

    final tracksById = {for (final track in tracks) track.id: track};
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      itemCount: playlists.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final playlist = playlists[index];
        final playlistTracks = playlist.trackIds
            .map((trackId) => tracksById[trackId])
            .whereType<Track>()
            .toList(growable: false);
        return _PlaylistCard(
          playlist: playlist,
          tracks: playlistTracks,
          artworkBaseUrl: artworkBaseUrl,
          labels: labels,
          onTap: () {
            context.push('/collections/${Uri.encodeComponent(playlist.id)}');
          },
          onPlay: playlistTracks.isEmpty ? null : () => onPlay(playlistTracks),
        );
      },
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  const _PlaylistCard({
    required this.playlist,
    required this.tracks,
    required this.artworkBaseUrl,
    required this.labels,
    required this.onTap,
    required this.onPlay,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final String artworkBaseUrl;
  final MediaLibraryStrings labels;
  final VoidCallback onTap;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              _PlaylistArtwork(
                tracks: tracks,
                artworkBaseUrl: artworkBaseUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      playlist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      labels.trackCount(playlist.trackIds.length),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: labels.playPlaylist,
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({
    required this.tracks,
    required this.artworkBaseUrl,
  });

  final List<Track> tracks;
  final String artworkBaseUrl;

  @override
  Widget build(BuildContext context) {
    if (tracks.isNotEmpty) {
      return TrackArtwork(
        track: tracks.first,
        artworkBaseUrl: artworkBaseUrl,
      );
    }

    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: 58,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(
          Icons.queue_music_outlined,
          color: colors.onSecondaryContainer,
        ),
      ),
    );
  }
}
