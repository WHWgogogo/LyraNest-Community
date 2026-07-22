import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../collections/application/collections_controller.dart';
import '../../collections/domain/playlist.dart';
import '../../offline/application/offline_downloads_controller.dart';
import '../../player/application/player_controller.dart';
import '../domain/track.dart';
import 'track_batch_actions.dart';
import 'library_ui.dart';

class TrackWorkflow {
  const TrackWorkflow({
    required this.context,
    required this.ref,
  });

  final BuildContext context;
  final WidgetRef ref;

  Future<void> playNow(Track track) async {
    await ref.read(playerControllerProvider.notifier).playNow(track);
    if (context.mounted) {
      context.push('/player');
    }
  }

  Future<void> playTracks(
    List<Track> tracks, {
    int initialIndex = 0,
  }) async {
    if (tracks.isEmpty) {
      return;
    }

    await ref.read(playerControllerProvider.notifier).setQueue(
          tracks,
          initialIndex: initialIndex,
        );
    if (context.mounted) {
      context.push('/player');
    }
  }

  Future<void> playNext(Track track) async {
    final controller = ref.read(playerControllerProvider.notifier);
    if (ref.read(playerControllerProvider).currentTrack == null) {
      await playNow(track);
      return;
    }
    final inserted = await controller.playNext(track);
    if (!context.mounted) {
      return;
    }
    if (!inserted) {
      _showMessage(MediaLibraryStrings.of(context).alreadyPlaying);
      return;
    }
    if (context.mounted) {
      _showMessage(MediaLibraryStrings.of(context).queuedNext);
    }
  }

  Future<void> addToQueue(Track track) async {
    final controller = ref.read(playerControllerProvider.notifier);
    if (ref.read(playerControllerProvider).currentTrack == null) {
      await playNow(track);
      return;
    }
    final inserted = await controller.addToQueue(track);
    if (!context.mounted) {
      return;
    }
    if (!inserted) {
      _showMessage(MediaLibraryStrings.of(context).alreadyInQueue);
      return;
    }
    if (context.mounted) {
      _showMessage(MediaLibraryStrings.of(context).addedToQueue);
    }
  }

  Future<TrackBatchResult> addTracksToQueue(Iterable<Track> tracks) {
    final controller = ref.read(playerControllerProvider.notifier);
    return runTrackBatchSequentially(tracks, controller.addToQueue);
  }

  Future<void> downloadTrack(Track track) async {
    try {
      await ref.read(offlineDownloadsProvider.notifier).downloadTrack(track);
    } catch (_) {
      _showMessage('Download failed.');
    }
  }

  Future<void> toggleFavorite(Track track) async {
    final labels = MediaLibraryStrings.of(context);
    final isFavorite = ref.read(isFavoriteTrackProvider(track.id));

    try {
      final collections = ref.read(collectionsControllerProvider.notifier);
      if (isFavorite) {
        await collections.removeFavoriteTrack(track.id);
      } else {
        await collections.addFavoriteTrack(track.id);
      }
    } catch (_) {
      _showMessage(labels.playlistUpdateFailed);
    }
  }

  Future<void> showPlaylistPicker(Track track) async {
    final labels = MediaLibraryStrings.of(context);
    final playlists = ref.read(playlistsProvider);
    var shouldCreatePlaylist = false;

    final selectedPlaylist = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  labels.addToPlaylist,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.add_circle_outline),
                title: Text(labels.newPlaylist),
                onTap: () {
                  shouldCreatePlaylist = true;
                  Navigator.of(sheetContext).pop();
                },
              ),
              if (playlists.isNotEmpty)
                for (final playlist in playlists)
                  ListTile(
                    leading: Icon(
                      playlist.trackIds.contains(track.id)
                          ? Icons.check_circle_outline
                          : Icons.queue_music_outlined,
                    ),
                    title: Text(playlist.name),
                    subtitle: Text(labels.trackCount(playlist.trackIds.length)),
                    onTap: () => Navigator.of(sheetContext).pop(playlist),
                  )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    labels.noPlaylists,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!context.mounted) {
      return;
    }
    if (shouldCreatePlaylist) {
      await _createPlaylistAndAdd(track);
      return;
    }
    if (selectedPlaylist != null) {
      await _addTrackToPlaylist(track, selectedPlaylist);
    }
  }

  Future<TrackBatchResult?> showPlaylistPickerForTracks(
    Iterable<Track> tracks,
  ) async {
    final selectedTracks = tracks.toList(growable: false);
    if (selectedTracks.isEmpty) {
      return const TrackBatchResult(
        attempted: 0,
        succeeded: 0,
        skipped: 0,
        failed: 0,
      );
    }

    final labels = MediaLibraryStrings.of(context);
    final playlists = ref.read(playlistsProvider);
    final selectedPlaylist = await showModalBottomSheet<Playlist>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.only(bottom: 16),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
                child: Text(
                  labels.addToPlaylist,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
              if (playlists.isNotEmpty)
                for (final playlist in playlists)
                  ListTile(
                    leading: const Icon(Icons.queue_music_outlined),
                    title: Text(playlist.name),
                    subtitle: Text(labels.trackCount(playlist.trackIds.length)),
                    onTap: () => Navigator.of(sheetContext).pop(playlist),
                  )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                  child: Text(
                    labels.noPlaylists,
                    style: Theme.of(sheetContext).textTheme.bodyMedium,
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!context.mounted || selectedPlaylist == null) {
      return null;
    }

    final collections = ref.read(collectionsControllerProvider.notifier);
    return runTrackBatchSequentially(
      selectedTracks,
      (track) => collections.addTrackToPlaylist(
        playlistId: selectedPlaylist.id,
        trackId: track.id,
      ),
    );
  }

  Future<void> createPlaylist() async {
    final playlistName = await _promptPlaylistName();
    if (playlistName == null || !context.mounted) {
      return;
    }

    try {
      final playlist = await ref
          .read(collectionsControllerProvider.notifier)
          .createPlaylist(playlistName);
      if (context.mounted) {
        context.push('/collections/${Uri.encodeComponent(playlist.id)}');
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showMessage(MediaLibraryStrings.of(context).playlistUpdateFailed);
    }
  }

  void viewAlbum(Track track) {
    final album = track.album?.trim();
    if (album?.isEmpty ?? true) {
      return;
    }
    context.push('/albums/${Uri.encodeComponent(album!)}');
  }

  void viewArtist(Track track) {
    final artist = track.artist?.trim();
    if (artist?.isEmpty ?? true) {
      return;
    }
    context.push('/artists/${Uri.encodeComponent(artist!)}');
  }

  void showInformation(Track track) {
    context.push(
      '/tracks/${Uri.encodeComponent(track.id)}/details',
      extra: track,
    );
  }

  void showLyrics(Track track) {
    context.push('/library-lyrics/${Uri.encodeComponent(track.id)}');
  }

  void scrapeMetadata(Track track) {
    context.push(
      '/tracks/${Uri.encodeComponent(track.id)}/scrape',
      extra: track,
    );
  }

  void showBatchMessage(String message) {
    _showMessage(message);
  }

  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required Track track,
  }) async {
    try {
      return await ref
          .read(collectionsControllerProvider.notifier)
          .removeTrackFromPlaylist(
            playlistId: playlistId,
            trackId: track.id,
          );
    } catch (_) {
      if (!context.mounted) {
        return false;
      }
      _showMessage(MediaLibraryStrings.of(context).playlistUpdateFailed);
      return false;
    }
  }

  Future<void> _createPlaylistAndAdd(Track track) async {
    final playlistName = await _promptPlaylistName();
    if (playlistName == null || !context.mounted) {
      return;
    }

    try {
      final collections = ref.read(collectionsControllerProvider.notifier);
      final playlist = await collections.createPlaylist(playlistName);
      await _addTrackToPlaylist(track, playlist);
      if (context.mounted) {
        context.push('/collections/${Uri.encodeComponent(playlist.id)}');
      }
    } catch (_) {
      if (!context.mounted) {
        return;
      }
      _showMessage(MediaLibraryStrings.of(context).playlistUpdateFailed);
    }
  }

  Future<void> _addTrackToPlaylist(Track track, Playlist playlist) async {
    final labels = MediaLibraryStrings.of(context);
    try {
      final added = await ref
          .read(collectionsControllerProvider.notifier)
          .addTrackToPlaylist(
            playlistId: playlist.id,
            trackId: track.id,
          );
      if (context.mounted) {
        _showMessage(
          added ? labels.trackAddedToPlaylist : labels.trackAlreadyInPlaylist,
        );
      }
    } catch (_) {
      _showMessage(labels.playlistUpdateFailed);
    }
  }

  Future<String?> _promptPlaylistName() async {
    final labels = MediaLibraryStrings.of(context);
    final nameController = TextEditingController();
    final playlistName = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(labels.newPlaylist),
          content: TextField(
            controller: nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.done,
            onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              labelText: labels.playlistName,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(labels.cancel),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(nameController.text);
              },
              child: Text(labels.create),
            ),
          ],
        );
      },
    );
    nameController.dispose();

    final normalizedName = playlistName?.trim();
    return normalizedName == null || normalizedName.isEmpty
        ? null
        : normalizedName;
  }

  void _showMessage(String message) {
    if (!context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
