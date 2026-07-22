import 'package:flutter/foundation.dart';

@immutable
class Track {
  const Track({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.genres = const [],
    this.durationSeconds,
    this.streamUrl,
    this.artworkUrl,
  });

  static const untitledTitle = 'Untitled track';

  final String id;
  final String title;
  final String? artist;
  final String? album;
  final List<String> genres;
  final int? durationSeconds;
  final String? streamUrl;
  final String? artworkUrl;

  factory Track.fromJson(Map<String, dynamic> json) {
    final durationSeconds = _intFromJson(
      json['durationSeconds'] ?? json['duration_seconds'] ?? json['duration'],
    );
    final durationMilliseconds = _intFromJson(
      json['durationMs'] ?? json['duration_ms'],
    );

    return Track(
      id: json['id'].toString(),
      title: json['title'] as String? ?? untitledTitle,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      genres: _stringsFromJson(json['genres'] ?? json['genre']),
      durationSeconds: durationSeconds ??
          (durationMilliseconds == null ? null : durationMilliseconds ~/ 1000),
      streamUrl: json['streamUrl'] as String? ?? json['url'] as String?,
      artworkUrl: json['artworkUrl'] as String?,
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

  static List<String> _stringsFromJson(Object? value) {
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? const [] : [trimmed];
    }
    if (value is! List<dynamic>) {
      return const [];
    }

    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }
}
