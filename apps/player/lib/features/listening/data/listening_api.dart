import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/listening_event.dart';

const listeningEventsPath = '/api/v1/listening/events';

final listeningApiProvider = Provider<ListeningApi>((ref) {
  return DioListeningApi(ref.watch(dioProvider));
});

abstract interface class ListeningApi {
  Future<void> submitEvents(List<ListeningEvent> events);
}

class DioListeningApi implements ListeningApi {
  const DioListeningApi(this._dio);

  final Dio _dio;

  @override
  Future<void> submitEvents(List<ListeningEvent> events) async {
    if (events.isEmpty) {
      return;
    }
    if (events.length > 50) {
      throw ArgumentError.value(events.length, 'events', 'Must be at most 50.');
    }
    try {
      await _dio.post(
        listeningEventsPath,
        data: {
          'events': events.map((event) => event.toJson()).toList(),
        },
      );
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
