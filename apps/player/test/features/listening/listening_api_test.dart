import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/listening/data/listening_api.dart';
import 'package:player/features/listening/domain/listening_event.dart';

void main() {
  test('wraps server listening events in an events batch', () async {
    final adapter = _ListeningAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    final api = DioListeningApi(dio);

    await api.submitEvents([
      ListeningEvent(
        eventId: 'event-1',
        trackId: 'track-1',
        listenedMs: 1250,
        completed: true,
        playedAt: DateTime.utc(2026, 7, 20, 8, 30),
      ),
    ]);

    expect(adapter.request?.method, 'POST');
    expect(adapter.request?.path, listeningEventsPath);
    expect(adapter.request?.data, {
      'events': [
        {
          'event_id': 'event-1',
          'track_id': 'track-1',
          'listened_ms': 1250,
          'completed': true,
          'played_at': '2026-07-20T08:30:00.000Z',
        },
      ],
    });
  });
}

class _ListeningAdapter implements HttpClientAdapter {
  RequestOptions? request;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    request = options;
    return ResponseBody.fromString(
      jsonEncode({'accepted': 1, 'duplicates': 0}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
