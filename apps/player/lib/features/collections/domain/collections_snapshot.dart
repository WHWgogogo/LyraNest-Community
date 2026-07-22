import 'package:flutter/foundation.dart';

import 'playlist.dart';

@immutable
class CollectionsSnapshot {
  CollectionsSnapshot({
    this.revision,
    Set<String> favoriteTrackIds = const <String>{},
    List<Playlist> playlists = const <Playlist>[],
  })  : favoriteTrackIds = Set.unmodifiable(favoriteTrackIds),
        playlists = List.unmodifiable(playlists);

  final int? revision;
  final Set<String> favoriteTrackIds;
  final List<Playlist> playlists;

  bool get isEmpty => favoriteTrackIds.isEmpty && playlists.isEmpty;

  factory CollectionsSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFavoriteTrackIds =
        json['favorite_track_ids'] ?? json['favoriteTrackIds'];
    final favoriteTrackIds = rawFavoriteTrackIds is List
        ? rawFavoriteTrackIds
            .whereType<String>()
            .map((trackId) => trackId.trim())
            .where((trackId) => trackId.isNotEmpty)
            .toSet()
        : <String>{};

    final rawPlaylists = json['playlists'];
    final playlists = <Playlist>[];
    final playlistIds = <String>{};
    if (rawPlaylists is List) {
      for (final rawPlaylist in rawPlaylists) {
        if (rawPlaylist is! Map) {
          continue;
        }
        try {
          final playlist = Playlist.fromJson(
            Map<String, dynamic>.from(rawPlaylist),
          );
          if (playlistIds.add(playlist.id)) {
            playlists.add(playlist);
          }
        } on FormatException {
          continue;
        }
      }
    }

    return CollectionsSnapshot(
      revision: _readRevision(json['revision']),
      favoriteTrackIds: favoriteTrackIds,
      playlists: playlists,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (revision != null) 'revision': revision,
      'favoriteTrackIds': favoriteTrackIds.toList(growable: false),
      'playlists': playlists.map((playlist) => playlist.toJson()).toList(),
    };
  }

  Map<String, dynamic> toRemoteImportJson() {
    return {
      if (revision != null) 'revision': revision,
      'favorite_track_ids': favoriteTrackIds.toList(growable: false),
      'playlists': playlists
          .map(
            (playlist) => {
              'id': playlist.id,
              'name': playlist.name,
              'track_ids': playlist.trackIds,
              if (playlist.createdAt != null)
                'created_at': playlist.createdAt!.toUtc().toIso8601String(),
              if (playlist.updatedAt != null)
                'updated_at': playlist.updatedAt!.toUtc().toIso8601String(),
            },
          )
          .toList(growable: false),
    };
  }

  CollectionsSnapshot copyWith({
    int? revision,
    Set<String>? favoriteTrackIds,
    List<Playlist>? playlists,
  }) {
    return CollectionsSnapshot(
      revision: revision ?? this.revision,
      favoriteTrackIds: favoriteTrackIds ?? this.favoriteTrackIds,
      playlists: playlists ?? this.playlists,
    );
  }
}

int? _readRevision(Object? value) {
  if (value is int) {
    return value;
  }
  return value is String ? int.tryParse(value.trim()) : null;
}
