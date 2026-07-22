import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';

@immutable
class AuthApiPaths {
  const AuthApiPaths({
    this.status = '/api/v1/auth/setup',
    this.login = '/api/v1/auth/login',
    this.registerAdmin = '/api/v1/auth/register',
    this.currentUser = '/api/v1/auth/me',
    this.logout = '/api/v1/auth/logout',
  });

  final String status;
  final String login;
  final String registerAdmin;
  final String currentUser;
  final String logout;
}

final authApiPathsProvider = Provider<AuthApiPaths>((ref) {
  return const AuthApiPaths();
});

final authApiProvider = Provider<AuthApi>((ref) {
  return DioAuthApi(
    ref.watch(dioProvider),
    paths: ref.watch(authApiPathsProvider),
  );
});

@immutable
class AuthStatus {
  const AuthStatus({
    required this.initialized,
    this.authenticated = false,
    this.username,
  });

  final bool initialized;
  final bool authenticated;
  final String? username;

  factory AuthStatus.fromJson(Object? data) {
    if (data is! Map) {
      throw const ApiError(
        '\u670d\u52a1\u5668\u8fd4\u56de\u4e86\u65e0\u6548\u7684\u521d\u59cb\u5316\u72b6\u6001',
      );
    }

    final initialized = data['initialized'] ??
        data['is_initialized'] ??
        data['setup_complete'] ??
        data['configured'];
    if (initialized is! bool) {
      throw const ApiError(
        '\u670d\u52a1\u5668\u8fd4\u56de\u4e86\u65e0\u6548\u7684\u521d\u59cb\u5316\u72b6\u6001',
      );
    }

    final authenticatedValue =
        data['authenticated'] ?? data['is_authenticated'];
    return AuthStatus(
      initialized: initialized,
      authenticated: authenticatedValue is bool ? authenticatedValue : false,
      username: _readUsername(data),
    );
  }
}

@immutable
class AuthResult {
  const AuthResult({required this.token, required this.username});

  final String token;
  final String username;

  factory AuthResult.fromJson(Object? data, {required String username}) {
    if (data is! Map) {
      throw const ApiError(
        '\u670d\u52a1\u5668\u8fd4\u56de\u4e86\u65e0\u6548\u7684\u767b\u5f55\u4f1a\u8bdd',
      );
    }

    final session = data['session'];
    final tokenValue = data['token'] ??
        data['access_token'] ??
        data['session_token'] ??
        (session is Map ? session['token'] : null);
    if (tokenValue is! String || tokenValue.trim().isEmpty) {
      throw const ApiError(
        '\u670d\u52a1\u5668\u672a\u8fd4\u56de\u767b\u5f55\u4ee4\u724c',
      );
    }

    final responseUsername = _readUsername(data);
    return AuthResult(
      token: tokenValue.trim(),
      username: responseUsername?.trim().isNotEmpty == true
          ? responseUsername!.trim()
          : username,
    );
  }
}

abstract interface class AuthApi {
  Future<AuthStatus> fetchStatus();

  Future<AuthResult> login({
    required String username,
    required String password,
  });

  Future<void> registerAdmin({
    required String username,
    required String password,
  });

  Future<String> fetchCurrentUsername();

  Future<void> logout();
}

class DioAuthApi implements AuthApi {
  const DioAuthApi(this._dio, {required this.paths});

  final Dio _dio;
  final AuthApiPaths paths;

  @override
  Future<AuthStatus> fetchStatus() async {
    try {
      final response = await _dio.get(
        paths.status,
        options: Options(extra: {skipAuthenticationExtraKey: true}),
      );
      return AuthStatus.fromJson(response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) {
    return _submitCredentials(
      paths.login,
      username: username,
      password: password,
    );
  }

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) async {
    try {
      await _dio.post(
        paths.registerAdmin,
        data: {
          'username': username,
          'password': password,
        },
        options: Options(extra: {skipAuthenticationExtraKey: true}),
      );
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<String> fetchCurrentUsername() async {
    try {
      final response = await _dio.get(paths.currentUser);
      final username =
          response.data is Map ? _readUsername(response.data as Map) : null;
      if (username == null || username.trim().isEmpty) {
        throw const ApiError(
          '\u670d\u52a1\u5668\u8fd4\u56de\u4e86\u65e0\u6548\u7684\u7528\u6237\u4fe1\u606f',
        );
      }
      return username.trim();
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  @override
  Future<void> logout() async {
    try {
      await _dio.post(paths.logout);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }

  Future<AuthResult> _submitCredentials(
    String path, {
    required String username,
    required String password,
  }) async {
    try {
      final response = await _dio.post(
        path,
        data: {
          'username': username,
          'password': password,
        },
        options: Options(extra: {skipAuthenticationExtraKey: true}),
      );
      return AuthResult.fromJson(response.data, username: username);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}

String? _readUsername(Map data) {
  final direct = data['username'];
  if (direct is String) {
    return direct;
  }

  final user = data['user'];
  if (user is Map && user['username'] is String) {
    return user['username'] as String;
  }
  return null;
}
