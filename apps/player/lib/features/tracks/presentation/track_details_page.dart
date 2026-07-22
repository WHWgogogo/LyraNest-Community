import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/l10n.dart';
import '../../collections/application/collections_controller.dart';
import '../data/tracks_api.dart';
import '../domain/track.dart';
import '../domain/track_list.dart';
import 'library_ui.dart';
import 'track_workflow.dart';

class TrackDetailsPage extends ConsumerWidget {
  const TrackDetailsPage({
    required this.trackId,
    this.track,
    super.key,
  });

  final String trackId;
  final Track? track;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = MediaLibraryStrings.of(context);
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;
    final favoriteTrackIds = ref.watch(favoriteTrackIdsProvider);

    return Scaffold(
      appBar: AppBar(title: Text(labels.songInformation)),
      body: AsyncValueView<TrackList>(
        value: ref.watch(tracksProvider),
        data: (trackList) {
          final resolvedTrack = track ?? _trackById(trackList.tracks);
          if (resolvedTrack == null) {
            return EmptyState(
              title: labels.songInformation,
              message: context.l10n.noTracksMessage,
              icon: Icons.music_off_outlined,
            );
          }

          final workflow = TrackWorkflow(context: context, ref: ref);
          final isFavorite = favoriteTrackIds.contains(resolvedTrack.id);
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: TrackArtwork(
                          track: resolvedTrack,
                          artworkBaseUrl: artworkBaseUrl,
                          size: 208,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        resolvedTrack.localizedTitle(context.l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        resolvedTrack.localizedArtist(context.l10n),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (resolvedTrack.hasAlbumName) ...[
                        const SizedBox(height: 3),
                        Text(
                          resolvedTrack.album!.trim(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => workflow.playNow(resolvedTrack),
                          icon: const Icon(Icons.play_arrow),
                          label: Text(labels.playNow),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () => workflow.playNext(resolvedTrack),
                            icon: const Icon(Icons.skip_next_outlined),
                            label: Text(labels.playNext),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => workflow.addToQueue(resolvedTrack),
                            icon: const Icon(Icons.queue_music_outlined),
                            label: Text(labels.addToQueue),
                          ),
                          OutlinedButton.icon(
                            onPressed: () =>
                                workflow.showPlaylistPicker(resolvedTrack),
                            icon: const Icon(Icons.playlist_add_outlined),
                            label: Text(labels.addToPlaylist),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Column(
                  children: [
                    _InformationRow(
                      icon: Icons.music_note_outlined,
                      label: labels.title,
                      value: resolvedTrack.localizedTitle(context.l10n),
                    ),
                    _InformationRow(
                      icon: Icons.person_outline,
                      label: labels.artist,
                      value: resolvedTrack.localizedArtist(context.l10n),
                      onTap: resolvedTrack.hasArtistName
                          ? () => workflow.viewArtist(resolvedTrack)
                          : null,
                    ),
                    _InformationRow(
                      icon: Icons.album_outlined,
                      label: labels.album,
                      value: resolvedTrack.hasAlbumName
                          ? resolvedTrack.album!.trim()
                          : labels.unknownAlbum,
                      onTap: resolvedTrack.hasAlbumName
                          ? () => workflow.viewAlbum(resolvedTrack)
                          : null,
                    ),
                    _InformationRow(
                      icon: Icons.category_outlined,
                      label: labels.genre,
                      value: resolvedTrack.genres.isEmpty
                          ? '-'
                          : resolvedTrack.genres.join(' · '),
                    ),
                    _InformationRow(
                      icon: Icons.schedule_outlined,
                      label: labels.duration,
                      value: _durationLabel(resolvedTrack.durationSeconds),
                    ),
                    _InformationRow(
                      icon: Icons.tag_outlined,
                      label: labels.identifier,
                      value: resolvedTrack.id,
                      isLast: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => workflow.toggleFavorite(resolvedTrack),
                      icon: Icon(
                        isFavorite ? Icons.favorite : Icons.favorite_border,
                      ),
                      label: Text(
                        isFavorite ? labels.removeFavorite : labels.addFavorite,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TrackActionMenu(
                    track: resolvedTrack,
                    isFavorite: isFavorite,
                    onPlayNow: () => workflow.playNow(resolvedTrack),
                    onPlayNext: () => workflow.playNext(resolvedTrack),
                    onAddToQueue: () => workflow.addToQueue(resolvedTrack),
                    onAddToPlaylist: () =>
                        workflow.showPlaylistPicker(resolvedTrack),
                    onViewAlbum: () => workflow.viewAlbum(resolvedTrack),
                    onViewArtist: () => workflow.viewArtist(resolvedTrack),
                    onInformation: () {},
                    onToggleFavorite: () =>
                        workflow.toggleFavorite(resolvedTrack),
                    onLyrics: () => workflow.showLyrics(resolvedTrack),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _durationLabel(int? totalSeconds) {
    final formatted = formatTrackDuration(totalSeconds);
    return formatted.isEmpty ? '-' : formatted;
  }

  Track? _trackById(List<Track> tracks) {
    for (final track in tracks) {
      if (track.id == trackId) {
        return track;
      }
    }
    return null;
  }
}

class _InformationRow extends StatelessWidget {
  const _InformationRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
    this.isLast = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final content = ListTile(
      leading: Icon(icon),
      title: Text(label),
      subtitle: Text(value),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );

    return Column(
      children: [
        content,
        if (!isLast)
          Divider(
            height: 1,
            indent: 72,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
      ],
    );
  }
}
