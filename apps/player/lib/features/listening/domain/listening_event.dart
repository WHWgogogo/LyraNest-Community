import 'package:flutter/foundation.dart';

@immutable
class ListeningEvent {
  const ListeningEvent({
    required this.eventId,
    required this.trackId,
    required this.listenedMs,
    required this.completed,
    required this.playedAt,
  });

  final String eventId;
  final String trackId;
  final int listenedMs;
  final bool completed;
  final DateTime playedAt;

  Map<String, Object> toJson() {
    return {
      'event_id': eventId,
      'track_id': trackId,
      'listened_ms': listenedMs,
      'completed': completed,
      'played_at': playedAt.toUtc().toIso8601String(),
    };
  }

  factory ListeningEvent.fromJson(Map<String, Object?> json) {
    final playedAt = DateTime.tryParse(json['played_at'] as String? ?? '');
    return ListeningEvent(
      eventId: json['event_id'] as String? ?? '',
      trackId: json['track_id'] as String? ?? '',
      listenedMs: (json['listened_ms'] as num?)?.toInt() ?? 0,
      completed: json['completed'] == true,
      playedAt: playedAt?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}
