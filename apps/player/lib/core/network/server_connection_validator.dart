import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_error.dart';

final serverConnectionValidatorProvider =
    Provider<ServerConnectionValidator>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(milliseconds: 1500),
      receiveTimeout: const Duration(milliseconds: 2500),
      responseType: ResponseType.json,
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return DioServerConnectionValidator(dio);
});

abstract interface class ServerConnectionValidator {
  Future<void> validate(String baseUrl);
}

/// Probes every candidate concurrently and returns as soon as one is healthy.
///
/// Failures are intentionally isolated: a private LAN address timing out must
/// not delay selecting a reachable public address.
Future<String?> selectHealthyServerUrl(
  ServerConnectionValidator validator,
  Iterable<String> candidateUrls,
) async {
  final candidates = <String>[];
  for (final url in candidateUrls) {
    if (!candidates.contains(url)) {
      candidates.add(url);
    }
  }
  if (candidates.isEmpty) {
    return null;
  }

  final result = Completer<String?>();
  var remaining = candidates.length;
  for (final url in candidates) {
    () async {
      try {
        await validator.validate(url);
        if (!result.isCompleted) {
          result.complete(url);
        }
      } catch (_) {
        // Probe all configured addresses before reporting that none work.
      } finally {
        remaining--;
        if (remaining == 0 && !result.isCompleted) {
          result.complete(null);
        }
      }
    }();
  }
  return result.future;
}

class DioServerConnectionValidator implements ServerConnectionValidator {
  const DioServerConnectionValidator(this._dio);

  final Dio _dio;

  @override
  Future<void> validate(String baseUrl) async {
    final healthUrl = Uri.parse(baseUrl).resolve('/healthz');
    final Response<Object?> response;

    try {
      response = await _dio.getUri<Object?>(healthUrl);
    } catch (error) {
      throw ApiError.fromObject(error);
    }

    final data = response.data;
    if (data is! Map) {
      throw const ServerHealthCheckException.invalidResponse();
    }

    if (!data.containsKey('status')) {
      throw const ServerHealthCheckException.invalidResponse();
    }

    final status = data['status'];
    if (status != 'ok') {
      throw ServerHealthCheckException.unexpectedStatus(status);
    }
  }
}

enum ServerHealthCheckFailure {
  invalidResponse,
  unexpectedStatus,
}

class ServerHealthCheckException implements Exception {
  const ServerHealthCheckException.invalidResponse()
      : failure = ServerHealthCheckFailure.invalidResponse,
        status = null;

  const ServerHealthCheckException.unexpectedStatus(this.status)
      : failure = ServerHealthCheckFailure.unexpectedStatus;

  final ServerHealthCheckFailure failure;
  final Object? status;
}
