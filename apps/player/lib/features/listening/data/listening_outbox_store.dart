import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/listening_event.dart';

const _legacyListeningOutboxKey = 'listening_event_outbox.v1';
const _listeningOutboxKeyPrefix = 'listening_event_outbox.v2';

abstract interface class ListeningOutboxStore {
  Future<List<ListeningEvent>> read({int limit = 50});

  Future<void> enqueue(ListeningEvent event);

  Future<void> removeByIds(Set<String> eventIds);
}

class ListeningOutboxScope {
  ListeningOutboxScope({
    required String serverBaseUrl,
    required String userId,
  })  : serverBaseUrl = normalizeListeningOutboxServerUrl(serverBaseUrl),
        userId = _requiredValue(userId, 'userId');

  final String serverBaseUrl;
  final String userId;

  String get storageKey {
    final identity = jsonEncode({
      'serverBaseUrl': serverBaseUrl,
      'userId': userId,
    });
    return '$_listeningOutboxKeyPrefix.'
        '${sha256.convert(utf8.encode(identity))}';
  }

  @override
  bool operator ==(Object other) {
    return other is ListeningOutboxScope &&
        other.serverBaseUrl == serverBaseUrl &&
        other.userId == userId;
  }

  @override
  int get hashCode => Object.hash(serverBaseUrl, userId);
}

class SharedPreferencesListeningOutboxStore implements ListeningOutboxStore {
  SharedPreferencesListeningOutboxStore({
    required String serverBaseUrl,
    required String userId,
    Future<SharedPreferences>? preferences,
  })  : _scope = ListeningOutboxScope(
          serverBaseUrl: serverBaseUrl,
          userId: userId,
        ),
        _preferences = preferences ?? SharedPreferences.getInstance();

  final ListeningOutboxScope _scope;
  final Future<SharedPreferences> _preferences;

  @override
  Future<List<ListeningEvent>> read({int limit = 50}) async {
    if (limit <= 0) {
      return const [];
    }
    final events = await _readAll();
    return List.unmodifiable(events.take(limit));
  }

  @override
  Future<void> enqueue(ListeningEvent event) async {
    final events = await _readAll();
    if (events.any((item) => item.eventId == event.eventId)) {
      return;
    }
    events.add(event);
    await _writeAll(events);
  }

  @override
  Future<void> removeByIds(Set<String> eventIds) async {
    if (eventIds.isEmpty) {
      return;
    }
    final events = await _readAll();
    await _writeAll(
      events.where((event) => !eventIds.contains(event.eventId)).toList(),
    );
  }

  Future<List<ListeningEvent>> _readAll() async {
    final preferences = await _preferences;
    final raw = preferences.getString(_scope.storageKey);
    if (raw != null) {
      return _decodeEvents(raw) ?? [];
    }

    final legacyRaw = preferences.getString(_legacyListeningOutboxKey);
    if (legacyRaw == null) {
      return [];
    }

    final legacyEvents = _decodeEvents(legacyRaw);
    if (legacyEvents == null) {
      return [];
    }

    await _writeEvents(preferences, legacyEvents);
    await preferences.remove(_legacyListeningOutboxKey);
    return legacyEvents;
  }

  Future<void> _writeAll(List<ListeningEvent> events) async {
    final preferences = await _preferences;
    await _writeEvents(preferences, events);
  }

  Future<void> _writeEvents(
    SharedPreferences preferences,
    List<ListeningEvent> events,
  ) async {
    await preferences.setString(
      _scope.storageKey,
      jsonEncode(events.map((event) => event.toJson()).toList()),
    );
  }
}

List<ListeningEvent>? _decodeEvents(String raw) {
  if (raw.isEmpty) {
    return [];
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List<Object?>) {
      return null;
    }

    final events = <ListeningEvent>[];
    for (final value in decoded.whereType<Map<Object?, Object?>>()) {
      try {
        final event = ListeningEvent.fromJson(
          value.cast<String, Object?>(),
        );
        if (event.eventId.isNotEmpty &&
            event.trackId.isNotEmpty &&
            event.listenedMs >= 0) {
          events.add(event);
        }
      } catch (_) {
        continue;
      }
    }
    return events;
  } catch (_) {
    return null;
  }
}

String normalizeListeningOutboxServerUrl(String value) {
  final parsed = Uri.tryParse(value.trim());
  final scheme = parsed?.scheme.toLowerCase();
  if (parsed == null ||
      (scheme != 'http' && scheme != 'https') ||
      parsed.host.isEmpty) {
    throw ArgumentError.value(
      value,
      'serverBaseUrl',
      'Must be an http(s) URL with a host.',
    );
  }

  final port = parsed.hasPort &&
          !((scheme == 'http' && parsed.port == 80) ||
              (scheme == 'https' && parsed.port == 443))
      ? parsed.port
      : null;
  var path = parsed.path;
  while (path.endsWith('/')) {
    path = path.substring(0, path.length - 1);
  }

  return Uri(
    scheme: scheme,
    userInfo: parsed.userInfo,
    host: parsed.host.toLowerCase(),
    port: port ?? 0,
    path: path,
  ).toString();
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}
