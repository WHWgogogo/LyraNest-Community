import 'dart:typed_data';

import 'package:dio/dio.dart';

class OfflineHttpResponse {
  OfflineHttpResponse({
    required this.statusCode,
    required Map<String, String> headers,
    required this.body,
  }) : headers = Map.unmodifiable(
          {
            for (final entry in headers.entries)
              entry.key.toLowerCase(): entry.value,
          },
        );

  final int statusCode;
  final Map<String, String> headers;
  final Stream<List<int>> body;

  String? header(String name) => headers[name.toLowerCase()];
}

abstract interface class OfflineDownloadTransport {
  Future<OfflineHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  });
}

class DioOfflineDownloadTransport implements OfflineDownloadTransport {
  const DioOfflineDownloadTransport(this._dio);

  final Dio _dio;

  @override
  Future<OfflineHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _dio.getUri<ResponseBody>(
      uri,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    final body = response.data;
    if (body == null || response.statusCode == null) {
      throw StateError('Media response did not include a body.');
    }

    return OfflineHttpResponse(
      statusCode: response.statusCode!,
      headers: {
        for (final entry in response.headers.map.entries)
          entry.key: entry.value.join(','),
      },
      body: body.stream.map<List<int>>(
        (Uint8List chunk) => List<int>.unmodifiable(chunk),
      ),
    );
  }
}
