import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../l10n/l10n.dart';
import '../../collections/application/collections_controller.dart';
import '../../tracks/data/tracks_api.dart';
import '../../tracks/domain/track.dart';
import '../../tracks/presentation/library_ui.dart' as media_ui;
import '../application/player_controller.dart';
import '../domain/playback_state.dart';
import 'track_artwork.dart';

class QueuePanel extends ConsumerWidget {
  const QueuePanel({
    this.compact = false,
    this.onClose,
    super.key,
  });

  final bool compact;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playback = ref.watch(playerControllerProvider);
    final controller = ref.read(playerControllerProvider.notifier);
    final serverBaseUrl =
        ref.watch(serverConfigControllerProvider).valueOrNull?.baseUrl;

    return _QueuePanelBody(
      playback: playback,
      controller: controller,
      serverBaseUrl: serverBaseUrl ?? ServerConfig.preferredDefaultBaseUrl,
      compact: compact,
      onClose: onClose,
    );
  }
}

class _QueuePanelBody extends StatefulWidget {
  const _QueuePanelBody({
    required this.playback,
    required this.controller,
    required this.serverBaseUrl,
    required this.compact,
    required this.onClose,
  });

  final PlaybackState playback;
  final PlayerController controller;
  final String serverBaseUrl;
  final bool compact;
  final VoidCallback? onClose;

  @override
  State<_QueuePanelBody> createState() => _QueuePanelBodyState();
}

class _QueuePanelBodyState extends State<_QueuePanelBody> {
  final ScrollController _scrollController = ScrollController();
  bool _hasAutoLocatedCurrent = false;
  bool _autoLocateScheduled = false;

  static const Duration _scrollDuration = Duration(milliseconds: 240);
  static const Curve _scrollCurve = Curves.easeOutCubic;
  static const double _queueItemExtent = 62;

  @override
  void initState() {
    super.initState();
    _scheduleInitialCurrentTrackReveal();
  }

  @override
  void didUpdateWidget(covariant _QueuePanelBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleInitialCurrentTrackReveal();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final controller = widget.controller;
    final currentIndex = _currentQueueIndex(playback);
    final hasCurrent = currentIndex >= 0;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE9141725),
        borderRadius: BorderRadius.circular(widget.compact ? 28 : 30),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          widget.compact ? 16 : 18,
          widget.compact ? 14 : 18,
          widget.compact ? 10 : 12,
          widget.compact ? 10 : 12,
        ),
        child: Column(
          children: [
            _QueueHeader(
              count: playback.queue.length,
              hasCurrent: hasCurrent,
              onLocateCurrent: hasCurrent ? _scrollToCurrentIndex : null,
              onAdd: () => _showAddTracksSheet(context),
              onClear: playback.queue.isEmpty
                  ? null
                  : () => unawaited(controller.clear()),
              onClose: widget.onClose,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: playback.queue.isEmpty
                  ? const _EmptyQueue()
                  : ReorderableListView.builder(
                      scrollController: _scrollController,
                      buildDefaultDragHandles: false,
                      itemExtent: _queueItemExtent,
                      padding: const EdgeInsets.only(bottom: 6),
                      itemCount: playback.queue.length,
                      onReorderItem: (oldIndex, newIndex) {
                        _reorderQueue(
                          controller,
                          playback,
                          oldIndex,
                          newIndex,
                        );
                      },
                      itemBuilder: (context, index) {
                        final track = playback.queue[index];
                        final active = index == currentIndex;
                        return _QueueTrackTile(
                          key: ValueKey('queue-${track.id}-$index'),
                          track: track,
                          index: index,
                          isActive: active,
                          isPlaying: active && playback.isPlaying,
                          artworkUrl: buildArtworkUrl(
                            widget.serverBaseUrl,
                            track.id,
                          ),
                          onTap: () => unawaited(
                            controller.selectQueueIndex(index),
                          ),
                          onRemove: () => _removeFromQueue(
                            controller,
                            playback,
                            index,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _scrollToCurrentIndex() {
    final index = _currentQueueIndex(widget.playback);
    if (index < 0) {
      return;
    }
    _revealCurrentTrack(index);
  }

  void _scheduleInitialCurrentTrackReveal() {
    if (_hasAutoLocatedCurrent || _autoLocateScheduled) {
      return;
    }
    final index = _currentQueueIndex(widget.playback);
    if (index < 0) {
      return;
    }
    _autoLocateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoLocateScheduled = false;
      if (!mounted || _hasAutoLocatedCurrent) {
        return;
      }
      final currentIndex = _currentQueueIndex(widget.playback);
      if (currentIndex < 0 || !_scrollController.hasClients) {
        _scheduleInitialCurrentTrackReveal();
        return;
      }
      _hasAutoLocatedCurrent = true;
      _revealCurrentTrack(currentIndex, animate: false);
    });
  }

  void _revealCurrentTrack(int index, {bool animate = true}) {
    if (!mounted) {
      return;
    }
    if (!_scrollController.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _revealCurrentTrack(index);
        }
      });
      return;
    }

    final position = _scrollController.position;
    final targetOffset = (index * _queueItemExtent +
            _queueItemExtent / 2 -
            position.viewportDimension * .42)
        .clamp(0.0, position.maxScrollExtent)
        .toDouble();
    if (animate) {
      unawaited(
        _scrollController.animateTo(
          targetOffset,
          duration: _scrollDuration,
          curve: _scrollCurve,
        ),
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  int _currentQueueIndex(PlaybackState playback) {
    final currentTrack = playback.currentTrack;
    if (currentTrack == null) {
      return -1;
    }

    final currentIndex = playback.currentIndex;
    if (currentIndex >= 0 &&
        currentIndex < playback.queue.length &&
        playback.queue[currentIndex].id == currentTrack.id) {
      return currentIndex;
    }

    return playback.queue.indexWhere((track) => track.id == currentTrack.id);
  }

  void _showAddTracksSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const _QueueAddSheet(),
    );
  }

  void _reorderQueue(
    PlayerController controller,
    PlaybackState playback,
    int oldIndex,
    int newIndex,
  ) {
    if (oldIndex == newIndex) {
      return;
    }
    unawaited(controller.moveQueueItem(oldIndex, newIndex));
  }

  void _removeFromQueue(
    PlayerController controller,
    PlaybackState playback,
    int index,
  ) {
    final queue = List<Track>.of(playback.queue)..removeAt(index);
    if (queue.isEmpty) {
      unawaited(controller.clear());
      return;
    }

    final activeTrackId = playback.currentTrack?.id;
    var activeIndex = activeTrackId == null
        ? 0
        : queue.indexWhere((track) => track.id == activeTrackId);
    if (activeIndex < 0) {
      activeIndex = index.clamp(0, queue.length - 1).toInt();
    }

    unawaited(
      controller.setQueue(
        queue,
        initialIndex: activeIndex,
        autoplay: playback.isPlaying,
      ),
    );
  }
}

class _QueueHeader extends StatelessWidget {
  const _QueueHeader({
    required this.count,
    required this.hasCurrent,
    required this.onLocateCurrent,
    required this.onAdd,
    required this.onClear,
    required this.onClose,
  });

  final int count;
  final bool hasCurrent;
  final VoidCallback? onLocateCurrent;
  final VoidCallback onAdd;
  final VoidCallback? onClear;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final labels = media_ui.MediaLibraryStrings.of(context);
    final subtitleStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          color: Colors.white.withValues(alpha: .48),
        );

    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF8F75F6).withValues(alpha: .18),
            borderRadius: BorderRadius.circular(14),
          ),
          child:
              const Icon(Icons.queue_music_rounded, color: Color(0xFFC8BAFF)),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                labels.queue,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(labels.queueSummary(count), style: subtitleStyle),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('queue-locate-current'),
          tooltip: context.l10n.nowPlaying,
          onPressed: hasCurrent ? onLocateCurrent : null,
          icon: const Icon(Icons.my_location_rounded),
        ),
        IconButton(
          key: const ValueKey('queue-add-tracks'),
          tooltip: labels.addToQueue,
          onPressed: onAdd,
          icon: const Icon(Icons.add_rounded),
        ),
        if (onClear != null)
          IconButton(
            tooltip: labels.clearQueue,
            onPressed: onClear,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
        if (onClose != null)
          IconButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            onPressed: onClose,
            icon: const Icon(Icons.close_rounded),
          ),
      ],
    );
  }
}

class _QueueTrackTile extends StatelessWidget {
  const _QueueTrackTile({
    required super.key,
    required this.track,
    required this.index,
    required this.isActive,
    required this.isPlaying,
    required this.artworkUrl,
    required this.onTap,
    required this.onRemove,
  });

  final Track track;
  final int index;
  final bool isActive;
  final bool isPlaying;
  final String artworkUrl;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final activeColor = const Color(0xFFC8BAFF);
    final labels = media_ui.MediaLibraryStrings.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: isActive
            ? const Color(0xFF9178F5).withValues(alpha: .16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 4, 7),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  child: isActive
                      ? Icon(
                          isPlaying
                              ? Icons.graphic_eq_rounded
                              : Icons.pause_circle_outline_rounded,
                          size: 18,
                          color: activeColor,
                        )
                      : Text(
                          '${index + 1}',
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: .42),
                                  ),
                        ),
                ),
                const SizedBox(width: 7),
                SizedBox(
                  width: 42,
                  height: 42,
                  child: TrackArtwork(
                    artworkUrl: artworkUrl,
                    identity: track.id,
                    title: track.title,
                    borderRadius: 12,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: isActive ? activeColor : Colors.white,
                              fontWeight:
                                  isActive ? FontWeight.w700 : FontWeight.w600,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.artist?.trim().isNotEmpty == true
                            ? track.artist!
                            : labels.unknownArtist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.white.withValues(alpha: .48),
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: labels.removeFromQueue,
                  visualDensity: VisualDensity.compact,
                  onPressed: onRemove,
                  icon: Icon(
                    Icons.remove_circle_outline_rounded,
                    size: 19,
                    color: Colors.white.withValues(alpha: .5),
                  ),
                ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      Icons.drag_handle_rounded,
                      color: Colors.white.withValues(alpha: .32),
                    ),
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

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue();

  @override
  Widget build(BuildContext context) {
    final labels = media_ui.MediaLibraryStrings.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.queue_music_outlined,
            size: 42,
            color: Colors.white.withValues(alpha: .34),
          ),
          const SizedBox(height: 10),
          Text(
            labels.emptyQueueMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .5),
                ),
          ),
        ],
      ),
    );
  }
}

class _QueueAddSheet extends ConsumerStatefulWidget {
  const _QueueAddSheet();

  @override
  ConsumerState<_QueueAddSheet> createState() => _QueueAddSheetState();
}

class _QueueAddSheetState extends ConsumerState<_QueueAddSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
    });
  }

  void _clearSearch() {
    _searchController.clear();
    _onSearchChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final labels = media_ui.MediaLibraryStrings.of(context);
    final playback = ref.watch(playerControllerProvider);
    final tracks = ref.watch(tracksProvider).valueOrNull?.tracks ?? const [];
    final favoriteIds = ref.watch(favoriteTrackIdsProvider);
    final queuedIds = playback.queue.map((track) => track.id).toSet();
    final candidates = tracks
        .where((track) => !queuedIds.contains(track.id))
        .toList(growable: false)
      ..sort((left, right) {
        final leftFavorite = favoriteIds.contains(left.id);
        final rightFavorite = favoriteIds.contains(right.id);
        if (leftFavorite == rightFavorite) {
          return left.title.compareTo(right.title);
        }
        return leftFavorite ? -1 : 1;
      });

    final normalizedQuery = _query.trim().toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? candidates
        : candidates
            .where((track) => _trackMatches(track, normalizedQuery))
            .toList(growable: false);

    return SafeArea(
      top: false,
      child: Container(
        height: MediaQuery.sizeOf(context).height * .72,
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: const Color(0xFF171A29),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.white.withValues(alpha: .1)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 34,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .22),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          labels.addToQueue,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          favoriteIds.isEmpty
                              ? labels.yourLibrary
                              : labels.favoritesFirst,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: .48),
                                  ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).closeButtonTooltip,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
            _QueueSearchField(
              controller: _searchController,
              hintText: labels.searchHint,
              onChanged: _onSearchChanged,
              onClear: _query.isEmpty ? null : _clearSearch,
            ),
            Expanded(
              child: candidates.isEmpty
                  ? const _EmptyQueue()
                  : filtered.isEmpty
                      ? _QueueNoMatches(message: labels.noMatchingTracks)
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(12, 4, 12, 18),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 4),
                          itemBuilder: (context, index) {
                            final track = filtered[index];
                            final isFavorite = favoriteIds.contains(track.id);
                            return Material(
                              color: Colors.white.withValues(alpha: .035),
                              borderRadius: BorderRadius.circular(18),
                              child: ListTile(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                leading: Icon(
                                  isFavorite
                                      ? Icons.favorite_rounded
                                      : Icons.music_note_rounded,
                                  color: isFavorite
                                      ? const Color(0xFFFF91B6)
                                      : const Color(0xFFC8BAFF),
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  track.artist?.trim().isNotEmpty == true
                                      ? track.artist!
                                      : labels.unknownArtist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                trailing: const Icon(
                                    Icons.add_circle_outline_rounded),
                                onTap: () => _appendTrack(
                                  context,
                                  playback,
                                  track,
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  bool _trackMatches(Track track, String query) {
    if (track.title.toLowerCase().contains(query)) {
      return true;
    }
    final artist = track.artist;
    if (artist != null && artist.toLowerCase().contains(query)) {
      return true;
    }
    final album = track.album;
    if (album != null && album.toLowerCase().contains(query)) {
      return true;
    }
    for (final genre in track.genres) {
      if (genre.toLowerCase().contains(query)) {
        return true;
      }
    }
    return false;
  }

  Future<void> _appendTrack(
    BuildContext context,
    PlaybackState playback,
    Track track,
  ) async {
    final queue = List<Track>.of(playback.queue)..add(track);
    final initialIndex = playback.currentIndex < 0 ? 0 : playback.currentIndex;
    await ref.read(playerControllerProvider.notifier).setQueue(
          queue,
          initialIndex: initialIndex,
          autoplay: playback.isPlaying,
        );
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _QueueSearchField extends StatelessWidget {
  const _QueueSearchField({
    required this.controller,
    required this.hintText,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(16),
        ),
        child: TextField(
          key: const ValueKey('queue-add-search'),
          controller: controller,
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: hintText,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            suffixIcon: onClear == null
                ? null
                : IconButton(
                    tooltip:
                        MaterialLocalizations.of(context).deleteButtonTooltip,
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 20),
                  ),
            contentPadding: const EdgeInsets.symmetric(vertical: 14),
            isDense: true,
          ),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _QueueNoMatches extends StatelessWidget {
  const _QueueNoMatches({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: .5),
              ),
        ),
      ),
    );
  }
}
