import 'package:flutter/foundation.dart';

@immutable
class Playlist {
  Playlist({
    required this.id,
    required this.name,
    List<String> trackIds = const [],
    this.createdAt,
    this.updatedAt,
  }) : trackIds = List.unmodifiable(trackIds);

  final String id;
  final String name;
  final List<String> trackIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Playlist.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    if (id is! String || id.trim().isEmpty) {
      throw const FormatException('Playlist id must be a non-empty string.');
    }
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('Playlist name must be a non-empty string.');
    }

    final rawTrackIds = json['track_ids'] ?? json['trackIds'];
    final trackIds = rawTrackIds is List
        ? rawTrackIds
            .whereType<String>()
            .map((trackId) => trackId.trim())
            .where((trackId) => trackId.isNotEmpty)
            .toSet()
            .toList(growable: false)
        : const <String>[];

    return Playlist(
      id: id.trim(),
      name: name.trim(),
      trackIds: trackIds,
      createdAt: _readDateTime(json['created_at'] ?? json['createdAt']),
      updatedAt: _readDateTime(json['updated_at'] ?? json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'trackIds': trackIds,
      if (createdAt != null) 'createdAt': createdAt!.toUtc().toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toUtc().toIso8601String(),
    };
  }

  Playlist copyWith({
    String? id,
    String? name,
    List<String>? trackIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Playlist(
      id: id ?? this.id,
      name: name ?? this.name,
      trackIds: trackIds ?? this.trackIds,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

DateTime? _readDateTime(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return DateTime.tryParse(value.trim())?.toUtc();
}
