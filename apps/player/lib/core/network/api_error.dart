import 'package:dio/dio.dart';

class ApiError implements Exception {
  const ApiError(this.message, {this.statusCode});

  static const networkRequestFailedMessage = 'Network request failed';

  final String message;
  final int? statusCode;

  factory ApiError.fromObject(Object error) {
    if (error is DioException) {
      return ApiError.fromDioException(error);
    }
    if (error is ApiError) {
      return error;
    }
    return ApiError(error.toString());
  }

  factory ApiError.fromDioException(DioException error) {
    final statusCode = error.response?.statusCode;
    final data = error.response?.data;
    final message = switch (data) {
      {'message': final String message} => message,
      {'error': final String message} => message,
      _ => error.message ?? networkRequestFailedMessage,
    };

    return ApiError(message, statusCode: statusCode);
  }

  @override
  String toString() {
    if (statusCode == null) {
      return message;
    }
    return '$message ($statusCode)';
  }
}
