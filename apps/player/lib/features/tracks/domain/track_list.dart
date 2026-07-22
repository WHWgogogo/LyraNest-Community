import 'package:flutter/foundation.dart';

import 'track.dart';

@immutable
class TrackList {
  const TrackList({
    required this.tracks,
    required this.total,
  });

  final List<Track> tracks;
  final int total;

  factory TrackList.fromJson(Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final rawTracks = map['tracks'];
    final tracks = rawTracks is List<dynamic>
        ? rawTracks
            .whereType<Map<String, dynamic>>()
            .map(Track.fromJson)
            .toList(growable: false)
        : const <Track>[];

    return TrackList(
      tracks: tracks,
      total: _intFromJson(map['total']) ?? tracks.length,
    );
  }

  static int? _intFromJson(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }
}
