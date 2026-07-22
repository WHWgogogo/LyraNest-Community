import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/track_list.dart';

final tracksApiProvider = Provider<TracksApi>((ref) {
  return TracksApi(ref.watch(dioProvider));
});

final tracksProvider = FutureProvider.autoDispose<TrackList>((ref) {
  return ref.watch(tracksApiProvider).fetchTracks();
});

class TracksApi {
  const TracksApi(this._dio);

  final Dio _dio;

  Future<TrackList> fetchTracks() async {
    try {
      final response = await _dio.get('/api/v1/tracks');
      return TrackList.fromJson(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
