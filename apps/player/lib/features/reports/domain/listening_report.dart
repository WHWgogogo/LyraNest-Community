import 'package:flutter/foundation.dart';

import '../../tracks/domain/track.dart';

@immutable
class ListeningReport {
  const ListeningReport({
    required this.year,
    this.totalListeningSeconds = 0,
    this.playCount = 0,
    this.activeDays = 0,
    this.songCount = 0,
    this.albumCount = 0,
    this.heatmap = const [],
    this.topTracks = const [],
  });

  final int year;
  final int totalListeningSeconds;
  final int playCount;
  final int activeDays;
  final int songCount;
  final int albumCount;
  final List<ListeningHeatmapEntry> heatmap;
  final List<RankedTrack> topTracks;

  bool get hasListeningHistory =>
      playCount > 0 ||
      totalListeningSeconds > 0 ||
      heatmap.isNotEmpty ||
      topTracks.isNotEmpty;

  factory ListeningReport.fromJson(Object? json, {required int year}) {
    final map = _responseMap(json);
    final totalListenedMs = _int(map['total_listened_ms']);
    return ListeningReport(
      year: _int(map['year']) ?? year,
      totalListeningSeconds: totalListenedMs == null
          ? _int(
                map['total_listening_seconds'] ??
                    map['total_duration_seconds'] ??
                    map['listening_seconds'] ??
                    map['total_seconds'] ??
                    map['duration_seconds'],
              ) ??
              0
          : totalListenedMs ~/ Duration.millisecondsPerSecond,
      playCount: _int(
            map['play_count'] ??
                map['total_plays'] ??
                map['listening_count'] ??
                map['plays'],
          ) ??
          0,
      activeDays: _int(
            map['active_days'] ?? map['listening_days'] ?? map['days_listened'],
          ) ??
          0,
      songCount: _int(
            map['song_count'] ?? map['track_count'] ?? map['unique_tracks'],
          ) ??
          0,
      albumCount: _int(
            map['album_count'] ?? map['unique_albums'],
          ) ??
          0,
      heatmap: _heatmapFromJson(
        map['heatmap'] ??
            map['daily_activity'] ??
            map['daily_listening'] ??
            map['calendar'],
      ),
      topTracks: _rankedTracksFromJson(
        map['top_tracks'] ?? map['hot_tracks'] ?? map['popular_tracks'],
      ),
    );
  }
}

@immutable
class ListeningHeatmapEntry {
  const ListeningHeatmapEntry({
    required this.date,
    required this.playCount,
  });

  final DateTime date;
  final int playCount;
}

@immutable
class RankedTrack {
  const RankedTrack({
    required this.track,
    this.playCount = 0,
    this.listeningSeconds = 0,
  });

  final Track track;
  final int playCount;
  final int listeningSeconds;

  factory RankedTrack.fromJson(Map<String, dynamic> json) {
    final rawTrack = json['track'];
    final trackJson = rawTrack is Map
        ? Map<String, dynamic>.from(rawTrack)
        : Map<String, dynamic>.from(json);
    trackJson['id'] ??= json['track_id'] ?? json['id'] ?? trackJson['track_id'];
    final listenedMs = _int(json['listened_ms']);

    return RankedTrack(
      track: Track.fromJson(trackJson),
      playCount: _int(
            json['play_count'] ??
                json['plays'] ??
                json['count'] ??
                json['times'],
          ) ??
          0,
      listeningSeconds: listenedMs == null
          ? _int(
                json['listening_seconds'] ??
                    json['total_seconds'] ??
                    json['duration_seconds'],
              ) ??
              0
          : listenedMs ~/ Duration.millisecondsPerSecond,
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

List<RankedTrack> _rankedTracksFromJson(Object? json) {
  if (json is! List) {
    return const [];
  }

  final tracks = <RankedTrack>[];
  for (final value in json) {
    if (value is! Map) {
      continue;
    }
    final ranked = RankedTrack.fromJson(Map<String, dynamic>.from(value));
    if (ranked.track.id != 'null' && ranked.track.id.trim().isNotEmpty) {
      tracks.add(ranked);
    }
  }
  return List.unmodifiable(tracks);
}

List<ListeningHeatmapEntry> _heatmapFromJson(Object? json) {
  if (json is Map) {
    return json.entries
        .map(
          (entry) => ListeningHeatmapEntry(
            date: _serverDate(entry.key) ?? DateTime.utc(0),
            playCount: _int(entry.value) ?? 0,
          ),
        )
        .where((entry) => entry.date.year > 0)
        .toList(growable: false);
  }
  if (json is! List) {
    return const [];
  }

  return json
      .whereType<Map>()
      .map((entry) {
        final date = _serverDate(
          entry['date'] ?? entry['day'] ?? entry['listened_at'],
        );
        if (date == null) {
          return null;
        }
        return ListeningHeatmapEntry(
          date: date,
          playCount: _int(
                entry['play_count'] ??
                    entry['count'] ??
                    entry['plays'] ??
                    entry['value'],
              ) ??
              0,
        );
      })
      .whereType<ListeningHeatmapEntry>()
      .toList(growable: false);
}

int? _int(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return value is String ? int.tryParse(value) : null;
}

DateTime? _serverDate(Object? value) {
  if (value is! String) {
    return null;
  }
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    return null;
  }
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) {
    return null;
  }
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}
