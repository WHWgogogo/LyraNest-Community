import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/listening_report.dart';

final listeningReportApiProvider = Provider<ListeningReportApi>((ref) {
  return ListeningReportApi(ref.watch(dioProvider));
});

final listeningReportProvider =
    FutureProvider.family<ListeningReport, int>((ref, year) {
  return ref.watch(listeningReportApiProvider).fetchReport(year: year);
});

class ListeningReportApi {
  const ListeningReportApi(this._dio);

  final Dio _dio;

  Future<ListeningReport> fetchReport({required int year}) async {
    if (year < 1000 || year > 9999) {
      throw ArgumentError.value(year, 'year', 'Must be a four-digit year.');
    }
    try {
      final response = await _dio.get(
        '/api/v1/listening/report',
        queryParameters: {'year': year},
      );
      return ListeningReport.fromJson(response.data, year: year);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
