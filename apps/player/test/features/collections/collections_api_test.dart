import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/collections/data/collections_api.dart';
import 'package:player/features/collections/domain/collections_snapshot.dart';
import 'package:player/features/collections/domain/playlist.dart';

void main() {
  test('matches collection CRUD and import snapshot contracts', () async {
    final adapter = _CollectionsAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = DioCollectionsApi(dio, paths: const CollectionsApiPaths());

    final snapshot = await api.fetchCollections();
    expect(snapshot.revision, 7);
    expect(snapshot.playlists.single.createdAt, DateTime.utc(2026, 7, 20));

    await api.addFavoriteTrack('track-1');
    await api.removeFavoriteTrack('track-1');
    final created = await api.createPlaylist(
      id: 'client-playlist',
      name: 'Morning Mix',
    );
    expect(created.id, 'server-playlist');
    expect(created.createdAt, DateTime.utc(2026, 7, 20));
    final renamed = await api.renamePlaylist(
      playlistId: 'server-playlist',
      name: 'Morning Focus',
    );
    expect(renamed?.name, 'Morning Focus');
    await api.addTrackToPlaylist(
      playlistId: 'server-playlist',
      trackId: 'track-1',
    );
    await api.removeTrackFromPlaylist(
      playlistId: 'server-playlist',
      trackId: 'track-1',
    );
    await api.deletePlaylist('server-playlist');
    await api.importCollections(
      CollectionsSnapshot(
        revision: 8,
        favoriteTrackIds: {'track-1'},
        playlists: [
          Playlist(
            id: 'local-playlist',
            name: 'Imported',
            trackIds: const ['track-1'],
            createdAt: DateTime.utc(2026, 7, 20, 8),
            updatedAt: DateTime.utc(2026, 7, 20, 9),
          ),
        ],
      ),
    );

    expect(
      adapter.requests.map((request) => '${request.method} ${request.path}'),
      [
        'GET /api/v1/me/collections',
        'PUT /api/v1/me/favorites/track-1',
        'DELETE /api/v1/me/favorites/track-1',
        'POST /api/v1/me/playlists',
        'PATCH /api/v1/me/playlists/server-playlist',
        'PUT /api/v1/me/playlists/server-playlist/tracks/track-1',
        'DELETE /api/v1/me/playlists/server-playlist/tracks/track-1',
        'DELETE /api/v1/me/playlists/server-playlist',
        'POST /api/v1/me/collections/import',
      ],
    );
    expect(
      adapter.requests[3].data,
      {
        'id': 'client-playlist',
        'name': 'Morning Mix',
      },
    );
    expect(adapter.requests[4].data, {'name': 'Morning Focus'});
    expect(adapter.requests.last.data, {
      'revision': 8,
      'favorite_track_ids': ['track-1'],
      'playlists': [
        {
          'id': 'local-playlist',
          'name': 'Imported',
          'track_ids': ['track-1'],
          'created_at': '2026-07-20T08:00:00.000Z',
          'updated_at': '2026-07-20T09:00:00.000Z',
        },
      ],
    });
  });
}

class _CollectionsAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(_responseFor(options)),
      options.method == 'POST' && options.path == '/api/v1/me/playlists'
          ? 201
          : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}

  Map<String, Object> _responseFor(RequestOptions options) {
    final playlistName = switch (options.path) {
      '/api/v1/me/playlists' => 'Morning Mix',
      '/api/v1/me/playlists/server-playlist' when options.method == 'PATCH' =>
        'Morning Focus',
      _ => 'Morning Focus',
    };
    return {
      'revision': 7,
      'favorite_track_ids': ['track-1'],
      'playlists': [
        {
          'id': 'server-playlist',
          'name': playlistName,
          'track_ids': ['track-1'],
          'created_at': '2026-07-20T00:00:00Z',
          'updated_at': '2026-07-20T00:00:00Z',
        },
      ],
    };
  }
}
