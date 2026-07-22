import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/library_scan_result.dart';
import '../domain/library_status.dart';

final libraryManagementApiProvider = Provider<LibraryManagementApi>((ref) {
  return DioLibraryManagementApi(ref.watch(dioProvider));
});

final libraryStatusProvider = FutureProvider.autoDispose<LibraryStatus>((ref) {
  return ref.watch(libraryManagementApiProvider).fetchStatus();
});

abstract interface class LibraryManagementApi {
  Future<LibraryStatus> fetchStatus();

  Future<LibraryScanResult> scanLibrary();
}

class DioLibraryManagementApi implements LibraryManagementApi {
  const DioLibraryManagementApi(this._dio);

  final Dio _dio;

  @override
  Future<LibraryStatus> fetchStatus() async {
    try {
      final response = await _dio.get('/api/v1/library/status');
      return LibraryStatus.fromJson(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<LibraryScanResult> scanLibrary() async {
    try {
      final response = await _dio.post(
        '/api/v1/library/scan',
        options: Options(
          receiveTimeout: const Duration(minutes: 2),
        ),
      );
      return LibraryScanResult.fromJson(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
