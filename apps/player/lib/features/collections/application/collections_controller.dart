import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_session.dart';
import '../data/collections_api.dart';
import '../data/collections_repository.dart';
import '../domain/collections_outbox_item.dart';
import '../domain/collections_scope.dart';
import '../domain/collections_snapshot.dart';
import '../domain/playlist.dart';

final collectionsControllerProvider =
    AsyncNotifierProvider<CollectionsController, CollectionsState>(
  CollectionsController.new,
);

final favoriteTrackIdsProvider = Provider<Set<String>>((ref) {
  return ref
          .watch(collectionsControllerProvider)
          .valueOrNull
          ?.favoriteTrackIds ??
      const <String>{};
});

final playlistsProvider = Provider<List<Playlist>>((ref) {
  return ref.watch(collectionsControllerProvider).valueOrNull?.playlists ??
      const <Playlist>[];
});

final playlistByIdProvider =
    Provider.family<Playlist?, String>((ref, playlistId) {
  final normalizedPlaylistId = playlistId.trim();
  for (final playlist in ref.watch(playlistsProvider)) {
    if (playlist.id == normalizedPlaylistId) {
      return playlist;
    }
  }
  return null;
});

final playlistTrackIdsProvider = Provider.family<Set<String>, String>(
  (ref, playlistId) {
    return Set.unmodifiable(
      ref.watch(playlistByIdProvider(playlistId))?.trackIds ?? const <String>[],
    );
  },
);

final isFavoriteTrackProvider = Provider.family<bool, String>((ref, trackId) {
  return ref.watch(favoriteTrackIdsProvider).contains(trackId.trim());
});

@immutable
class CollectionsState {
  CollectionsState({
    Set<String> favoriteTrackIds = const <String>{},
    List<Playlist> playlists = const <Playlist>[],
    this.revision,
    this.pendingOutboxCount = 0,
  })  : favoriteTrackIds = Set.unmodifiable(favoriteTrackIds),
        playlists = List.unmodifiable(playlists);

  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;
  final int? revision;
  final int pendingOutboxCount;

  bool isFavorite(String trackId) {
    return favoriteTrackIds.contains(trackId.trim());
  }

  Playlist? playlistById(String playlistId) {
    final normalizedPlaylistId = playlistId.trim();
    for (final playlist in playlists) {
      if (playlist.id == normalizedPlaylistId) {
        return playlist;
      }
    }
    return null;
  }

  Set<String> trackIdsForPlaylist(String playlistId) {
    return Set.unmodifiable(playlistById(playlistId)?.trackIds ?? const []);
  }
}

class CollectionsController extends AsyncNotifier<CollectionsState>
    with WidgetsBindingObserver {
  Future<void> _operationTail = Future.value();
  CollectionsScope _activeScope = const CollectionsScope.local();
  bool _observingLifecycle = false;

  @override
  Future<CollectionsState> build() async {
    _observeLifecycle();
    ref.listen(authControllerProvider, (previous, next) {
      _switchToSession(next.valueOrNull?.session);
    });

    _activeScope =
        _scopeFor(ref.read(authControllerProvider).valueOrNull?.session);
    final initialState = await _loadState(_activeScope);
    if (_activeScope.isRemote) {
      _scheduleSync(_activeScope);
    }
    return initialState;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeScope.isRemote) {
      _scheduleSync(_activeScope);
    }
  }

  bool isFavorite(String trackId) {
    return state.valueOrNull?.isFavorite(trackId) ?? false;
  }

  Playlist? getPlaylist(String playlistId) {
    return state.valueOrNull?.playlistById(playlistId);
  }

  Set<String> getPlaylistTrackIds(String playlistId) {
    return state.valueOrNull?.trackIdsForPlaylist(playlistId) ??
        const <String>{};
  }

  Future<void> sync() {
    final scope = _activeScope;
    return _enqueue(() => _syncScope(scope));
  }

  Future<void> refresh() => sync();

  Future<bool> addFavoriteTrack(String trackId) {
    final normalizedTrackId = requireCollectionsValue(trackId, 'trackId');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      if (cache.snapshot.favoriteTrackIds.contains(normalizedTrackId)) {
        return false;
      }

      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            favoriteTrackIds: {
              ...cache.snapshot.favoriteTrackIds,
              normalizedTrackId,
            },
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.addFavorite,
          createdAt: DateTime.now().toUtc(),
          trackId: normalizedTrackId,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  Future<bool> removeFavoriteTrack(String trackId) {
    final normalizedTrackId = requireCollectionsValue(trackId, 'trackId');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      if (!cache.snapshot.favoriteTrackIds.contains(normalizedTrackId)) {
        return false;
      }

      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            favoriteTrackIds: cache.snapshot.favoriteTrackIds
                .where(
                    (favoriteTrackId) => favoriteTrackId != normalizedTrackId)
                .toSet(),
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.removeFavorite,
          createdAt: DateTime.now().toUtc(),
          trackId: normalizedTrackId,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  Future<Playlist> createPlaylist(String name) {
    final normalizedName = requireCollectionsValue(name, 'name');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      final playlist = Playlist(
        id: _repository.createPlaylistId(),
        name: normalizedName,
      );
      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            playlists: [...cache.snapshot.playlists, playlist],
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.createPlaylist,
          createdAt: DateTime.now().toUtc(),
          playlistId: playlist.id,
          playlistName: playlist.name,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return playlist;
    });
  }

  Future<bool> renamePlaylist({
    required String playlistId,
    required String name,
  }) {
    final normalizedPlaylistId =
        requireCollectionsValue(playlistId, 'playlistId');
    final normalizedName = requireCollectionsValue(name, 'name');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      final playlistIndex = cache.snapshot.playlists.indexWhere(
        (playlist) => playlist.id == normalizedPlaylistId,
      );
      if (playlistIndex < 0 ||
          cache.snapshot.playlists[playlistIndex].name == normalizedName) {
        return false;
      }

      final updatedPlaylist = cache.snapshot.playlists[playlistIndex].copyWith(
        name: normalizedName,
      );
      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            playlists: _replacePlaylist(
              cache.snapshot.playlists,
              index: playlistIndex,
              replacement: updatedPlaylist,
            ),
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.renamePlaylist,
          createdAt: DateTime.now().toUtc(),
          playlistId: normalizedPlaylistId,
          playlistName: normalizedName,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  Future<bool> deletePlaylist(String playlistId) {
    final normalizedPlaylistId =
        requireCollectionsValue(playlistId, 'playlistId');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      if (!cache.snapshot.playlists.any(
        (playlist) => playlist.id == normalizedPlaylistId,
      )) {
        return false;
      }

      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            playlists: cache.snapshot.playlists
                .where((playlist) => playlist.id != normalizedPlaylistId)
                .toList(growable: false),
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.deletePlaylist,
          createdAt: DateTime.now().toUtc(),
          playlistId: normalizedPlaylistId,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  Future<bool> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) {
    final normalizedPlaylistId =
        requireCollectionsValue(playlistId, 'playlistId');
    final normalizedTrackId = requireCollectionsValue(trackId, 'trackId');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      final playlistIndex = cache.snapshot.playlists.indexWhere(
        (playlist) => playlist.id == normalizedPlaylistId,
      );
      if (playlistIndex < 0 ||
          cache.snapshot.playlists[playlistIndex].trackIds
              .contains(normalizedTrackId)) {
        return false;
      }

      final updatedPlaylist = cache.snapshot.playlists[playlistIndex].copyWith(
        trackIds: [
          ...cache.snapshot.playlists[playlistIndex].trackIds,
          normalizedTrackId,
        ],
      );
      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            playlists: _replacePlaylist(
              cache.snapshot.playlists,
              index: playlistIndex,
              replacement: updatedPlaylist,
            ),
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.addTrackToPlaylist,
          createdAt: DateTime.now().toUtc(),
          playlistId: normalizedPlaylistId,
          trackId: normalizedTrackId,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) {
    final normalizedPlaylistId =
        requireCollectionsValue(playlistId, 'playlistId');
    final normalizedTrackId = requireCollectionsValue(trackId, 'trackId');
    return _enqueue(() async {
      await future;
      final scope = _activeScope;
      final cache = await _repository.load(scope);
      final playlistIndex = cache.snapshot.playlists.indexWhere(
        (playlist) => playlist.id == normalizedPlaylistId,
      );
      if (playlistIndex < 0 ||
          !cache.snapshot.playlists[playlistIndex].trackIds
              .contains(normalizedTrackId)) {
        return false;
      }

      final updatedPlaylist = cache.snapshot.playlists[playlistIndex].copyWith(
        trackIds: cache.snapshot.playlists[playlistIndex].trackIds
            .where((playlistTrackId) => playlistTrackId != normalizedTrackId)
            .toList(growable: false),
      );
      final updatedCache = _queueChange(
        scope,
        cache.copyWith(
          snapshot: cache.snapshot.copyWith(
            playlists: _replacePlaylist(
              cache.snapshot.playlists,
              index: playlistIndex,
              replacement: updatedPlaylist,
            ),
          ),
        ),
        CollectionsOutboxItem(
          id: _newOutboxId(),
          action: CollectionsOutboxAction.removeTrackFromPlaylist,
          createdAt: DateTime.now().toUtc(),
          playlistId: normalizedPlaylistId,
          trackId: normalizedTrackId,
        ),
      );
      await _commit(scope, updatedCache);
      _scheduleSync(scope);
      return true;
    });
  }

  CollectionsRepository get _repository {
    return ref.read(collectionsRepositoryProvider);
  }

  CollectionsApi get _api => ref.read(collectionsApiProvider);

  void _observeLifecycle() {
    if (_observingLifecycle) {
      return;
    }
    WidgetsBinding.instance.addObserver(this);
    _observingLifecycle = true;
    ref.onDispose(() {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    });
  }

  void _switchToSession(AuthSession? session) {
    final nextScope = _scopeFor(session);
    if (nextScope == _activeScope) {
      return;
    }
    _activeScope = nextScope;
    state = AsyncData(CollectionsState());
    unawaited(
      _enqueue(() async {
        final loaded = await _loadState(nextScope);
        if (nextScope != _activeScope) {
          return;
        }
        state = AsyncData(loaded);
        if (nextScope.isRemote) {
          await _syncScope(nextScope);
        }
      }),
    );
  }

  CollectionsScope _scopeFor(AuthSession? session) {
    return session == null
        ? const CollectionsScope.local()
        : CollectionsScope.fromSession(session);
  }

  Future<CollectionsState> _loadState(CollectionsScope scope) async {
    final cache = await _repository.load(scope);
    return _stateForCache(cache);
  }

  CollectionsState _stateForCache(CollectionsCache cache) {
    return CollectionsState(
      favoriteTrackIds: cache.snapshot.favoriteTrackIds,
      playlists: cache.snapshot.playlists,
      revision: cache.snapshot.revision,
      pendingOutboxCount: cache.outbox.length,
    );
  }

  CollectionsCache _queueChange(
    CollectionsScope scope,
    CollectionsCache cache,
    CollectionsOutboxItem item,
  ) {
    if (!scope.isRemote) {
      return cache;
    }
    return cache.copyWith(outbox: [...cache.outbox, item]);
  }

  Future<void> _commit(
    CollectionsScope scope,
    CollectionsCache cache,
  ) async {
    await _repository.save(scope, cache);
    if (scope == _activeScope) {
      state = AsyncData(_stateForCache(cache));
    }
  }

  void _scheduleSync(CollectionsScope scope) {
    if (!scope.isRemote) {
      return;
    }
    unawaited(_enqueue(() => _syncScope(scope)));
  }

  Future<void> _syncScope(CollectionsScope scope) async {
    if (!scope.isRemote || scope != _activeScope) {
      return;
    }

    try {
      var cache = await _repository.load(scope);
      if (!cache.legacyImported) {
        final legacySnapshot = cache.legacyImportSnapshot;
        if (legacySnapshot != null && !legacySnapshot.isEmpty) {
          await _api.importCollections(legacySnapshot);
        }
        cache = cache.copyWith(
          legacyImported: true,
          clearLegacyImportSnapshot: true,
        );
        await _commit(scope, cache);
      }

      final remoteSnapshot = _mapRemotePlaylistIds(
        await _api.fetchCollections(),
        cache.playlistIdMappings,
      );
      cache = cache.copyWith(
        snapshot: _applyOutbox(remoteSnapshot, cache.outbox),
      );
      await _commit(scope, cache);

      while (cache.outbox.isNotEmpty) {
        final item = cache.outbox.first;
        try {
          cache = await _pushOutboxItem(scope, cache, item);
        } catch (error) {
          if (!_isPermanentClientFailure(error)) {
            rethrow;
          }

          cache = cache.copyWith(
            outbox: cache.outbox.skip(1).toList(growable: false),
          );
          await _commit(scope, cache);
          final refreshedSnapshot = _mapRemotePlaylistIds(
            await _api.fetchCollections(),
            cache.playlistIdMappings,
          );
          cache = cache.copyWith(
            snapshot: _applyOutbox(refreshedSnapshot, cache.outbox),
          );
          await _commit(scope, cache);
          continue;
        }
        cache = cache.copyWith(
          outbox: cache.outbox.skip(1).toList(growable: false),
        );
        await _commit(scope, cache);
      }

      final confirmedSnapshot = _mapRemotePlaylistIds(
        await _api.fetchCollections(),
        cache.playlistIdMappings,
      );
      cache = await _repository.load(scope);
      cache = cache.copyWith(
        snapshot: _applyOutbox(confirmedSnapshot, cache.outbox),
      );
      await _commit(scope, cache);
    } catch (_) {
      // The locally persisted optimistic state and outbox remain available.
    }
  }

  Future<CollectionsCache> _pushOutboxItem(
    CollectionsScope scope,
    CollectionsCache cache,
    CollectionsOutboxItem item,
  ) async {
    switch (item.action) {
      case CollectionsOutboxAction.addFavorite:
        await _api.addFavoriteTrack(_requiredOutboxValue(item.trackId));
        break;
      case CollectionsOutboxAction.removeFavorite:
        await _ignoreMissing(
          () => _api.removeFavoriteTrack(_requiredOutboxValue(item.trackId)),
        );
        break;
      case CollectionsOutboxAction.createPlaylist:
        final localPlaylistId = _requiredOutboxValue(item.playlistId);
        final createdPlaylist = await _api.createPlaylist(
          id: localPlaylistId,
          name: _requiredOutboxValue(item.playlistName),
        );
        return _recordRemotePlaylistId(
          cache,
          localPlaylistId: localPlaylistId,
          remotePlaylistId: createdPlaylist.id,
        );
      case CollectionsOutboxAction.renamePlaylist:
        await _api.renamePlaylist(
          playlistId: _remotePlaylistId(
            cache,
            _requiredOutboxValue(item.playlistId),
          ),
          name: _requiredOutboxValue(item.playlistName),
        );
        break;
      case CollectionsOutboxAction.deletePlaylist:
        await _ignoreMissing(
          () => _api.deletePlaylist(
            _remotePlaylistId(cache, _requiredOutboxValue(item.playlistId)),
          ),
        );
        return _removeRemotePlaylistId(
          cache,
          _requiredOutboxValue(item.playlistId),
        );
      case CollectionsOutboxAction.addTrackToPlaylist:
        await _api.addTrackToPlaylist(
          playlistId: _remotePlaylistId(
            cache,
            _requiredOutboxValue(item.playlistId),
          ),
          trackId: _requiredOutboxValue(item.trackId),
        );
        break;
      case CollectionsOutboxAction.removeTrackFromPlaylist:
        await _ignoreMissing(
          () => _api.removeTrackFromPlaylist(
            playlistId: _remotePlaylistId(
              cache,
              _requiredOutboxValue(item.playlistId),
            ),
            trackId: _requiredOutboxValue(item.trackId),
          ),
        );
        break;
    }
    return cache;
  }

  Future<void> _ignoreMissing(Future<void> Function() operation) async {
    try {
      await operation();
    } on ApiError catch (error) {
      if (error.statusCode != 404) {
        rethrow;
      }
    }
  }

  bool _isPermanentClientFailure(Object error) {
    if (error is! ApiError) {
      return false;
    }
    final statusCode = error.statusCode;
    return statusCode != null &&
        statusCode >= 400 &&
        statusCode < 500 &&
        statusCode != 408 &&
        statusCode != 409 &&
        statusCode != 429;
  }

  CollectionsCache _recordRemotePlaylistId(
    CollectionsCache cache, {
    required String localPlaylistId,
    required String remotePlaylistId,
  }) {
    return cache.copyWith(
      playlistIdMappings: {
        ...cache.playlistIdMappings,
        localPlaylistId: remotePlaylistId,
      },
    );
  }

  CollectionsCache _removeRemotePlaylistId(
    CollectionsCache cache,
    String localPlaylistId,
  ) {
    return cache.copyWith(
      playlistIdMappings: {
        for (final entry in cache.playlistIdMappings.entries)
          if (entry.key != localPlaylistId) entry.key: entry.value,
      },
    );
  }

  String _remotePlaylistId(
    CollectionsCache cache,
    String localPlaylistId,
  ) {
    return cache.playlistIdMappings[localPlaylistId] ?? localPlaylistId;
  }

  CollectionsSnapshot _mapRemotePlaylistIds(
    CollectionsSnapshot snapshot,
    Map<String, String> playlistIdMappings,
  ) {
    if (playlistIdMappings.isEmpty) {
      return snapshot;
    }
    final localIdsByRemoteId = {
      for (final entry in playlistIdMappings.entries) entry.value: entry.key,
    };
    return snapshot.copyWith(
      playlists: snapshot.playlists
          .map(
            (playlist) => playlist.copyWith(
              id: localIdsByRemoteId[playlist.id] ?? playlist.id,
            ),
          )
          .toList(growable: false),
    );
  }

  CollectionsSnapshot _applyOutbox(
    CollectionsSnapshot snapshot,
    List<CollectionsOutboxItem> outbox,
  ) {
    var favoriteTrackIds = snapshot.favoriteTrackIds;
    var playlists = snapshot.playlists;

    for (final item in outbox) {
      switch (item.action) {
        case CollectionsOutboxAction.addFavorite:
          favoriteTrackIds = {
            ...favoriteTrackIds,
            _requiredOutboxValue(item.trackId),
          };
          break;
        case CollectionsOutboxAction.removeFavorite:
          favoriteTrackIds = favoriteTrackIds
              .where((trackId) => trackId != _requiredOutboxValue(item.trackId))
              .toSet();
          break;
        case CollectionsOutboxAction.createPlaylist:
          final playlistId = _requiredOutboxValue(item.playlistId);
          if (!playlists.any((playlist) => playlist.id == playlistId)) {
            playlists = [
              ...playlists,
              Playlist(
                id: playlistId,
                name: _requiredOutboxValue(item.playlistName),
              ),
            ];
          }
          break;
        case CollectionsOutboxAction.renamePlaylist:
          playlists = _updatePlaylist(
            playlists,
            _requiredOutboxValue(item.playlistId),
            (playlist) => playlist.copyWith(
              name: _requiredOutboxValue(item.playlistName),
            ),
          );
          break;
        case CollectionsOutboxAction.deletePlaylist:
          playlists = playlists
              .where(
                (playlist) =>
                    playlist.id != _requiredOutboxValue(item.playlistId),
              )
              .toList(growable: false);
          break;
        case CollectionsOutboxAction.addTrackToPlaylist:
          playlists = _updatePlaylist(
            playlists,
            _requiredOutboxValue(item.playlistId),
            (playlist) => playlist.trackIds.contains(
              _requiredOutboxValue(item.trackId),
            )
                ? playlist
                : playlist.copyWith(
                    trackIds: [
                      ...playlist.trackIds,
                      _requiredOutboxValue(item.trackId),
                    ],
                  ),
          );
          break;
        case CollectionsOutboxAction.removeTrackFromPlaylist:
          playlists = _updatePlaylist(
            playlists,
            _requiredOutboxValue(item.playlistId),
            (playlist) => playlist.copyWith(
              trackIds: playlist.trackIds
                  .where(
                    (trackId) => trackId != _requiredOutboxValue(item.trackId),
                  )
                  .toList(growable: false),
            ),
          );
          break;
      }
    }

    return CollectionsSnapshot(
      revision: snapshot.revision,
      favoriteTrackIds: favoriteTrackIds,
      playlists: playlists,
    );
  }

  Future<T> _enqueue<T>(Future<T> Function() operation) {
    final result = _operationTail.then((_) => operation());
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }

  String _newOutboxId() {
    return 'outbox_${DateTime.now().microsecondsSinceEpoch}_${_repository.createPlaylistId()}';
  }
}

List<Playlist> _replacePlaylist(
  List<Playlist> playlists, {
  required int index,
  required Playlist replacement,
}) {
  return [
    ...playlists.take(index),
    replacement,
    ...playlists.skip(index + 1),
  ];
}

List<Playlist> _updatePlaylist(
  List<Playlist> playlists,
  String playlistId,
  Playlist Function(Playlist playlist) update,
) {
  return playlists
      .map(
        (playlist) => playlist.id == playlistId ? update(playlist) : playlist,
      )
      .toList(growable: false);
}

String _requiredOutboxValue(String? value) {
  if (value == null || value.isEmpty) {
    throw const FormatException('Invalid collections outbox item.');
  }
  return value;
}
