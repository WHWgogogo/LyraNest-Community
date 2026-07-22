import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracks/domain/track.dart';

const playerQueuePreferencesKey = 'player.queue.v1';

final queueRepositoryProvider = Provider<QueueRepository>((ref) {
  return SharedPreferencesQueueRepository();
});

abstract interface class QueueRepository {
  Future<List<Track>> loadQueue();

  Future<void> saveQueue(Iterable<Track> queue);

  Future<void> clearQueue();
}

class SharedPreferencesQueueRepository implements QueueRepository {
  SharedPreferencesQueueRepository({
    Future<SharedPreferences>? preferences,
    this.preferencesKey = playerQueuePreferencesKey,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;
  final String preferencesKey;

  @override
  Future<List<Track>> loadQueue() async {
    final preferences = await _preferences;
    final encodedQueue = preferences.getString(preferencesKey);
    if (encodedQueue == null || encodedQueue.trim().isEmpty) {
      return const [];
    }

    try {
      final decodedQueue = jsonDecode(encodedQueue);
      if (decodedQueue is! List) {
        return const [];
      }

      final queue = <Track>[];
      for (final value in decodedQueue) {
        if (value is! Map) {
          continue;
        }
        final json = Map<String, dynamic>.from(value);
        final id = json['id'];
        if (id == null || id.toString().trim().isEmpty) {
          continue;
        }
        queue.add(Track.fromJson(json));
      }
      return List.unmodifiable(queue);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> saveQueue(Iterable<Track> queue) async {
    final preferences = await _preferences;
    await preferences.setString(
      preferencesKey,
      jsonEncode(queue.map(_trackToJson).toList(growable: false)),
    );
  }

  @override
  Future<void> clearQueue() async {
    final preferences = await _preferences;
    await preferences.remove(preferencesKey);
  }
}

Map<String, dynamic> _trackToJson(Track track) {
  return {
    'id': track.id,
    'title': track.title,
    if (track.artist != null) 'artist': track.artist,
    if (track.album != null) 'album': track.album,
    'genres': track.genres,
    if (track.durationSeconds != null) 'durationSeconds': track.durationSeconds,
    if (track.streamUrl != null) 'streamUrl': track.streamUrl,
  };
}
