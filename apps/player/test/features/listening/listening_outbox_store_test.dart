import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/listening/data/listening_outbox_store.dart';
import 'package:player/features/listening/domain/listening_event.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late SharedPreferences preferences;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });

  test('shares a scope between equivalent normalized server addresses',
      () async {
    final firstStore = _store(
      preferences: preferences,
      serverBaseUrl:
          'HTTPS://MUSIC.example.test:443/library/?temporary=true#fragment',
    );
    final equivalentStore = _store(
      preferences: preferences,
      serverBaseUrl: 'https://music.example.test/library',
    );

    await firstStore.enqueue(_event('event-1'));

    expect(
      (await equivalentStore.read()).map((event) => event.eventId),
      ['event-1'],
    );
  });

  test('isolates events by both server address and user identity', () async {
    final aliceOnPrimary = _store(
      preferences: preferences,
      serverBaseUrl: 'https://music.example.test',
      userId: 'alice',
    );
    final bobOnPrimary = _store(
      preferences: preferences,
      serverBaseUrl: 'https://music.example.test',
      userId: 'bob',
    );
    final aliceOnSecondary = _store(
      preferences: preferences,
      serverBaseUrl: 'https://backup.example.test',
      userId: 'alice',
    );

    await aliceOnPrimary.enqueue(_event('alice-event'));
    await bobOnPrimary.enqueue(_event('bob-event'));
    await aliceOnSecondary.enqueue(_event('backup-event'));

    expect(
      (await aliceOnPrimary.read()).map((event) => event.eventId),
      ['alice-event'],
    );
    expect(
      (await bobOnPrimary.read()).map((event) => event.eventId),
      ['bob-event'],
    );
    expect(
      (await aliceOnSecondary.read()).map((event) => event.eventId),
      ['backup-event'],
    );
  });

  test('migrates the legacy outbox into the first scoped store that opens it',
      () async {
    final legacyEvent = _event('legacy-event');
    SharedPreferences.setMockInitialValues({
      'listening_event_outbox.v1': jsonEncode([legacyEvent.toJson()]),
    });
    preferences = await SharedPreferences.getInstance();
    final currentStore = _store(
      preferences: preferences,
      serverBaseUrl: 'https://music.example.test',
      userId: 'alice',
    );
    final otherStore = _store(
      preferences: preferences,
      serverBaseUrl: 'https://music.example.test',
      userId: 'bob',
    );

    expect(
      (await currentStore.read()).map((event) => event.eventId),
      [legacyEvent.eventId],
    );
    expect(preferences.containsKey('listening_event_outbox.v1'), isFalse);
    expect(await otherStore.read(), isEmpty);
  });
}

SharedPreferencesListeningOutboxStore _store({
  required SharedPreferences preferences,
  String serverBaseUrl = 'https://music.example.test',
  String userId = 'alice',
}) {
  return SharedPreferencesListeningOutboxStore(
    serverBaseUrl: serverBaseUrl,
    userId: userId,
    preferences: Future.value(preferences),
  );
}

ListeningEvent _event(String eventId) {
  return ListeningEvent(
    eventId: eventId,
    trackId: 'track-1',
    listenedMs: 1200,
    completed: false,
    playedAt: DateTime.utc(2026, 7, 20),
  );
}
