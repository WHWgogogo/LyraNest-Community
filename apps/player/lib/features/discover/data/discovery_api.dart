import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../domain/discovery_data.dart';

final discoveryApiProvider = Provider<DiscoveryApi>((ref) {
  return DiscoveryApi(ref.watch(dioProvider));
});

final discoveryProvider = FutureProvider<DiscoveryData>((ref) {
  return ref.watch(discoveryApiProvider).fetchDiscovery();
});

class DiscoveryApi {
  const DiscoveryApi(this._dio);

  final Dio _dio;

  Future<DiscoveryData> fetchDiscovery() async {
    try {
      final response = await _dio.get('/api/v1/discovery');
      return DiscoveryData.fromJson(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
