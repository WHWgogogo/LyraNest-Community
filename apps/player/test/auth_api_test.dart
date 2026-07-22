import 'dart:convert';
import 'dart:typed_data';

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/config/server_config.dart';
import 'package:player/core/config/server_config_controller.dart';
import 'package:player/core/network/api_client.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/core/network/server_connection_validator.dart';
import 'package:player/features/auth/application/auth_controller.dart';
import 'package:player/features/auth/data/auth_api.dart';
import 'package:player/features/auth/data/auth_session_store.dart';
import 'package:player/features/auth/domain/auth_session.dart';
import 'package:player/features/auth/domain/auth_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('parses compatible status and token response fields', () {
    final status = AuthStatus.fromJson({
      'setup_complete': true,
      'is_authenticated': true,
      'user': {'username': 'admin'},
    });
    final result = AuthResult.fromJson({
      'session': {'token': 'session-token'},
      'user': {'username': 'owner'},
    }, username: 'fallback');

    expect(status.initialized, isTrue);
    expect(status.authenticated, isTrue);
    expect(status.username, 'admin');
    expect(result.token, 'session-token');
    expect(result.username, 'owner');
  });

  test('uses replaceable endpoint paths and skips stale authentication',
      () async {
    final adapter = _RecordingAdapter((options) {
      expect(options.path, '/custom/sign-in');
      expect(options.extra[skipAuthenticationExtraKey], isTrue);
      expect(options.data, {'username': 'admin', 'password': 'secret'});
      return {'access_token': 'token'};
    });
    final dio = Dio()..httpClientAdapter = adapter;
    final api = DioAuthApi(
      dio,
      paths: const AuthApiPaths(login: '/custom/sign-in'),
    );

    final result = await api.login(username: 'admin', password: 'secret');

    expect(result.token, 'token');
    expect(adapter.requests, hasLength(1));
  });

  test('persists and clears the session as one logical record', () async {
    SharedPreferences.setMockInitialValues({});
    const store = SharedPreferencesAuthSessionStore();
    final session = AuthSession(
      token: 'token',
      username: 'admin',
      serverBaseUrl: 'http://server.test',
      offlineCredential: 'offline-proof',
      lastOnlineValidatedAt: DateTime.utc(2026, 7, 20, 8, 30),
    );

    await store.write(session);
    final restored = await store.read();
    expect(restored?.token, 'token');
    expect(restored?.username, 'admin');
    expect(restored?.serverBaseUrl, 'http://server.test');
    expect(restored?.offlineCredential, 'offline-proof');
    expect(
      restored?.lastOnlineValidatedAt,
      DateTime.utc(2026, 7, 20, 8, 30),
    );

    await store.clear();
    expect(await store.read(), isNull);
  });

  test('adds bearer token and clears the session after a 401', () async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://server.test',
    });
    final store = _MemorySessionStore(
      const AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://server.test',
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(serverConfigControllerProvider.future);
    final adapter = _RecordingAdapter(
      (options) => {'error': 'unauthorized'},
      statusCode: 401,
    );
    final dio = container.read(dioProvider)..httpClientAdapter = adapter;

    await expectLater(dio.get('/private'), throwsA(isA<DioException>()));

    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer saved-token',
    );
    expect(store.session, isNull);
    expect(container.read(unauthorizedGenerationProvider), 1);
  });

  test('uses one session across the configured internal and external URLs',
      () async {
    const internal = 'http://192.168.1.20:8080';
    const external = 'https://music.example.test';
    final identity = serverIdentityForUrls([internal, external]);
    SharedPreferences.setMockInitialValues({
      'server_base_url': external,
      'server_internal_base_url': internal,
      'server_external_base_url': external,
      'server_active_base_url': external,
      'server_identity': identity,
    });
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: internal,
        serverScopeId: identity,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
      ],
    );
    addTearDown(container.dispose);
    await container.read(serverConfigControllerProvider.future);
    final adapter = _RecordingAdapter((options) => {'ok': true});
    final dio = container.read(dioProvider)..httpClientAdapter = adapter;

    await dio.get('/private');

    expect(
      adapter.requests.single.headers['Authorization'],
      'Bearer saved-token',
    );
  });

  test('restores a verified session when the server is unreachable', () async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://server.test',
    });
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://server.test',
        offlineCredential: 'offline-proof',
        lastOnlineValidatedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(_OfflineAuthApi()),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(authControllerProvider.future);

    expect(state.isOfflineAuthenticated, isTrue);
    expect(state.session?.username, 'admin');
    expect(store.session, isNotNull);
  });

  test('successful authenticated request restores an offline session online',
      () async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://server.test',
    });
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://server.test',
        offlineCredential: 'offline-proof',
        lastOnlineValidatedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(_OfflineAuthApi()),
      ],
    );
    addTearDown(container.dispose);

    final offlineState = await container.read(authControllerProvider.future);
    expect(offlineState.isOfflineAuthenticated, isTrue);

    final dio = container.read(dioProvider)
      ..httpClientAdapter = _RecordingAdapter((options) => {'ok': true});
    await dio.get('/api/v1/tracks');
    await _waitFor(
      () =>
          container.read(authControllerProvider).valueOrNull!.connectionState ==
          AuthConnectionState.online,
    );

    expect(store.session?.lastOnlineValidatedAt, isNotNull);
  });

  test('clears a cached session only after an explicit 401', () async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://server.test',
    });
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://server.test',
        offlineCredential: 'offline-proof',
        lastOnlineValidatedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(_UnauthorizedCurrentUserAuthApi()),
      ],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await _waitFor(() =>
        !container.read(authControllerProvider).valueOrNull!.isAuthenticated);

    expect(store.session, isNull);
  });

  test('restores cached credentials before the background probe completes',
      () async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://server.test',
    });
    final pendingApi = _PendingAuthApi();
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://server.test',
        offlineCredential: 'offline-proof',
        lastOnlineValidatedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final container = ProviderContainer(
      overrides: [
        authSessionStoreProvider.overrideWithValue(store),
        authApiProvider.overrideWithValue(pendingApi),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(authControllerProvider.future);

    expect(state.isOfflineAuthenticated, isTrue);
    expect(pendingApi.fetchStatusCalls, 1);
    pendingApi.completeWithNetworkFailure();
  });

  test('keeps an authenticated session while saving reachable addresses',
      () async {
    const internal = 'http://192.168.1.20:8080';
    const external = 'https://music.example.test';
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://saved.example.test',
    });
    final authApi = _AuthenticatedAuthApi();
    final store = _MemorySessionStore(
      AuthSession(
        token: 'saved-token',
        username: 'admin',
        serverBaseUrl: 'http://saved.example.test',
        offlineCredential: 'offline-proof',
        lastOnlineValidatedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final validator = _SuccessfulServerConnectionValidator();
    final container = ProviderContainer(
      overrides: [
        authApiProvider.overrideWithValue(authApi),
        authSessionStoreProvider.overrideWithValue(store),
        serverConnectionValidatorProvider.overrideWithValue(validator),
      ],
    );
    addTearDown(container.dispose);

    final signedIn = await container.read(authControllerProvider.future);
    expect(signedIn.isAuthenticated, isTrue);
    final statusChecksBeforeSave = authApi.fetchStatusCalls;

    await container
        .read(authControllerProvider.notifier)
        .configureServerAddresses(
          internalBaseUrl: internal,
          externalBaseUrl: external,
        );

    final savedState = container.read(authControllerProvider).requireValue;
    expect(savedState.isAuthenticated, isTrue);
    expect(savedState.session?.token, 'saved-token');
    expect(savedState.session?.serverBaseUrl, internal);
    expect(savedState.session?.serverScopeId, isNotEmpty);
    expect(authApi.fetchStatusCalls, statusChecksBeforeSave);
    expect(
      validator.candidates,
      containsAll([internal, external]),
    );
  });
}

Future<void> _waitFor(bool Function() predicate) async {
  for (var attempt = 0; attempt < 20; attempt++) {
    if (predicate()) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError('Timed out waiting for auth state.');
}

class _RecordingAdapter implements HttpClientAdapter {
  _RecordingAdapter(this.response, {this.statusCode = 200});

  final Object Function(RequestOptions options) response;
  final int statusCode;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(response(options)),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _MemorySessionStore implements AuthSessionStore {
  _MemorySessionStore(this.session);

  AuthSession? session;

  @override
  Future<void> clear() async {
    session = null;
  }

  @override
  Future<AuthSession?> read() async => session;

  @override
  Future<void> write(AuthSession session) async {
    this.session = session;
  }
}

class _OfflineAuthApi implements AuthApi {
  @override
  Future<AuthStatus> fetchStatus() {
    throw const ApiError('Network unavailable');
  }

  @override
  Future<String> fetchCurrentUsername() => throw UnimplementedError();

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();
}

class _UnauthorizedCurrentUserAuthApi implements AuthApi {
  @override
  Future<AuthStatus> fetchStatus() async {
    return const AuthStatus(initialized: true);
  }

  @override
  Future<String> fetchCurrentUsername() {
    throw const ApiError('Unauthorized', statusCode: 401);
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();
}

class _PendingAuthApi implements AuthApi {
  final Completer<AuthStatus> _status = Completer<AuthStatus>();
  var fetchStatusCalls = 0;

  @override
  Future<AuthStatus> fetchStatus() {
    fetchStatusCalls++;
    return _status.future;
  }

  void completeWithNetworkFailure() {
    _status.completeError(const ApiError('Network unavailable'));
  }

  @override
  Future<String> fetchCurrentUsername() => throw UnimplementedError();

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> logout() => throw UnimplementedError();

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) =>
      throw UnimplementedError();
}

class _AuthenticatedAuthApi implements AuthApi {
  var fetchStatusCalls = 0;

  @override
  Future<AuthStatus> fetchStatus() async {
    fetchStatusCalls++;
    return const AuthStatus(
      initialized: true,
      authenticated: true,
      username: 'admin',
    );
  }

  @override
  Future<String> fetchCurrentUsername() {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> logout() {
    throw UnimplementedError();
  }

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }
}

class _SuccessfulServerConnectionValidator
    implements ServerConnectionValidator {
  final List<String> candidates = [];

  @override
  Future<void> validate(String baseUrl) async {
    candidates.add(baseUrl);
  }
}
