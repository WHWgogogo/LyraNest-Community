import 'package:flutter/foundation.dart';

enum CollectionsOutboxAction {
  addFavorite,
  removeFavorite,
  createPlaylist,
  renamePlaylist,
  deletePlaylist,
  addTrackToPlaylist,
  removeTrackFromPlaylist,
}

@immutable
class CollectionsOutboxItem {
  const CollectionsOutboxItem({
    required this.id,
    required this.action,
    required this.createdAt,
    this.trackId,
    this.playlistId,
    this.playlistName,
  });

  final String id;
  final CollectionsOutboxAction action;
  final DateTime createdAt;
  final String? trackId;
  final String? playlistId;
  final String? playlistName;

  factory CollectionsOutboxItem.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final actionName = json['action'];
    final createdAt = json['createdAt'];
    if (id is! String ||
        id.trim().isEmpty ||
        actionName is! String ||
        createdAt is! String) {
      throw const FormatException('Invalid collections outbox item.');
    }

    final action = CollectionsOutboxAction.values.where(
      (value) => value.name == actionName,
    );
    final parsedCreatedAt = DateTime.tryParse(createdAt);
    if (action.isEmpty || parsedCreatedAt == null) {
      throw const FormatException('Invalid collections outbox item.');
    }

    return CollectionsOutboxItem(
      id: id.trim(),
      action: action.single,
      createdAt: parsedCreatedAt.toUtc(),
      trackId: _optionalString(json['trackId']),
      playlistId: _optionalString(json['playlistId']),
      playlistName: _optionalString(json['playlistName']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'action': action.name,
      'createdAt': createdAt.toUtc().toIso8601String(),
      if (trackId != null) 'trackId': trackId,
      if (playlistId != null) 'playlistId': playlistId,
      if (playlistName != null) 'playlistName': playlistName,
    };
  }

  CollectionsOutboxItem copyWith({
    String? playlistId,
  }) {
    return CollectionsOutboxItem(
      id: id,
      action: action,
      createdAt: createdAt,
      trackId: trackId,
      playlistId: playlistId ?? this.playlistId,
      playlistName: playlistName,
    );
  }
}

String? _optionalString(Object? value) {
  if (value is! String || value.trim().isEmpty) {
    return null;
  }
  return value.trim();
}
