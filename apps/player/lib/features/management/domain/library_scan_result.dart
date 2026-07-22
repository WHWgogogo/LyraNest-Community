import 'package:flutter/foundation.dart';

import '../../tracks/domain/track.dart';

@immutable
class LibraryScanResult {
  const LibraryScanResult({
    required this.tracks,
    required this.total,
    required this.scannedAt,
  });

  final List<Track> tracks;
  final int total;
  final DateTime scannedAt;

  factory LibraryScanResult.fromJson(Object? json) {
    final map = _jsonMap(json);
    final rawTracks = map['tracks'];
    final tracks = rawTracks is List<dynamic>
        ? rawTracks
            .whereType<Map<dynamic, dynamic>>()
            .map(
              (track) => Track.fromJson(
                track.map(
                  (key, value) => MapEntry(key.toString(), value),
                ),
              ),
            )
            .toList(growable: false)
        : const <Track>[];
    final scannedAt = _dateTimeFromJson(
      map['scanned_at'] ?? map['scannedAt'],
    );

    if (scannedAt == null) {
      throw const FormatException('Invalid library scan timestamp');
    }

    return LibraryScanResult(
      tracks: tracks,
      total: _intFromJson(map['total']) ?? tracks.length,
      scannedAt: scannedAt,
    );
  }
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return const {};
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

int? _intFromJson(Object? value) {
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

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
