import 'package:dio/dio.dart';

import '../application/offline_supplemental_resource_fetcher.dart';
import '../domain/offline_supplemental_resources.dart';

class DioOfflineSupplementalResourceFetcher
    implements OfflineSupplementalResourceFetcher {
  const DioOfflineSupplementalResourceFetcher(this._dio);

  final Dio _dio;

  @override
  Future<OfflineArtwork?> fetchArtwork(String trackId) async {
    try {
      final response = await _dio.get<List<int>>(
        _trackResourcePath(trackId, 'artwork'),
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        return null;
      }
      return OfflineArtwork(
        bytes: bytes,
        contentType: response.headers.value(Headers.contentTypeHeader),
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<OfflineCachedLyrics?> fetchLyrics(String trackId) async {
    try {
      final response = await _dio.get<Object>(
        _trackResourcePath(trackId, 'lyrics'),
      );
      final data = response.data;
      if (data is! Map<Object?, Object?>) {
        return null;
      }
      final content = data['content'];
      if (content is! String || content.trim().isEmpty) {
        return null;
      }
      return OfflineCachedLyrics(
        path: data['path'] as String?,
        encoding: data['encoding'] as String?,
        content: content,
      );
    } on DioException catch (error) {
      if (error.response?.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }
}

String _trackResourcePath(String trackId, String resource) {
  return '/api/v1/tracks/${Uri.encodeComponent(trackId)}/$resource';
}
