import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

class PlaylistDetailPage extends ConsumerWidget {
  const PlaylistDetailPage({
    required this.playlistId,
    super.key,
  });

  final String playlistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    return ref.watch(collectionsControllerProvider).when(
          loading: () => Scaffold(
            appBar: AppBar(title: Text(labels.playlists)),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, stackTrace) => Scaffold(
            appBar: AppBar(title: Text(labels.playlists)),
            body: EmptyState(
              title: labels.playlists,
              message: labels.playlistUpdateFailed,
              icon: Icons.error_outline,
            ),
          ),
          data: (collections) {
            final playlist = collections.playlistById(playlistId);
            if (playlist == null) {
              return Scaffold(
                appBar: AppBar(title: Text(labels.playlists)),
                body: EmptyState(
                  title: labels.playlists,
                  message: labels.noPlaylists,
                  icon: Icons.queue_music_outlined,
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                title: Text(playlist.name),
                actions: [
                  IconButton(
                    tooltip: labels.deletePlaylist,
                    onPressed: () => _deletePlaylist(context, ref, playlist),
                    icon: const Icon(Icons.delete_outline),
                  ),
                ],
              ),
              body: AsyncValueView<TrackList>(
                value: ref.watch(tracksProvider),
                data: (trackList) => _PlaylistDetailBody(
                  playlist: playlist,
                  allTracks: trackList.tracks,
                  artworkBaseUrl: artworkBaseUrl,
                ),
              ),
            );
          },
        );
  }

  Future<void> _deletePlaylist(
    BuildContext context,
    WidgetRef ref,
    Playlist playlist,
  ) async {
    final labels = MediaLibraryStrings.of(context);
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(labels.deletePlaylist),
          content: Text(labels.deletePlaylistPrompt),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(labels.delete),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(collectionsControllerProvider.notifier)
          .deletePlaylist(playlist.id);
      if (context.mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(labels.playlistUpdateFailed)),
      );
    }
  }
}

class _PlaylistDetailBody extends ConsumerWidget {
  const _PlaylistDetailBody({
    required this.playlist,
    required this.allTracks,
    required this.artworkBaseUrl,
  });

  final Playlist playlist;
  final List<Track> allTracks;
  final String artworkBaseUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final tracksById = {for (final track in allTracks) track.id: track};
    final tracks = playlist.trackIds
        .map((trackId) => tracksById[trackId])
        .whereType<Track>()
        .toList(growable: false);
    final favoriteTrackIds = ref.watch(favoriteTrackIdsProvider);
    final workflow = TrackWorkflow(context: context, ref: ref);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _PlaylistHeader(
          playlist: playlist,
          tracks: tracks,
          artworkBaseUrl: artworkBaseUrl,
          onPlay: tracks.isEmpty ? null : () => workflow.playTracks(tracks),
        ),
        const SizedBox(height: 22),
        if (tracks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: EmptyState(
              title: playlist.name,
              message: labels.noPlaylistTracks,
              icon: Icons.queue_music_outlined,
            ),
          )
        else
          for (final (index, track) in tracks.indexed) ...[
            TrackListCard(
              track: track,
              artworkBaseUrl: artworkBaseUrl,
              onTap: () => workflow.playTracks(tracks, initialIndex: index),
              actions: [
                IconButton(
                  tooltip: labels.removeFromPlaylist,
                  onPressed: () => workflow.removeTrackFromPlaylist(
                    playlistId: playlist.id,
                    track: track,
                  ),
                  icon: const Icon(Icons.playlist_remove_outlined),
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
  }
}

class _PlaylistHeader extends StatelessWidget {
  const _PlaylistHeader({
    required this.playlist,
    required this.tracks,
    required this.artworkBaseUrl,
    required this.onPlay,
  });

  final Playlist playlist;
  final List<Track> tracks;
  final String artworkBaseUrl;
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: tracks.isEmpty
                  ? const _EmptyPlaylistArtwork(size: 156)
                  : TrackArtwork(
                      track: tracks.first,
                      artworkBaseUrl: artworkBaseUrl,
                      size: 156,
                    ),
            ),
            const SizedBox(height: 18),
            Text(
              playlist.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              labels.trackCount(playlist.trackIds.length),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onPlay,
                icon: const Icon(Icons.play_arrow),
                label: Text(labels.playPlaylist),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyPlaylistArtwork extends StatelessWidget {
  const _EmptyPlaylistArtwork({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.secondaryContainer,
          borderRadius: BorderRadius.circular(size * 0.24),
        ),
        child: Icon(
          Icons.queue_music_outlined,
          size: size * 0.42,
          color: colors.onSecondaryContainer,
        ),
      ),
    );
  }
}
