import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/scrape_models.dart';

final scrapeApiProvider = Provider<ScrapeApi>((ref) {
  return DioScrapeApi(ref.watch(dioProvider));
});

final scrapeSearchProvider =
    FutureProvider.autoDispose.family<ScrapeSearchResult, ScrapeSearchRequest>(
  (ref, request) {
    return ref.watch(scrapeApiProvider).search(
          request.trackId,
          query: request.query,
        );
  },
);

abstract interface class ScrapeApi {
  Future<ScrapeSearchResult> search(
    String trackId, {
    ScrapeSearchQuery query = const ScrapeSearchQuery(),
  });

  Future<ScrapeApplyResult> apply({
    required String trackId,
    required String candidateId,
    required String provider,
    required List<ScrapeField> fields,
  });
}

class DioScrapeApi implements ScrapeApi {
  const DioScrapeApi(this._dio);

  final Dio _dio;

  @override
  Future<ScrapeSearchResult> search(
    String trackId, {
    ScrapeSearchQuery query = const ScrapeSearchQuery(),
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/tracks/${Uri.encodeComponent(trackId)}/scrape/search',
        data: query.toJson(),
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return ScrapeSearchResult.fromJson(trackId, response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<ScrapeApplyResult> apply({
    required String trackId,
    required String candidateId,
    required String provider,
    required List<ScrapeField> fields,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/tracks/${Uri.encodeComponent(trackId)}/scrape/apply',
        data: {
          'candidate_id': candidateId,
          'provider': provider,
          'fields': fields.map((field) => field.apiName).toList(),
        },
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return ScrapeApplyResult.fromJson(
        response.data,
        trackId: trackId,
        provider: provider,
        requestedFields: fields,
      );
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
