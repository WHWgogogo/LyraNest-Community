import 'package:flutter/foundation.dart';

import '../../tracks/domain/track.dart';

@immutable
class DiscoveryData {
  const DiscoveryData({
    this.guessYouLike = const [],
    this.dailyRecommendations = const [],
    this.categoryPlaylists = const [],
    this.recentRecommendations = const [],
    this.moreRecommendations = const [],
  });

  final List<Track> guessYouLike;
  final List<Track> dailyRecommendations;
  final List<DiscoveryPlaylist> categoryPlaylists;
  final List<Track> recentRecommendations;
  final List<Track> moreRecommendations;

  factory DiscoveryData.fromJson(Object? json) {
    final map = _responseMap(json);
    return DiscoveryData(
      guessYouLike: _tracksFrom(
        map,
        const ['guess_you_like', 'for_you', 'personalized', 'recommendations'],
      ),
      dailyRecommendations: _tracksFrom(
        map,
        const ['daily_recommendations', 'daily', 'daily_tracks'],
      ),
      categoryPlaylists: _playlistsFrom(
        map['category_playlists'] ??
            map['categories'] ??
            map['playlist_categories'] ??
            map['playlists'],
      ),
      recentRecommendations: _tracksFrom(
        map,
        const [
          'recent_listening_recommendations',
          'recent_recommendations',
          'based_on_recent',
        ],
      ),
      moreRecommendations: _tracksFrom(map, const [
        'hot_tracks',
        'more_recommendations',
        'more_tracks',
        'recommended_tracks',
      ]),
    );
  }
}

@immutable
class DiscoveryPlaylist {
  const DiscoveryPlaylist({
    required this.id,
    required this.title,
    this.subtitle,
    this.coverUrl,
    this.tracks = const [],
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? coverUrl;
  final List<Track> tracks;

  factory DiscoveryPlaylist.fromJson(Map<String, dynamic> json) {
    return DiscoveryPlaylist(
      id: (json['id'] ?? json['playlist_id'] ?? json['name'] ?? '').toString(),
      title: (json['title'] ?? json['name'] ?? json['label'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? json['description'] ?? json['category'])
          ?.toString(),
      coverUrl: (json['cover_url'] ??
              json['coverUrl'] ??
              json['artwork_url'] ??
              json['image_url'])
          ?.toString(),
      tracks: _tracksFromValue(
        json['tracks'] ?? json['items'] ?? json['recommended_tracks'],
      ),
    );
  }
}

Map<String, dynamic> _responseMap(Object? json) {
  if (json is! Map) {
    return const <String, dynamic>{};
  }
  final data = json['data'];
  return data is Map
      ? Map<String, dynamic>.from(data)
      : Map<String, dynamic>.from(json);
}

List<Track> _tracksFrom(Map<String, dynamic> map, List<String> keys) {
  for (final key in keys) {
    final value = map[key];
    if (value is List) {
      return _tracksFromValue(value);
    }
    if (value is Map) {
      final nestedTracks = value['tracks'] ?? value['items'];
      if (nestedTracks is List) {
        return _tracksFromValue(nestedTracks);
      }
    }
  }
  return const [];
}

List<Track> _tracksFromValue(Object? value) {
  if (value is! List) {
    return const [];
  }

  final tracks = <Track>[];
  for (final rawTrack in value) {
    if (rawTrack is! Map) {
      continue;
    }
    final nestedTrack = rawTrack['track'];
    final trackJson = nestedTrack is Map ? nestedTrack : rawTrack;
    final track = Track.fromJson(Map<String, dynamic>.from(trackJson));
    if (track.id != 'null' && track.id.trim().isNotEmpty) {
      tracks.add(track);
    }
  }
  return List.unmodifiable(tracks);
}

List<DiscoveryPlaylist> _playlistsFrom(Object? value) {
  if (value is! List) {
    return const [];
  }

  final playlists = <DiscoveryPlaylist>[];
  for (final value in value) {
    if (value is! Map) {
      continue;
    }
    final playlist = DiscoveryPlaylist.fromJson(
      Map<String, dynamic>.from(value),
    );
    if (playlist.id.isNotEmpty && playlist.title.isNotEmpty) {
      playlists.add(playlist);
    }
  }
  return List.unmodifiable(playlists);
}
