import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/features/auth/application/auth_controller.dart';
import 'package:player/features/auth/domain/auth_session.dart';
import 'package:player/features/auth/domain/auth_state.dart';
import 'package:player/features/collections/application/collections_controller.dart';
import 'package:player/features/collections/data/collections_api.dart';
import 'package:player/features/collections/data/collections_repository.dart';
import 'package:player/features/collections/domain/collections_scope.dart';
import 'package:player/features/collections/domain/collections_snapshot.dart';
import 'package:player/features/collections/domain/playlist.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('stores favorite track IDs and exposes them through Riverpod', () async {
    final container = _container();
    addTearDown(container.dispose);
    final controller = container.read(collectionsControllerProvider.notifier);

    await container.read(collectionsControllerProvider.future);
    expect(await controller.addFavoriteTrack(' track-1 '), isTrue);
    expect(await controller.addFavoriteTrack('track-1'), isFalse);
    expect(container.read(favoriteTrackIdsProvider), {'track-1'});
    expect(container.read(isFavoriteTrackProvider('track-1')), isTrue);
    expect(controller.isFavorite('track-1'), isTrue);

    expect(await controller.removeFavoriteTrack('track-1'), isTrue);
    expect(await controller.removeFavoriteTrack('track-1'), isFalse);
    expect(container.read(favoriteTrackIdsProvider), isEmpty);
  });

  test('creates, updates, queries, and deletes playlists', () async {
    final container = _container();
    addTearDown(container.dispose);
    final controller = container.read(collectionsControllerProvider.notifier);

    await container.read(collectionsControllerProvider.future);
    final playlist = await controller.createPlaylist(' Road trip ');

    expect(playlist.name, 'Road trip');
    expect(container.read(playlistsProvider), hasLength(1));
    expect(
      container.read(playlistByIdProvider(playlist.id))?.name,
      'Road trip',
    );
    expect(controller.getPlaylist(playlist.id)?.id, playlist.id);
    expect(
      await controller.renamePlaylist(
        playlistId: playlist.id,
        name: 'Road trip 2026',
      ),
      isTrue,
    );
    expect(controller.getPlaylist(playlist.id)?.name, 'Road trip 2026');

    expect(
      await controller.addTrackToPlaylist(
        playlistId: playlist.id,
        trackId: ' track-1 ',
      ),
      isTrue,
    );
    expect(
      await controller.addTrackToPlaylist(
        playlistId: playlist.id,
        trackId: 'track-1',
      ),
      isFalse,
    );
    expect(
      container.read(playlistTrackIdsProvider(playlist.id)),
      {'track-1'},
    );
    expect(controller.getPlaylistTrackIds(playlist.id), {'track-1'});

    expect(
      await controller.removeTrackFromPlaylist(
        playlistId: playlist.id,
        trackId: 'track-1',
      ),
      isTrue,
    );
    expect(
      await controller.removeTrackFromPlaylist(
        playlistId: playlist.id,
        trackId: 'track-1',
      ),
      isFalse,
    );
    expect(container.read(playlistTrackIdsProvider(playlist.id)), isEmpty);

    expect(await controller.deletePlaylist(playlist.id), isTrue);
    expect(await controller.deletePlaylist(playlist.id), isFalse);
    expect(container.read(playlistByIdProvider(playlist.id)), isNull);
  });

  test('restores anonymous local collections saved in SharedPreferences',
      () async {
    final firstContainer = _container();
    final firstController =
        firstContainer.read(collectionsControllerProvider.notifier);

    await firstContainer.read(collectionsControllerProvider.future);
    await firstController.addFavoriteTrack('track-1');
    final playlist = await firstController.createPlaylist('Favorites');
    await firstController.addTrackToPlaylist(
      playlistId: playlist.id,
      trackId: 'track-1',
    );
    firstContainer.dispose();

    final secondContainer = _container();
    addTearDown(secondContainer.dispose);

    final restored =
        await secondContainer.read(collectionsControllerProvider.future);
    expect(restored.favoriteTrackIds, {'track-1'});
    expect(restored.playlists, hasLength(1));
    expect(restored.playlists.single.name, 'Favorites');
    expect(restored.playlists.single.trackIds, ['track-1']);
  });

  test('migrates legacy data once and isolates each server account cache',
      () async {
    SharedPreferences.setMockInitialValues({
      'collections.favorite_track_ids.v1': ['legacy-track'],
      'collections.playlists.v1':
          '[{"id":"legacy-playlist","name":"Legacy","trackIds":["legacy-track"]}]',
    });
    final api = _FakeCollectionsApi();
    final session = _session('alice');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    await container.read(collectionsControllerProvider.notifier).sync();

    expect(api.importedSnapshots, hasLength(1));
    expect(api.importedSnapshots.single.favoriteTrackIds, {'legacy-track'});
    expect(api.importedSnapshots.single.playlists.single.name, 'Legacy');
    expect(
      container.read(favoriteTrackIdsProvider),
      containsAll(<String>['legacy-track']),
    );

    final preferences = await SharedPreferences.getInstance();
    expect(
        preferences.containsKey('collections.favorite_track_ids.v1'), isFalse);
    expect(preferences.containsKey('collections.playlists.v1'), isFalse);

    final repository = SharedPreferencesCollectionsRepository(
      preferences: Future.value(preferences),
    );
    final aliceCache = await repository.load(
      CollectionsScope.fromSession(session),
    );
    final bobCache = await repository.load(
      CollectionsScope.fromSession(_session('bob')),
    );
    expect(aliceCache.snapshot.favoriteTrackIds, {'legacy-track'});
    expect(bobCache.snapshot, isNot(equals(aliceCache.snapshot)));
    expect(bobCache.snapshot.isEmpty, isTrue);
  });

  test('keeps optimistic changes in the outbox and retries them online',
      () async {
    final api = _FakeCollectionsApi()..online = false;
    final session = _session('offline-user');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    final controller = container.read(collectionsControllerProvider.notifier);

    expect(await controller.addFavoriteTrack('offline-track'), isTrue);
    final playlist = await controller.createPlaylist('Offline playlist');
    expect(
      await controller.addTrackToPlaylist(
        playlistId: playlist.id,
        trackId: 'offline-track',
      ),
      isTrue,
    );
    expect(container.read(favoriteTrackIdsProvider), {'offline-track'});
    expect(
      container.read(playlistByIdProvider(playlist.id))?.trackIds,
      ['offline-track'],
    );

    final repository = container.read(collectionsRepositoryProvider);
    final offlineCache = await repository.load(
      CollectionsScope.fromSession(session),
    );
    expect(offlineCache.outbox, hasLength(3));

    api.online = true;
    await controller.sync();

    final synced = await repository.load(CollectionsScope.fromSession(session));
    expect(synced.outbox, isEmpty);
    expect(api.snapshot.favoriteTrackIds, {'offline-track'});
    expect(api.snapshot.playlists, hasLength(1));
    expect(api.snapshot.playlists.single.trackIds, ['offline-track']);
    expect(controller.getPlaylist(playlist.id)?.trackIds, ['offline-track']);
    expect(
        api.calls,
        containsAllInOrder(<String>[
          'favorite:add:offline-track',
          'playlist:create:${playlist.id}:Offline playlist',
          'playlist:add-track:remote-1:offline-track',
        ]));
  });

  test('retries playlist creation with its stable client ID', () async {
    final api = _FakeCollectionsApi()
      ..online = false
      ..acceptsClientPlaylistIds = true;
    final session = _session('idempotent-create-user');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    final controller = container.read(collectionsControllerProvider.notifier);

    final playlist = await controller.createPlaylist('Retry-safe playlist');
    api
      ..online = true
      ..failNextCreateAfterPersist = true;

    await controller.sync();

    final repository = container.read(collectionsRepositoryProvider);
    final cache = await repository.load(CollectionsScope.fromSession(session));
    expect(cache.outbox, isEmpty);
    expect(api.createdPlaylistIds, [playlist.id, playlist.id]);
    expect(api.snapshot.playlists, hasLength(1));
    expect(api.snapshot.playlists.single.id, playlist.id);
  });

  test('discards permanent client failures and continues the FIFO', () async {
    final api = _FakeCollectionsApi()..online = false;
    final session = _session('permanent-failure-user');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    final controller = container.read(collectionsControllerProvider.notifier);

    expect(await controller.addFavoriteTrack('rejected-track'), isTrue);
    expect(await controller.addFavoriteTrack('accepted-track'), isTrue);
    api.addFavoriteErrors['rejected-track'] = const ApiError(
      'Rejected',
      statusCode: 400,
    );
    api.online = true;

    await controller.sync();

    final repository = container.read(collectionsRepositoryProvider);
    final cache = await repository.load(CollectionsScope.fromSession(session));
    expect(cache.outbox, isEmpty);
    expect(api.snapshot.favoriteTrackIds, {'accepted-track'});
    expect(container.read(favoriteTrackIdsProvider), {'accepted-track'});
    expect(
      api.calls,
      containsAllInOrder(<String>[
        'favorite:add:rejected-track',
        'favorite:add:accepted-track',
      ]),
    );
  });

  test('keeps transient HTTP failures at the FIFO head', () async {
    for (final statusCode in [408, 409, 429, 500]) {
      final api = _FakeCollectionsApi()..online = false;
      final session = _session('transient-failure-$statusCode');
      final container = _container(session: session, api: api);
      await container.read(authControllerProvider.future);
      await container.read(collectionsControllerProvider.future);
      final controller = container.read(collectionsControllerProvider.notifier);

      expect(await controller.addFavoriteTrack('first-track'), isTrue);
      expect(await controller.addFavoriteTrack('second-track'), isTrue);
      api.addFavoriteErrors['first-track'] = ApiError(
        'Retry later',
        statusCode: statusCode,
      );
      api.online = true;

      await controller.sync();

      final repository = container.read(collectionsRepositoryProvider);
      final cache =
          await repository.load(CollectionsScope.fromSession(session));
      expect(
        cache.outbox.map((item) => item.trackId),
        ['first-track', 'second-track'],
        reason: 'HTTP $statusCode must remain retryable.',
      );
      expect(api.calls, isNot(contains('favorite:add:second-track')));
      container.dispose();
    }
  });

  test('remote pull overwrites stale cache but preserves pending local edits',
      () async {
    final api = _FakeCollectionsApi(
      snapshot: CollectionsSnapshot(
        revision: 1,
        favoriteTrackIds: {'server-track'},
      ),
    );
    final session = _session('merge-user');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    final controller = container.read(collectionsControllerProvider.notifier);
    await controller.sync();
    expect(container.read(favoriteTrackIdsProvider), {'server-track'});

    api.online = false;
    expect(await controller.addFavoriteTrack('local-track'), isTrue);
    api.snapshot = CollectionsSnapshot(
      revision: 2,
      favoriteTrackIds: {'server-track', 'new-server-track'},
    );
    api.online = true;

    await controller.sync();

    expect(
      container.read(favoriteTrackIdsProvider),
      {'server-track', 'new-server-track', 'local-track'},
    );
    expect(api.snapshot.favoriteTrackIds, {
      'server-track',
      'new-server-track',
      'local-track',
    });
  });

  test('replays favorite and playlist CRUD mutations through the remote API',
      () async {
    final api = _FakeCollectionsApi(
      snapshot: CollectionsSnapshot(
        revision: 1,
        favoriteTrackIds: {'remove-favorite'},
        playlists: [
          Playlist(
            id: 'remote-playlist',
            name: 'Original',
            trackIds: ['remove-track'],
          ),
        ],
      ),
    );
    final session = _session('crud-user');
    final container = _container(session: session, api: api);
    addTearDown(container.dispose);
    await container.read(authControllerProvider.future);
    await container.read(collectionsControllerProvider.future);
    final controller = container.read(collectionsControllerProvider.notifier);
    await controller.sync();

    api.online = false;
    expect(await controller.removeFavoriteTrack('remove-favorite'), isTrue);
    expect(await controller.addFavoriteTrack('add-favorite'), isTrue);
    expect(
      await controller.renamePlaylist(
        playlistId: 'remote-playlist',
        name: 'Renamed',
      ),
      isTrue,
    );
    expect(
      await controller.addTrackToPlaylist(
        playlistId: 'remote-playlist',
        trackId: 'add-track',
      ),
      isTrue,
    );
    expect(
      await controller.removeTrackFromPlaylist(
        playlistId: 'remote-playlist',
        trackId: 'remove-track',
      ),
      isTrue,
    );
    expect(await controller.deletePlaylist('remote-playlist'), isTrue);

    api.online = true;
    await controller.sync();

    expect(api.snapshot.favoriteTrackIds, {'add-favorite'});
    expect(api.snapshot.playlists, isEmpty);
    expect(
      api.calls,
      containsAllInOrder(<String>[
        'favorite:remove:remove-favorite',
        'favorite:add:add-favorite',
        'playlist:rename:Renamed',
        'playlist:add-track:remote-playlist:add-track',
        'playlist:remove-track:remove-track',
        'playlist:delete:remote-playlist',
      ]),
    );
  });
}

ProviderContainer _container({
  AuthSession? session,
  _FakeCollectionsApi? api,
}) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(
        () => _TestAuthController(session),
      ),
      if (api != null) collectionsApiProvider.overrideWithValue(api),
    ],
  );
}

AuthSession _session(String username) {
  return AuthSession(
    token: 'token-$username',
    username: username,
    serverBaseUrl: 'https://example.test',
  );
}

class _TestAuthController extends AuthController {
  _TestAuthController(this.session);

  final AuthSession? session;

  @override
  Future<AuthState> build() async {
    if (session == null) {
      return const AuthState.signedOut(serverInitialized: true);
    }
    return AuthState.signedIn(serverInitialized: true, session: session!);
  }
}

class _FakeCollectionsApi implements CollectionsApi {
  _FakeCollectionsApi({CollectionsSnapshot? snapshot})
      : snapshot = snapshot ?? CollectionsSnapshot(revision: 1);

  bool online = true;
  int _playlistCounter = 0;
  bool acceptsClientPlaylistIds = false;
  bool failNextCreateAfterPersist = false;
  CollectionsSnapshot snapshot;
  final List<CollectionsSnapshot> importedSnapshots = [];
  final List<String> calls = [];
  final List<String> createdPlaylistIds = [];
  final Map<String, ApiError> addFavoriteErrors = {};

  @override
  Future<void> addFavoriteTrack(String trackId) async {
    _checkOnline();
    calls.add('favorite:add:$trackId');
    final error = addFavoriteErrors[trackId];
    if (error != null) {
      throw error;
    }
    snapshot = snapshot.copyWith(
      favoriteTrackIds: {...snapshot.favoriteTrackIds, trackId},
    );
  }

  @override
  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    _checkOnline();
    calls.add('playlist:add-track:$playlistId:$trackId');
    snapshot = snapshot.copyWith(
      playlists: snapshot.playlists
          .map(
            (playlist) => playlist.id == playlistId
                ? playlist.copyWith(
                    trackIds: [...playlist.trackIds, trackId],
                  )
                : playlist,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<Playlist> createPlaylist({
    required String id,
    required String name,
  }) async {
    _checkOnline();
    calls.add('playlist:create:$id:$name');
    createdPlaylistIds.add(id);
    final existingPlaylist = snapshot.playlists
        .where((playlist) => playlist.id == id)
        .cast<Playlist?>()
        .firstOrNull;
    final playlist = existingPlaylist ??
        Playlist(
          id: acceptsClientPlaylistIds ? id : 'remote-${++_playlistCounter}',
          name: name,
        );
    if (existingPlaylist == null) {
      snapshot =
          snapshot.copyWith(playlists: [...snapshot.playlists, playlist]);
    }
    if (failNextCreateAfterPersist) {
      failNextCreateAfterPersist = false;
      throw const ApiError('Connection lost');
    }
    return playlist;
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    _checkOnline();
    calls.add('playlist:delete:$playlistId');
    snapshot = snapshot.copyWith(
      playlists: snapshot.playlists
          .where((playlist) => playlist.id != playlistId)
          .toList(growable: false),
    );
  }

  @override
  Future<CollectionsSnapshot> fetchCollections() async {
    _checkOnline();
    calls.add('collections:get');
    return snapshot;
  }

  @override
  Future<void> importCollections(CollectionsSnapshot imported) async {
    _checkOnline();
    calls.add('collections:import');
    importedSnapshots.add(imported);
    final importedPlaylistNames = {
      for (final playlist in snapshot.playlists) playlist.name,
    };
    snapshot = snapshot.copyWith(
      favoriteTrackIds: {
        ...snapshot.favoriteTrackIds,
        ...imported.favoriteTrackIds,
      },
      playlists: [
        ...snapshot.playlists,
        ...imported.playlists.where(
          (playlist) => importedPlaylistNames.add(playlist.name),
        ),
      ],
    );
  }

  @override
  Future<void> removeFavoriteTrack(String trackId) async {
    _checkOnline();
    calls.add('favorite:remove:$trackId');
    snapshot = snapshot.copyWith(
      favoriteTrackIds: snapshot.favoriteTrackIds
          .where((favoriteTrackId) => favoriteTrackId != trackId)
          .toSet(),
    );
  }

  @override
  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    _checkOnline();
    calls.add('playlist:remove-track:$trackId');
    snapshot = snapshot.copyWith(
      playlists: snapshot.playlists
          .map(
            (playlist) => playlist.id == playlistId
                ? playlist.copyWith(
                    trackIds: playlist.trackIds
                        .where((id) => id != trackId)
                        .toList(growable: false),
                  )
                : playlist,
          )
          .toList(growable: false),
    );
  }

  @override
  Future<Playlist?> renamePlaylist({
    required String playlistId,
    required String name,
  }) async {
    _checkOnline();
    calls.add('playlist:rename:$name');
    Playlist? renamed;
    snapshot = snapshot.copyWith(
      playlists: snapshot.playlists.map(
        (playlist) {
          if (playlist.id != playlistId) {
            return playlist;
          }
          renamed = playlist.copyWith(name: name);
          return renamed!;
        },
      ).toList(growable: false),
    );
    return renamed;
  }

  void _checkOnline() {
    if (!online) {
      throw const ApiError('Offline');
    }
  }
}
