import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../l10n/l10n.dart';
import '../../collections/application/collections_controller.dart';
import '../../collections/presentation/collections_page.dart';
import '../../offline/application/offline_downloads_controller.dart';
import '../../offline/domain/offline_download_task.dart';
import '../data/tracks_api.dart';
import '../domain/track.dart';
import '../domain/track_list.dart';
import 'library_group_pages.dart';
import 'library_ui.dart';
import 'track_batch_actions.dart';
import 'track_sorting.dart';
import 'track_workflow.dart';

class TracksPage extends ConsumerStatefulWidget {
  const TracksPage({
    this.initialSearchQuery,
    super.key,
  });

  final String? initialSearchQuery;

  @override
  ConsumerState<TracksPage> createState() => _TracksPageState();
}

class _TracksPageState extends ConsumerState<TracksPage> {
  late final TextEditingController _searchController;
  var _selectedSection = _LibrarySection.all;
  var _searchQuery = '';
  var _sortField = TrackSortField.title;
  var _sortDirection = TrackSortDirection.ascending;
  var _isSelectionMode = false;
  final Set<String> _selectedTrackIds = <String>{};

  @override
  void initState() {
    super.initState();
    _searchQuery = widget.initialSearchQuery?.trim() ?? '';
    _searchController = TextEditingController(text: _searchQuery);
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void didUpdateWidget(covariant TracksPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextQuery = widget.initialSearchQuery?.trim() ?? '';
    if (nextQuery == _searchController.text) {
      return;
    }
    _searchController.value = TextEditingValue(
      text: nextQuery,
      selection: TextSelection.collapsed(offset: nextQuery.length),
    );
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    final tracks = ref.watch(tracksProvider);
    final favoriteTrackIds = ref.watch(favoriteTrackIdsProvider);
    final offlineDownloads = ref.watch(offlineDownloadsProvider).valueOrNull;
    final artworkBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl ??
            ServerConfig.preferredDefaultBaseUrl;

    final trackList =
        tracks.valueOrNull ?? const TrackList(total: 0, tracks: <Track>[]);

    return _buildLibrary(
      trackList,
      labels,
      remoteTracks: tracks,
      favoriteTrackIds: favoriteTrackIds,
      downloadedTracks: _downloadedTracks(
        trackList.tracks,
        offlineDownloads?.tasks.values ?? const <OfflineDownloadTask>[],
      ),
      artworkBaseUrl: artworkBaseUrl,
    );
  }

  Widget _buildLibrary(
    TrackList trackList,
    MediaLibraryStrings labels, {
    required AsyncValue<TrackList> remoteTracks,
    required Set<String> favoriteTrackIds,
    required List<Track> downloadedTracks,
    required String artworkBaseUrl,
  }) {
    return Column(
      children: [
        _LibrarySectionTabs(
          selectedSection: _selectedSection,
          labels: labels,
          onSelected: (section) {
            if (_selectedSection == section) {
              return;
            }
            setState(() {
              _selectedSection = section;
              _clearSelection();
            });
          },
        ),
        if (_selectedSection.isTrackList) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SearchField(
              controller: _searchController,
              hintText: labels.searchHint,
              onClear: _searchQuery.isEmpty ? null : _searchController.clear,
            ),
          ),
        ],
        Expanded(
          child: KeyedSubtree(
            key: ValueKey(_selectedSection),
            child: switch (_selectedSection) {
              _LibrarySection.all ||
              _LibrarySection.favorites =>
                _buildRemoteTracksContent(
                  remoteTracks,
                  () => _buildTrackList(
                    trackList.tracks,
                    labels,
                    favoriteTrackIds: favoriteTrackIds,
                    artworkBaseUrl: artworkBaseUrl,
                  ),
                ),
              _LibrarySection.downloaded => _buildTrackList(
                  downloadedTracks,
                  labels,
                  favoriteTrackIds: favoriteTrackIds,
                  artworkBaseUrl: artworkBaseUrl,
                ),
              _LibrarySection.albums => _buildRemoteTracksContent(
                  remoteTracks,
                  () => AlbumLibraryView(
                    tracks: trackList.tracks,
                    artworkBaseUrl: artworkBaseUrl,
                  ),
                ),
              _LibrarySection.artists => _buildRemoteTracksContent(
                  remoteTracks,
                  () => ArtistLibraryView(
                    tracks: trackList.tracks,
                    artworkBaseUrl: artworkBaseUrl,
                  ),
                ),
              _LibrarySection.playlists => _buildRemoteTracksContent(
                  remoteTracks,
                  () => PlaylistLibraryView(
                    tracks: trackList.tracks,
                    artworkBaseUrl: artworkBaseUrl,
                    showCreateAction: true,
                  ),
                ),
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRemoteTracksContent(
    AsyncValue<TrackList> remoteTracks,
    Widget Function() content,
  ) {
    return remoteTracks.when(
      data: (_) => content(),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) => _RemoteTracksError(
        onRetry: () => ref.invalidate(tracksProvider),
      ),
    );
  }

  Widget _buildTrackList(
    List<Track> tracks,
    MediaLibraryStrings labels, {
    required Set<String> favoriteTrackIds,
    required String artworkBaseUrl,
  }) {
    final visibleTracks = tracks
        .where((track) => _matchesActiveFilters(track, favoriteTrackIds))
        .toList(growable: false);
    final hasSearchQuery = _searchQuery.trim().isNotEmpty;
    final favoritesOnly = _selectedSection == _LibrarySection.favorites;
    final isAllTracks = _selectedSection == _LibrarySection.all;
    final isDownloadedTracks = _selectedSection == _LibrarySection.downloaded;
    final workflow = TrackWorkflow(context: context, ref: ref);
    final displayTracks = sortTracks(visibleTracks, _sortField, _sortDirection);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(tracksProvider);
        await ref.read(tracksProvider.future);
      },
      child: Stack(
        children: [
          ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _sectionTitle(labels),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _selectionSummary(labels, displayTracks.length),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  if (!_isSelectionMode)
                    _SortControl(
                      field: _sortField,
                      direction: _sortDirection,
                      labels: labels,
                      onChanged: (field, direction) {
                        setState(() {
                          _sortField = field;
                          _sortDirection = direction;
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              if (displayTracks.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: EmptyState(
                    title: hasSearchQuery
                        ? labels.noMatchingTracks
                        : favoritesOnly
                            ? labels.noFavorites
                            : _selectedSection == _LibrarySection.downloaded
                                ? labels.noDownloadedTracks
                                : context.l10n.noTracksTitle,
                    message: hasSearchQuery
                        ? labels.tryAnotherSearch
                        : favoritesOnly
                            ? labels.noFavoritesMessage
                            : _selectedSection == _LibrarySection.downloaded
                                ? labels.noDownloadedTracksMessage
                                : context.l10n.noTracksMessage,
                    icon: hasSearchQuery
                        ? Icons.search_off_outlined
                        : favoritesOnly
                            ? Icons.favorite_border
                            : _selectedSection == _LibrarySection.downloaded
                                ? Icons.download_done_outlined
                                : Icons.music_note_outlined,
                  ),
                )
              else
                for (final (index, track) in displayTracks.indexed) ...[
                  TrackListCard(
                    track: track,
                    artworkBaseUrl: artworkBaseUrl,
                    selected:
                        isAllTracks && _selectedTrackIds.contains(track.id),
                    onLongPress:
                        isAllTracks ? () => _enterSelectionMode(track) : null,
                    onTap: () {
                      if (isAllTracks && _isSelectionMode) {
                        _toggleSelection(track);
                        return;
                      }
                      workflow.playTracks(displayTracks, initialIndex: index);
                    },
                    actions: isAllTracks && _isSelectionMode
                        ? [
                            Checkbox(
                              key: ValueKey('all_tracks_select_${track.id}'),
                              value: _selectedTrackIds.contains(track.id),
                              onChanged: (_) => _toggleSelection(track),
                            ),
                          ]
                        : isAllTracks
                            ? [
                                TrackActionMenu(
                                  track: track,
                                  isFavorite:
                                      favoriteTrackIds.contains(track.id),
                                  onPlayNow: () => workflow.playNow(track),
                                  onPlayNext: () => workflow.playNext(track),
                                  onAddToQueue: () =>
                                      workflow.addToQueue(track),
                                  onAddToPlaylist: () =>
                                      workflow.showPlaylistPicker(track),
                                  onViewAlbum: () => workflow.viewAlbum(track),
                                  onViewArtist: () =>
                                      workflow.viewArtist(track),
                                  onInformation: () =>
                                      workflow.showInformation(track),
                                  onToggleFavorite: () =>
                                      workflow.toggleFavorite(track),
                                  onLyrics: () => workflow.showLyrics(track),
                                  showDownloadButton: false,
                                  onDownload: () => _downloadSingle(track),
                                ),
                              ]
                            : [
                                IconButton(
                                  tooltip: labels.favorites,
                                  onPressed: () =>
                                      workflow.toggleFavorite(track),
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
                                  isFavorite:
                                      favoriteTrackIds.contains(track.id),
                                  onPlayNow: () => workflow.playNow(track),
                                  onPlayNext: () => workflow.playNext(track),
                                  onAddToQueue: () =>
                                      workflow.addToQueue(track),
                                  onAddToPlaylist: () =>
                                      workflow.showPlaylistPicker(track),
                                  onViewAlbum: () => workflow.viewAlbum(track),
                                  onViewArtist: () =>
                                      workflow.viewArtist(track),
                                  onInformation: () =>
                                      workflow.showInformation(track),
                                  onToggleFavorite: () =>
                                      workflow.toggleFavorite(track),
                                  onLyrics: () => workflow.showLyrics(track),
                                  onDeleteDownload: isDownloadedTracks
                                      ? () => _confirmDeleteDownload(track)
                                      : null,
                                ),
                              ],
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
          if (isAllTracks && _isSelectionMode)
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: _BatchActionBar(
                selectedCount: _selectedTrackIds.length,
                onAddToQueue: _batchAddToQueue,
                onAddToPlaylist: _batchAddToPlaylist,
                onDownload: _batchDownload,
                onSelectAll: displayTracks.isEmpty
                    ? null
                    : () => _selectAll(displayTracks),
                onClear: _exitSelectionMode,
              ),
            ),
        ],
      ),
    );
  }

  bool _matchesActiveFilters(
    Track track,
    Set<String> favoriteTrackIds,
  ) {
    if (_selectedSection == _LibrarySection.favorites &&
        !favoriteTrackIds.contains(track.id)) {
      return false;
    }

    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return true;
    }

    final searchText = [
      track.title,
      track.artist,
      track.album,
      ...track.genres,
    ].whereType<String>().join(' ').toLowerCase();
    return searchText.contains(query);
  }

  void _onSearchChanged() {
    setState(() {
      _searchQuery = _searchController.text;
    });
  }

  String _selectionSummary(MediaLibraryStrings labels, int total) {
    if (_isSelectionMode) {
      return labels.selectionSummary(total, _selectedTrackIds.length);
    }
    return labels.trackCount(total);
  }

  String _sectionTitle(MediaLibraryStrings labels) {
    return switch (_selectedSection) {
      _LibrarySection.all => labels.allTracks,
      _LibrarySection.favorites => labels.favorites,
      _LibrarySection.downloaded => labels.downloadedTracks,
      _LibrarySection.albums ||
      _LibrarySection.artists ||
      _LibrarySection.playlists =>
        labels.allTracks,
    };
  }

  void _enterSelectionMode(Track track) {
    setState(() {
      _isSelectionMode = true;
      _selectedTrackIds
        ..clear()
        ..add(track.id);
    });
  }

  void _toggleSelection(Track track) {
    setState(() {
      if (!_selectedTrackIds.add(track.id)) {
        _selectedTrackIds.remove(track.id);
      }
      if (_selectedTrackIds.isEmpty) {
        _isSelectionMode = false;
      }
    });
  }

  void _selectAll(Iterable<Track> tracks) {
    setState(() {
      _selectedTrackIds
        ..clear()
        ..addAll(tracks.map((track) => track.id));
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _clearSelection();
    });
  }

  void _clearSelection() {
    _isSelectionMode = false;
    _selectedTrackIds.clear();
  }

  Iterable<Track> _selectedTracks(List<Track> tracks) {
    if (_selectedTrackIds.isEmpty) {
      return const <Track>[];
    }
    return tracks.where((track) => _selectedTrackIds.contains(track.id));
  }

  List<Track> _visibleTracks(TrackList? trackList) {
    final favoriteTrackIds = ref.read(favoriteTrackIdsProvider);
    final all = trackList?.tracks ?? const <Track>[];
    return all
        .where((track) => _matchesActiveFilters(track, favoriteTrackIds))
        .toList(growable: false);
  }

  Future<void> _downloadSingle(Track track) async {
    final workflow = TrackWorkflow(context: context, ref: ref);
    await workflow.downloadTrack(track);
  }

  Future<void> _confirmDeleteDownload(Track track) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteDownloadedTrackTitle),
        content: Text(l10n.deleteDownloadedTrackPrompt(track.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }

    try {
      await ref.read(offlineDownloadsProvider.notifier).delete(track.id);
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.deleteDownloadedTrackFailed)),
        );
    }
  }

  List<Track> _sortedSelectedTracks() {
    return _selectedTracks(
      sortTracks(
        _visibleTracks(ref.read(tracksProvider).valueOrNull),
        _sortField,
        _sortDirection,
      ),
    ).toList(growable: false);
  }

  Future<void> _batchAddToQueue() async {
    final tracks = _sortedSelectedTracks();
    final workflow = TrackWorkflow(context: context, ref: ref);
    final result = await workflow.addTracksToQueue(tracks);
    if (!mounted) {
      return;
    }
    _showBatchResult(TrackWorkflow(context: context, ref: ref), result,
        total: tracks.length);
    _exitSelectionMode();
  }

  Future<void> _batchAddToPlaylist() async {
    final tracks = _sortedSelectedTracks();
    final workflow = TrackWorkflow(context: context, ref: ref);
    final result = await workflow.showPlaylistPickerForTracks(tracks);
    if (!mounted || result == null) {
      return;
    }
    _showBatchResult(workflow, result, total: tracks.length);
    _exitSelectionMode();
  }

  Future<void> _batchDownload() async {
    final tracks = _sortedSelectedTracks();
    if (tracks.isEmpty) {
      return;
    }

    final downloads = ref.read(offlineDownloadsProvider.notifier);
    final result = await runTrackBatchSequentially(
      tracks,
      (track) async {
        await downloads.downloadTrack(track);
        return true;
      },
    );
    if (!mounted) {
      return;
    }
    _showBatchResult(
      TrackWorkflow(context: context, ref: ref),
      result,
      total: tracks.length,
      download: true,
    );
    _exitSelectionMode();
  }

  void _showBatchResult(
    TrackWorkflow workflow,
    TrackBatchResult result, {
    required int total,
    bool download = false,
  }) {
    final labels = MediaLibraryStrings.of(context);
    final summary = download
        ? labels.batchDownloadQueued(result.succeeded, total)
        : labels.batchOperationCompleted(result.succeeded, total);
    final skipped =
        result.skipped > 0 ? labels.batchSkipped(result.skipped) : '';
    final failed = result.failed > 0 ? labels.batchFailed(result.failed) : '';
    workflow.showBatchMessage('$summary$skipped$failed');
  }

  List<Track> _downloadedTracks(
    List<Track> tracks,
    Iterable<OfflineDownloadTask> tasks,
  ) {
    final downloadedTasks = tasks
        .where((task) => task.status == OfflineDownloadStatus.completed)
        .toList(growable: false);
    final tracksById = {for (final track in tracks) track.id: track};

    return [
      for (final task in downloadedTasks)
        tracksById[task.trackId] ?? task.trackSnapshot.toTrack(task.trackId),
    ];
  }
}

enum _LibrarySection {
  all,
  favorites,
  downloaded,
  albums,
  artists,
  playlists;

  bool get isTrackList =>
      this == _LibrarySection.all ||
      this == _LibrarySection.favorites ||
      this == _LibrarySection.downloaded;
}

class _RemoteTracksError extends StatelessWidget {
  const _RemoteTracksError({required this.onRetry});

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
            const SizedBox(height: 16),
            Text(
              context.l10n.requestFailedTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
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

class _SortControl extends StatelessWidget {
  const _SortControl({
    required this.field,
    required this.direction,
    required this.labels,
    required this.onChanged,
  });

  final TrackSortField field;
  final TrackSortDirection direction;
  final MediaLibraryStrings labels;
  final void Function(TrackSortField field, TrackSortDirection direction)
      onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_TrackSortMenuOption>(
      key: const ValueKey('all_tracks_sort'),
      tooltip: labels.sortTracks,
      onSelected: (option) {
        onChanged(
          option.field ?? field,
          option.direction ?? direction,
        );
      },
      child: OutlinedButton.icon(
        onPressed: null,
        icon: Icon(
          direction == TrackSortDirection.ascending
              ? Icons.arrow_upward
              : Icons.arrow_downward,
          size: 18,
        ),
        label: Text('${labels.sortTracks}：${_fieldLabel(field)}'),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: const _TrackSortMenuOption(field: TrackSortField.title),
          child: _SortMenuItem(
            label: labels.sortByTitle,
            selected: field == TrackSortField.title,
          ),
        ),
        PopupMenuItem(
          value: const _TrackSortMenuOption(field: TrackSortField.artist),
          child: _SortMenuItem(
            label: labels.sortByArtist,
            selected: field == TrackSortField.artist,
          ),
        ),
        PopupMenuItem(
          value: const _TrackSortMenuOption(field: TrackSortField.album),
          child: _SortMenuItem(
            label: labels.sortByAlbum,
            selected: field == TrackSortField.album,
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: const _TrackSortMenuOption(
            direction: TrackSortDirection.ascending,
          ),
          child: _SortMenuItem(
            label: labels.sortAscending,
            selected: direction == TrackSortDirection.ascending,
          ),
        ),
        PopupMenuItem(
          value: const _TrackSortMenuOption(
            direction: TrackSortDirection.descending,
          ),
          child: _SortMenuItem(
            label: labels.sortDescending,
            selected: direction == TrackSortDirection.descending,
          ),
        ),
      ],
    );
  }

  String _fieldLabel(TrackSortField sortField) {
    return switch (sortField) {
      TrackSortField.title => labels.sortByTitle,
      TrackSortField.artist => labels.sortByArtist,
      TrackSortField.album => labels.sortByAlbum,
    };
  }
}

class _TrackSortMenuOption {
  const _TrackSortMenuOption({
    this.field,
    this.direction,
  });

  final TrackSortField? field;
  final TrackSortDirection? direction;
}

class _SortMenuItem extends StatelessWidget {
  const _SortMenuItem({
    required this.label,
    required this.selected,
  });

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        if (selected) const Icon(Icons.check, size: 18),
      ],
    );
  }
}

class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.selectedCount,
    required this.onAddToQueue,
    required this.onAddToPlaylist,
    required this.onDownload,
    required this.onSelectAll,
    required this.onClear,
  });

  final int selectedCount;
  final Future<void> Function() onAddToQueue;
  final Future<void> Function() onAddToPlaylist;
  final Future<void> Function() onDownload;
  final VoidCallback? onSelectAll;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final labels = MediaLibraryStrings.of(context);
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.secondaryContainer,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              key: const ValueKey('all_tracks_exit_selection'),
              tooltip: labels.exitSelection,
              onPressed: onClear,
              icon: const Icon(Icons.close),
            ),
            Expanded(
              child: Text(
                labels.selectedTracks(selectedCount),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              key: const ValueKey('all_tracks_select_all'),
              tooltip: labels.selectAll,
              onPressed: onSelectAll,
              icon: const Icon(Icons.select_all),
            ),
            IconButton(
              key: const ValueKey('all_tracks_add_to_queue'),
              tooltip: labels.addToQueue,
              onPressed: selectedCount == 0
                  ? null
                  : () {
                      unawaited(onAddToQueue());
                    },
              icon: const Icon(Icons.queue_music_outlined),
            ),
            IconButton(
              key: const ValueKey('all_tracks_add_to_playlist'),
              tooltip: labels.addToPlaylist,
              onPressed: selectedCount == 0
                  ? null
                  : () {
                      unawaited(onAddToPlaylist());
                    },
              icon: const Icon(Icons.playlist_add_outlined),
            ),
            IconButton(
              key: const ValueKey('all_tracks_download'),
              tooltip: labels.downloadSelectedTracks,
              onPressed: selectedCount == 0
                  ? null
                  : () {
                      unawaited(onDownload());
                    },
              icon: const Icon(Icons.download_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _LibrarySectionTabs extends StatelessWidget {
  const _LibrarySectionTabs({
    required this.selectedSection,
    required this.labels,
    required this.onSelected,
  });

  final _LibrarySection selectedSection;
  final MediaLibraryStrings labels;
  final ValueChanged<_LibrarySection> onSelected;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          for (final section in _LibrarySection.values) ...[
            ChoiceChip(
              selected: selectedSection == section,
              showCheckmark: false,
              avatar: Icon(_iconFor(section), size: 18),
              label: Text(_labelFor(section)),
              onSelected: (_) => onSelected(section),
            ),
            if (section != _LibrarySection.values.last)
              const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  String _labelFor(_LibrarySection section) {
    return switch (section) {
      _LibrarySection.all => labels.all,
      _LibrarySection.favorites => labels.favorites,
      _LibrarySection.downloaded => labels.downloadedTracks,
      _LibrarySection.albums => labels.albums,
      _LibrarySection.artists => labels.artists,
      _LibrarySection.playlists => labels.playlists,
    };
  }

  IconData _iconFor(_LibrarySection section) {
    return switch (section) {
      _LibrarySection.all => Icons.music_note_outlined,
      _LibrarySection.favorites => Icons.favorite_border,
      _LibrarySection.downloaded => Icons.download_done_outlined,
      _LibrarySection.albums => Icons.album_outlined,
      _LibrarySection.artists => Icons.person_outline,
      _LibrarySection.playlists => Icons.queue_music_outlined,
    };
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.hintText,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: onClear == null
              ? null
              : IconButton(
                  tooltip:
                      MaterialLocalizations.of(context).deleteButtonTooltip,
                  onPressed: onClear,
                  icon: const Icon(Icons.close),
                ),
          contentPadding: const EdgeInsets.symmetric(vertical: 15),
        ),
      ),
    );
  }
}
