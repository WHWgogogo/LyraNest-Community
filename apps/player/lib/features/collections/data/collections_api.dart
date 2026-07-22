import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/collections_snapshot.dart';
import '../domain/playlist.dart';

@immutable
class CollectionsApiPaths {
  const CollectionsApiPaths({
    this.collections = '/api/v1/me/collections',
    this.favorites = '/api/v1/me/favorites',
    this.playlists = '/api/v1/me/playlists',
    this.import = '/api/v1/me/collections/import',
  });

  final String collections;
  final String favorites;
  final String playlists;
  final String import;

  String favorite(String trackId) =>
      '$favorites/${Uri.encodeComponent(trackId)}';

  String playlist(String playlistId) =>
      '$playlists/${Uri.encodeComponent(playlistId)}';

  String playlistTrack(String playlistId, String trackId) {
    return '${playlist(playlistId)}/tracks/${Uri.encodeComponent(trackId)}';
  }
}

final collectionsApiPathsProvider = Provider<CollectionsApiPaths>((ref) {
  return const CollectionsApiPaths();
});

final collectionsApiProvider = Provider<CollectionsApi>((ref) {
  return DioCollectionsApi(
    ref.watch(dioProvider),
    paths: ref.watch(collectionsApiPathsProvider),
  );
});

abstract interface class CollectionsApi {
  Future<CollectionsSnapshot> fetchCollections();

  Future<void> addFavoriteTrack(String trackId);

  Future<void> removeFavoriteTrack(String trackId);

  Future<Playlist> createPlaylist({
    required String id,
    required String name,
  });

  Future<Playlist?> renamePlaylist({
    required String playlistId,
    required String name,
  });

  Future<void> deletePlaylist(String playlistId);

  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  });

  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  });

  Future<void> importCollections(CollectionsSnapshot snapshot);
}

class DioCollectionsApi implements CollectionsApi {
  const DioCollectionsApi(this._dio, {required this.paths});

  final Dio _dio;
  final CollectionsApiPaths paths;

  @override
  Future<CollectionsSnapshot> fetchCollections() async {
    try {
      final response = await _dio.get(paths.collections);
      return _readSnapshot(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<void> addFavoriteTrack(String trackId) {
    return _sendSnapshot(
      () => _dio.put(paths.favorite(trackId)),
    );
  }

  @override
  Future<void> removeFavoriteTrack(String trackId) {
    return _sendSnapshot(
      () => _dio.delete(paths.favorite(trackId)),
    );
  }

  @override
  Future<Playlist> createPlaylist({
    required String id,
    required String name,
  }) async {
    final snapshot = await _sendSnapshot(
      () => _dio.post(
        paths.playlists,
        data: {
          'id': id,
          'name': name,
        },
      ),
    );
    if (snapshot.playlists.isEmpty) {
      throw const ApiError('Server did not return the created playlist.');
    }
    for (final playlist in snapshot.playlists) {
      if (playlist.id == id) {
        return playlist;
      }
    }
    return snapshot.playlists.last;
  }

  @override
  Future<Playlist?> renamePlaylist({
    required String playlistId,
    required String name,
  }) async {
    final snapshot = await _sendSnapshot(
      () => _dio.patch(
        paths.playlist(playlistId),
        data: {'name': name},
      ),
    );
    final normalizedPlaylistId = playlistId.trim();
    for (final playlist in snapshot.playlists) {
      if (playlist.id == normalizedPlaylistId) {
        return playlist;
      }
    }
    return null;
  }

  @override
  Future<void> deletePlaylist(String playlistId) {
    return _sendSnapshot(
      () => _dio.delete(paths.playlist(playlistId)),
    );
  }

  @override
  Future<void> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) {
    return _sendSnapshot(
      () => _dio.put(paths.playlistTrack(playlistId, trackId)),
    );
  }

  @override
  Future<void> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) {
    return _sendSnapshot(
      () => _dio.delete(paths.playlistTrack(playlistId, trackId)),
    );
  }

  @override
  Future<void> importCollections(CollectionsSnapshot snapshot) {
    return _sendSnapshot(
      () => _dio.post(
        paths.import,
        data: snapshot.toRemoteImportJson(),
      ),
    );
  }

  Future<CollectionsSnapshot> _sendSnapshot(
    Future<Response<dynamic>> Function() request,
  ) async {
    try {
      final response = await request();
      return _readSnapshot(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}

CollectionsSnapshot _readSnapshot(Object? data) {
  if (data is! Map) {
    throw const ApiError('Server returned invalid collections data.');
  }
  return CollectionsSnapshot.fromJson(Map<String, dynamic>.from(data));
}
