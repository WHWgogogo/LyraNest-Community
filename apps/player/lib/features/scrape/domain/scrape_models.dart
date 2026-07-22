import 'package:flutter/foundation.dart';

import '../../tracks/domain/track.dart';

enum ScrapeField {
  title('title'),
  artist('artist'),
  album('album'),
  albumArtist('album_artist'),
  year('year'),
  trackNumber('track_number'),
  discNumber('disc_number'),
  genre('genre'),
  artworkUrl('artwork_url'),
  lyrics('lyrics');

  const ScrapeField(this.apiName);

  final String apiName;

  static ScrapeField? fromApiName(Object? value) {
    final name = value?.toString();
    if (name == 'genres') {
      return ScrapeField.genre;
    }
    for (final field in values) {
      if (field.apiName == name) {
        return field;
      }
    }
    return null;
  }
}

@immutable
class ScrapeSearchQuery {
  const ScrapeSearchQuery({
    this.title,
    this.artist,
    this.album,
    this.limit,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? limit;

  bool get isEmpty =>
      _trimmedValue(title) == null &&
      _trimmedValue(artist) == null &&
      _trimmedValue(album) == null &&
      limit == null;

  Map<String, dynamic> toJson() {
    final data = <String, dynamic>{};
    final normalizedTitle = _trimmedValue(title);
    final normalizedArtist = _trimmedValue(artist);
    final normalizedAlbum = _trimmedValue(album);

    if (normalizedTitle != null) {
      data['title'] = normalizedTitle;
    }
    if (normalizedArtist != null) {
      data['artist'] = normalizedArtist;
    }
    if (normalizedAlbum != null) {
      data['album'] = normalizedAlbum;
    }
    if (limit case final value? when value > 0) {
      data['limit'] = value;
    }

    return data;
  }

  @override
  bool operator ==(Object other) {
    return other is ScrapeSearchQuery &&
        other.title == title &&
        other.artist == artist &&
        other.album == album &&
        other.limit == limit;
  }

  @override
  int get hashCode => Object.hash(title, artist, album, limit);
}

@immutable
class ScrapeSearchRequest {
  const ScrapeSearchRequest({
    required this.trackId,
    this.query = const ScrapeSearchQuery(),
  });

  final String trackId;
  final ScrapeSearchQuery query;

  @override
  bool operator ==(Object other) {
    return other is ScrapeSearchRequest &&
        other.trackId == trackId &&
        other.query == query;
  }

  @override
  int get hashCode => Object.hash(trackId, query);
}

@immutable
class ScrapeFieldDifference {
  const ScrapeFieldDifference({
    required this.field,
    required this.current,
    required this.candidate,
    required this.changed,
  });

  final ScrapeField field;
  final Object? current;
  final Object? candidate;
  final bool changed;

  factory ScrapeFieldDifference.fromJson(Object? json) {
    final map = _jsonMap(json);
    final field = ScrapeField.fromApiName(map['field']);
    if (field == null) {
      throw const FormatException('Unknown scrape field');
    }
    final current = _scrapeValue(map['current'] ?? map['before']);
    final candidate = _scrapeValue(map['candidate'] ?? map['after']);

    return ScrapeFieldDifference(
      field: field,
      current: current,
      candidate: candidate,
      changed: map['changed'] is bool
          ? map['changed'] as bool
          : current?.toString() != candidate?.toString(),
    );
  }
}

@immutable
class ScrapeCandidate {
  const ScrapeCandidate({
    required this.id,
    required this.provider,
    required this.confidence,
    required this.metadata,
    required this.differences,
    this.sourceUrl,
  });

  final String id;
  final String provider;
  final double confidence;
  final Map<ScrapeField, Object?> metadata;
  final List<ScrapeFieldDifference> differences;
  final String? sourceUrl;

  factory ScrapeCandidate.fromJson(Object? json) {
    final map = _jsonMap(json);
    final rawMetadata = _jsonMap(map['metadata'] ?? map['fields']);
    final metadata = <ScrapeField, Object?>{};
    for (final entry in rawMetadata.entries) {
      final field = ScrapeField.fromApiName(entry.key);
      if (field == null) {
        continue;
      }
      final value = _scrapeValue(entry.value);
      if (value != null) {
        metadata[field] = value;
      }
    }

    final rawDifferences = map['differences'];
    final differences = rawDifferences is List<dynamic>
        ? rawDifferences
            .map((value) {
              try {
                return ScrapeFieldDifference.fromJson(value);
              } on FormatException {
                return null;
              }
            })
            .whereType<ScrapeFieldDifference>()
            .toList(growable: false)
        : const <ScrapeFieldDifference>[];
    final confidence = _doubleFromJson(map['confidence']) ?? 0;
    final normalizedConfidence = confidence > 1
        ? (confidence / 100).clamp(0, 1).toDouble()
        : confidence.clamp(0, 1).toDouble();
    final sourceUrl = _optionalString(
      map['source_url'] ?? map['sourceUrl'],
    );

    return ScrapeCandidate(
      id: _stringFromJson(
        map['id'] ?? map['candidate_id'] ?? map['candidateId'],
      ),
      provider: _stringFromJson(map['provider'], fallback: 'unknown'),
      confidence: normalizedConfidence,
      metadata: Map.unmodifiable(metadata),
      differences: differences,
      sourceUrl: sourceUrl,
    );
  }
}

@immutable
class ScrapeSearchResult {
  const ScrapeSearchResult({
    required this.trackId,
    required this.candidates,
    this.searchedAt,
  });

  final String trackId;
  final List<ScrapeCandidate> candidates;
  final DateTime? searchedAt;

  factory ScrapeSearchResult.fromJson(
    String fallbackTrackId,
    Object? json,
  ) {
    final map = _jsonMap(json);
    final rawCandidates = map['candidates'] ?? map['results'];
    final candidates = rawCandidates is List<dynamic>
        ? rawCandidates.map(ScrapeCandidate.fromJson).toList(growable: false)
        : const <ScrapeCandidate>[];

    return ScrapeSearchResult(
      trackId: _stringFromJson(
        map['track_id'] ?? map['trackId'],
        fallback: fallbackTrackId,
      ),
      candidates: candidates,
      searchedAt: _dateTimeFromJson(
        map['searched_at'] ?? map['searchedAt'],
      ),
    );
  }
}

@immutable
class ScrapeApplyResult {
  const ScrapeApplyResult({
    required this.track,
    required this.provider,
    required this.appliedFields,
    required this.appliedAt,
  });

  final Track track;
  final String provider;
  final List<ScrapeField> appliedFields;
  final DateTime appliedAt;

  factory ScrapeApplyResult.fromJson(
    Object? json, {
    required String trackId,
    required String provider,
    required List<ScrapeField> requestedFields,
  }) {
    final map = _jsonMap(json);
    final rawTrack = _jsonMap(map['track']);
    final rawFields = map['applied_fields'] ?? map['appliedFields'];
    final appliedFields = rawFields is List<dynamic>
        ? rawFields
            .map(ScrapeField.fromApiName)
            .whereType<ScrapeField>()
            .toList(growable: false)
        : requestedFields;

    return ScrapeApplyResult(
      track: rawTrack.isEmpty
          ? Track(id: trackId, title: Track.untitledTitle)
          : Track.fromJson(rawTrack),
      provider: _stringFromJson(map['provider'], fallback: provider),
      appliedFields: appliedFields,
      appliedAt: _dateTimeFromJson(
            map['applied_at'] ?? map['appliedAt'],
          ) ??
          DateTime.now().toUtc(),
    );
  }
}

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is! Map<dynamic, dynamic>) {
    return const {};
  }
  return value.map((key, value) => MapEntry(key.toString(), value));
}

String _stringFromJson(Object? value, {String fallback = ''}) {
  return value is String ? value : fallback;
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value;
}

String? _trimmedValue(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

double? _doubleFromJson(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value);
  }
  return null;
}

Object? _scrapeValue(Object? value) {
  if (value is String || value is num) {
    return value;
  }
  if (value is List<dynamic>) {
    final items = value
        .whereType<Object>()
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    return items.isEmpty ? null : items.join(', ');
  }
  return null;
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value);
}
