import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/collections_outbox_item.dart';
import '../domain/collections_scope.dart';
import '../domain/collections_snapshot.dart';
import '../domain/playlist.dart';

const _legacyFavoriteTrackIdsKey = 'collections.favorite_track_ids.v1';
const _legacyPlaylistsKey = 'collections.playlists.v1';
const _scopedCacheKeyPrefix = 'collections.cache.v2.';
const _legacyOwnerKey = 'collections.legacy_owner.v2';

final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  return SharedPreferencesCollectionsRepository();
});

@immutable
class CollectionsCache {
  CollectionsCache({
    CollectionsSnapshot? snapshot,
    List<CollectionsOutboxItem> outbox = const <CollectionsOutboxItem>[],
    this.legacyImported = true,
    this.legacyImportSnapshot,
    Map<String, String> playlistIdMappings = const <String, String>{},
  })  : snapshot = snapshot ?? CollectionsSnapshot(),
        outbox = List.unmodifiable(outbox),
        playlistIdMappings = Map.unmodifiable(playlistIdMappings);

  final CollectionsSnapshot snapshot;
  final List<CollectionsOutboxItem> outbox;
  final bool legacyImported;
  final CollectionsSnapshot? legacyImportSnapshot;
  final Map<String, String> playlistIdMappings;

  factory CollectionsCache.fromJson(Map<String, dynamic> json) {
    final rawSnapshot = json['snapshot'];
    final snapshot = rawSnapshot is Map
        ? CollectionsSnapshot.fromJson(Map<String, dynamic>.from(rawSnapshot))
        : CollectionsSnapshot();
    final rawLegacyImportSnapshot = json['legacyImportSnapshot'];
    final legacyImportSnapshot = rawLegacyImportSnapshot is Map
        ? CollectionsSnapshot.fromJson(
            Map<String, dynamic>.from(rawLegacyImportSnapshot),
          )
        : null;
    final playlistIdMappings = <String, String>{};
    final rawPlaylistIdMappings = json['playlistIdMappings'];
    if (rawPlaylistIdMappings is Map) {
      for (final entry in rawPlaylistIdMappings.entries) {
        final localId = entry.key.toString().trim();
        final remoteId =
            entry.value is String ? (entry.value as String).trim() : '';
        if (localId.isNotEmpty && remoteId.isNotEmpty) {
          playlistIdMappings[localId] = remoteId;
        }
      }
    }
    final outbox = <CollectionsOutboxItem>[];
    final rawOutbox = json['outbox'];
    if (rawOutbox is List) {
      for (final rawItem in rawOutbox) {
        if (rawItem is! Map) {
          continue;
        }
        try {
          outbox.add(
            CollectionsOutboxItem.fromJson(
              Map<String, dynamic>.from(rawItem),
            ),
          );
        } on FormatException {
          continue;
        }
      }
    }

    return CollectionsCache(
      snapshot: snapshot,
      outbox: outbox,
      legacyImported: json['legacyImported'] is bool
          ? json['legacyImported'] as bool
          : true,
      legacyImportSnapshot: legacyImportSnapshot,
      playlistIdMappings: playlistIdMappings,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'snapshot': snapshot.toJson(),
      'outbox': outbox.map((item) => item.toJson()).toList(growable: false),
      'legacyImported': legacyImported,
      if (legacyImportSnapshot != null)
        'legacyImportSnapshot': legacyImportSnapshot!.toJson(),
      if (playlistIdMappings.isNotEmpty)
        'playlistIdMappings': playlistIdMappings,
    };
  }

  CollectionsCache copyWith({
    CollectionsSnapshot? snapshot,
    List<CollectionsOutboxItem>? outbox,
    bool? legacyImported,
    CollectionsSnapshot? legacyImportSnapshot,
    bool clearLegacyImportSnapshot = false,
    Map<String, String>? playlistIdMappings,
  }) {
    return CollectionsCache(
      snapshot: snapshot ?? this.snapshot,
      outbox: outbox ?? this.outbox,
      legacyImported: legacyImported ?? this.legacyImported,
      legacyImportSnapshot: clearLegacyImportSnapshot
          ? null
          : legacyImportSnapshot ?? this.legacyImportSnapshot,
      playlistIdMappings: playlistIdMappings ?? this.playlistIdMappings,
    );
  }
}

abstract interface class CollectionsRepository {
  Future<CollectionsCache> load(CollectionsScope scope);

  Future<void> save(CollectionsScope scope, CollectionsCache cache);

  String createPlaylistId();

  Future<Set<String>> getFavoriteTrackIds();

  Future<bool> addFavoriteTrack(String trackId);

  Future<bool> removeFavoriteTrack(String trackId);

  Future<List<Playlist>> getPlaylists();

  Future<Playlist?> getPlaylist(String playlistId);

  Future<Playlist> createPlaylist(String name);

  Future<bool> deletePlaylist(String playlistId);

  Future<bool> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  });

  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  });
}

class SharedPreferencesCollectionsRepository implements CollectionsRepository {
  SharedPreferencesCollectionsRepository({
    Future<SharedPreferences>? preferences,
    Random? random,
  })  : _preferences = preferences ?? SharedPreferences.getInstance(),
        _random = random ?? Random.secure();

  final Future<SharedPreferences> _preferences;
  final Random _random;

  @override
  Future<CollectionsCache> load(CollectionsScope scope) async {
    final preferences = await _preferences;
    if (!scope.isRemote) {
      return CollectionsCache(snapshot: _readLegacySnapshot(preferences));
    }

    final existing = _readScopedCache(preferences, scope);
    if (existing != null) {
      return existing;
    }

    final legacyOwner = preferences.getString(_legacyOwnerKey);
    final canClaimLegacy = legacyOwner == null || legacyOwner.trim().isEmpty;
    final legacySnapshot = canClaimLegacy
        ? _readLegacySnapshot(preferences)
        : CollectionsSnapshot();
    final cache = CollectionsCache(
      snapshot: legacySnapshot,
      legacyImported: legacySnapshot.isEmpty,
      legacyImportSnapshot: legacySnapshot.isEmpty ? null : legacySnapshot,
    );

    if (canClaimLegacy) {
      await preferences.setString(_legacyOwnerKey, scope.storageKey);
      await Future.wait([
        preferences.remove(_legacyFavoriteTrackIdsKey),
        preferences.remove(_legacyPlaylistsKey),
      ]);
    }
    await _writeScopedCache(preferences, scope, cache);
    return cache;
  }

  @override
  Future<void> save(CollectionsScope scope, CollectionsCache cache) async {
    final preferences = await _preferences;
    if (!scope.isRemote) {
      await _writeLegacySnapshot(preferences, cache.snapshot);
      return;
    }
    await _writeScopedCache(preferences, scope, cache);
  }

  @override
  String createPlaylistId() {
    return 'playlist_${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(1 << 32).toRadixString(36)}';
  }

  @override
  Future<Set<String>> getFavoriteTrackIds() async {
    return (await load(const CollectionsScope.local()))
        .snapshot
        .favoriteTrackIds;
  }

  @override
  Future<bool> addFavoriteTrack(String trackId) async {
    final normalizedTrackId = _requireValue(trackId, 'trackId');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    if (cache.snapshot.favoriteTrackIds.contains(normalizedTrackId)) {
      return false;
    }
    await save(
      scope,
      cache.copyWith(
        snapshot: cache.snapshot.copyWith(
          favoriteTrackIds: {
            ...cache.snapshot.favoriteTrackIds,
            normalizedTrackId,
          },
        ),
      ),
    );
    return true;
  }

  @override
  Future<bool> removeFavoriteTrack(String trackId) async {
    final normalizedTrackId = _requireValue(trackId, 'trackId');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    if (!cache.snapshot.favoriteTrackIds.contains(normalizedTrackId)) {
      return false;
    }
    await save(
      scope,
      cache.copyWith(
        snapshot: cache.snapshot.copyWith(
          favoriteTrackIds: cache.snapshot.favoriteTrackIds
              .where((favoriteTrackId) => favoriteTrackId != normalizedTrackId)
              .toSet(),
        ),
      ),
    );
    return true;
  }

  @override
  Future<List<Playlist>> getPlaylists() async {
    return (await load(const CollectionsScope.local())).snapshot.playlists;
  }

  @override
  Future<Playlist?> getPlaylist(String playlistId) async {
    final normalizedPlaylistId = _requireValue(playlistId, 'playlistId');
    for (final playlist in await getPlaylists()) {
      if (playlist.id == normalizedPlaylistId) {
        return playlist;
      }
    }
    return null;
  }

  @override
  Future<Playlist> createPlaylist(String name) async {
    final normalizedName = _requireValue(name, 'name');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    final playlist = Playlist(id: createPlaylistId(), name: normalizedName);
    await save(
      scope,
      cache.copyWith(
        snapshot: cache.snapshot.copyWith(
          playlists: [...cache.snapshot.playlists, playlist],
        ),
      ),
    );
    return playlist;
  }

  @override
  Future<bool> deletePlaylist(String playlistId) async {
    final normalizedPlaylistId = _requireValue(playlistId, 'playlistId');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    if (!cache.snapshot.playlists.any(
      (playlist) => playlist.id == normalizedPlaylistId,
    )) {
      return false;
    }
    await save(
      scope,
      cache.copyWith(
        snapshot: cache.snapshot.copyWith(
          playlists: cache.snapshot.playlists
              .where((playlist) => playlist.id != normalizedPlaylistId)
              .toList(growable: false),
        ),
      ),
    );
    return true;
  }

  @override
  Future<bool> addTrackToPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final normalizedPlaylistId = _requireValue(playlistId, 'playlistId');
    final normalizedTrackId = _requireValue(trackId, 'trackId');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    final playlistIndex = cache.snapshot.playlists.indexWhere(
      (playlist) => playlist.id == normalizedPlaylistId,
    );
    if (playlistIndex < 0 ||
        cache.snapshot.playlists[playlistIndex].trackIds
            .contains(normalizedTrackId)) {
      return false;
    }

    final playlist = cache.snapshot.playlists[playlistIndex];
    final updatedPlaylist = playlist.copyWith(
      trackIds: [...playlist.trackIds, normalizedTrackId],
    );
    await save(
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
    );
    return true;
  }

  @override
  Future<bool> removeTrackFromPlaylist({
    required String playlistId,
    required String trackId,
  }) async {
    final normalizedPlaylistId = _requireValue(playlistId, 'playlistId');
    final normalizedTrackId = _requireValue(trackId, 'trackId');
    final scope = const CollectionsScope.local();
    final cache = await load(scope);
    final playlistIndex = cache.snapshot.playlists.indexWhere(
      (playlist) => playlist.id == normalizedPlaylistId,
    );
    if (playlistIndex < 0 ||
        !cache.snapshot.playlists[playlistIndex].trackIds
            .contains(normalizedTrackId)) {
      return false;
    }

    final playlist = cache.snapshot.playlists[playlistIndex];
    final updatedPlaylist = playlist.copyWith(
      trackIds: playlist.trackIds
          .where((playlistTrackId) => playlistTrackId != normalizedTrackId)
          .toList(growable: false),
    );
    await save(
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
    );
    return true;
  }

  CollectionsCache? _readScopedCache(
    SharedPreferences preferences,
    CollectionsScope scope,
  ) {
    final encodedCache = preferences.getString(_scopedCacheKey(scope));
    if (encodedCache == null || encodedCache.trim().isEmpty) {
      return null;
    }
    try {
      final decodedCache = jsonDecode(encodedCache);
      if (decodedCache is! Map) {
        return null;
      }
      return CollectionsCache.fromJson(Map<String, dynamic>.from(decodedCache));
    } on FormatException {
      return null;
    }
  }

  Future<void> _writeScopedCache(
    SharedPreferences preferences,
    CollectionsScope scope,
    CollectionsCache cache,
  ) {
    return preferences.setString(
      _scopedCacheKey(scope),
      jsonEncode(cache.toJson()),
    );
  }

  CollectionsSnapshot _readLegacySnapshot(SharedPreferences preferences) {
    final favoriteTrackIds =
        preferences.getStringList(_legacyFavoriteTrackIdsKey) ?? const [];
    final encodedPlaylists = preferences.getString(_legacyPlaylistsKey);
    Object? playlists = const [];
    if (encodedPlaylists != null && encodedPlaylists.trim().isNotEmpty) {
      try {
        playlists = jsonDecode(encodedPlaylists);
      } on FormatException {
        playlists = const [];
      }
    }
    return CollectionsSnapshot.fromJson({
      'favoriteTrackIds': favoriteTrackIds,
      'playlists': playlists,
    });
  }

  Future<void> _writeLegacySnapshot(
    SharedPreferences preferences,
    CollectionsSnapshot snapshot,
  ) async {
    await Future.wait([
      preferences.setStringList(
        _legacyFavoriteTrackIdsKey,
        snapshot.favoriteTrackIds.toList(growable: false),
      ),
      preferences.setString(
        _legacyPlaylistsKey,
        jsonEncode(
          snapshot.playlists
              .map((playlist) => playlist.toJson())
              .toList(growable: false),
        ),
      ),
    ]);
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

String _scopedCacheKey(CollectionsScope scope) {
  return '$_scopedCacheKeyPrefix${scope.storageKey}';
}

String requireCollectionsValue(String value, String argumentName) {
  return _requireValue(value, argumentName);
}

String _requireValue(String value, String argumentName) {
  final normalizedValue = value.trim();
  if (normalizedValue.isEmpty) {
    throw ArgumentError.value(
      value,
      argumentName,
      'Must not be empty.',
    );
  }
  return normalizedValue;
}
