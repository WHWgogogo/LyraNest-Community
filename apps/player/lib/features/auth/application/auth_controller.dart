import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/server_config.dart';
import '../../../core/config/server_config_controller.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../data/auth_api.dart';
import '../data/auth_session_store.dart';
import '../domain/auth_session.dart';
import '../domain/auth_state.dart';

final authControllerProvider =
    AsyncNotifierProvider<AuthController, AuthState>(AuthController.new);

class AuthController extends AsyncNotifier<AuthState> {
  @override
  Future<AuthState> build() async {
    ref.listen<int>(unauthorizedGenerationProvider, (previous, next) {
      if (previous != null && next > previous) {
        _handleUnauthorized();
      }
    });
    ref.listen<int>(authenticatedRequestGenerationProvider, (previous, next) {
      if (previous != null && next > previous) {
        _handleAuthenticatedRequestSucceeded();
      }
    });

    final config = await ref.read(serverConfigControllerProvider.future);
    final store = ref.read(authSessionStoreProvider);
    final session = await _sessionForConfig(
      store: store,
      config: config,
      session: await store.read(),
    );
    if (session != null && session.canAuthenticateOffline) {
      unawaited(_verifyCachedSession(config, session));
      return AuthState.signedIn(
        serverInitialized: true,
        session: session,
        connectionState: AuthConnectionState.offline,
      );
    }

    return _loadOnlineAuthState(config: config, session: session);
  }

  Future<AuthState> _loadOnlineAuthState({
    required ServerConfig config,
    required AuthSession? session,
  }) async {
    final store = ref.read(authSessionStoreProvider);
    try {
      final status = await ref.read(authApiProvider).fetchStatus();
      if (!status.initialized || session == null) {
        return AuthState.signedOut(serverInitialized: status.initialized);
      }

      final username = status.authenticated && status.username != null
          ? status.username!.trim()
          : await ref.read(authApiProvider).fetchCurrentUsername();
      final verifiedSession = AuthSession(
        token: session.token,
        username: username,
        serverBaseUrl: config.baseUrl,
        serverScopeId: config.cacheScopeId,
        offlineCredential: _offlineCredentialFor(session),
        lastOnlineValidatedAt: DateTime.now().toUtc(),
      );
      await store.write(verifiedSession);
      return AuthState.signedIn(
        serverInitialized: true,
        session: verifiedSession,
      );
    } on ApiError catch (error) {
      if (error.statusCode == 401) {
        await store.clear();
        return const AuthState.signedOut(serverInitialized: true);
      }
      if (error.statusCode == null &&
          session != null &&
          session.canAuthenticateOffline) {
        return AuthState.signedIn(
          serverInitialized: true,
          session: session,
          connectionState: AuthConnectionState.offline,
        );
      }
      rethrow;
    }
  }

  Future<void> configureServer(String value) async {
    final oldConfig = await ref.read(serverConfigControllerProvider.future);
    await ref.read(serverConfigControllerProvider.notifier).setBaseUrl(value);
    final newConfig = await ref.read(serverConfigControllerProvider.future);
    if (oldConfig.cacheScopeId != newConfig.cacheScopeId) {
      await ref.read(authSessionStoreProvider).clear();
    } else {
      final store = ref.read(authSessionStoreProvider);
      final session = await _sessionForConfig(
        store: store,
        config: newConfig,
        session: await store.read(),
      );
      if (session != null && session.canAuthenticateOffline) {
        state = AsyncData(
          AuthState.signedIn(
            serverInitialized: true,
            session: session,
            connectionState: AuthConnectionState.offline,
          ),
        );
        unawaited(_verifyCachedSession(newConfig, session));
        return;
      }
    }

    final status = await ref.read(authApiProvider).fetchStatus();
    state = AsyncData(
      AuthState.signedOut(serverInitialized: status.initialized),
    );
  }

  Future<void> configureServerAddresses({
    String? internalBaseUrl,
    String? externalBaseUrl,
  }) async {
    await ref
        .read(serverConfigControllerProvider.notifier)
        .setEndpointAddresses(
          internalBaseUrl: internalBaseUrl,
          externalBaseUrl: externalBaseUrl,
        );
    final newConfig = await ref.read(serverConfigControllerProvider.future);
    await _migrateSessionToConfig(newConfig);
  }

  /// Updates the login screen after a user selects server addresses.
  ///
  /// Address settings deliberately do not call this method, because saving a
  /// reachable address must not invalidate an existing authenticated session.
  Future<bool> refreshServerInitialization() async {
    final status = await ref.read(authApiProvider).fetchStatus();
    final current = state.valueOrNull;
    if (current?.isAuthenticated != true) {
      state = AsyncData(
        AuthState.signedOut(serverInitialized: status.initialized),
      );
    }
    return status.initialized;
  }

  Future<void> _migrateSessionToConfig(ServerConfig config) async {
    final store = ref.read(authSessionStoreProvider);
    final current = state.valueOrNull;
    final session = current?.session ?? await store.read();
    if (session == null) {
      return;
    }

    final migrated = session.copyWith(
      serverBaseUrl: config.baseUrl,
      serverScopeId: config.cacheScopeId,
    );
    await store.write(migrated);

    if (current?.isAuthenticated == true) {
      state = AsyncData(
        AuthState.signedIn(
          serverInitialized: current!.serverInitialized,
          session: migrated,
          connectionState: current.connectionState,
        ),
      );
    }
  }

  Future<void> login({
    required String username,
    required String password,
  }) async {
    await _authenticate(
      username: username,
      password: password,
      register: false,
    );
  }

  Future<void> registerAdmin({
    required String username,
    required String password,
  }) async {
    await _authenticate(
      username: username,
      password: password,
      register: true,
    );
  }

  Future<void> logout() async {
    try {
      await ref.read(authApiProvider).logout();
    } finally {
      await ref.read(authSessionStoreProvider).clear();
      final initialized = state.valueOrNull?.serverInitialized ?? true;
      state = AsyncData(
        AuthState.signedOut(serverInitialized: initialized),
      );
    }
  }

  Future<void> _authenticate({
    required String username,
    required String password,
    required bool register,
  }) async {
    final normalizedUsername = username.trim();
    if (normalizedUsername.isEmpty || password.isEmpty) {
      throw const ApiError(
        '\u8bf7\u8f93\u5165\u7528\u6237\u540d\u548c\u5bc6\u7801',
      );
    }

    final api = ref.read(authApiProvider);
    if (register) {
      await api.registerAdmin(
        username: normalizedUsername,
        password: password,
      );
    }
    final result = await api.login(
      username: normalizedUsername,
      password: password,
    );
    final config = await ref.read(serverConfigControllerProvider.future);
    final session = AuthSession(
      token: result.token,
      username: result.username,
      serverBaseUrl: config.baseUrl,
      serverScopeId: config.cacheScopeId,
      offlineCredential: result.token,
      lastOnlineValidatedAt: DateTime.now().toUtc(),
    );
    await ref.read(authSessionStoreProvider).write(session);
    state = AsyncData(
      AuthState.signedIn(serverInitialized: true, session: session),
    );
  }

  void _handleUnauthorized() {
    final current = state.valueOrNull;
    if (current == null || !current.isAuthenticated) {
      return;
    }
    unawaited(ref.read(authSessionStoreProvider).clear());
    state = AsyncData(
      AuthState.signedOut(serverInitialized: current.serverInitialized),
    );
  }

  void _handleAuthenticatedRequestSucceeded() {
    final current = state.valueOrNull;
    if (current?.isOfflineAuthenticated != true) {
      return;
    }

    final session = current!.session!;
    final config = ref.read(serverConfigControllerProvider).valueOrNull;
    final onlineSession = session.copyWith(
      serverBaseUrl: config?.baseUrl ?? session.serverBaseUrl,
      serverScopeId: config?.cacheScopeId ?? session.serverScopeId,
      lastOnlineValidatedAt: DateTime.now().toUtc(),
    );
    state = AsyncData(
      AuthState.signedIn(
        serverInitialized: current.serverInitialized,
        session: onlineSession,
      ),
    );
    unawaited(ref.read(authSessionStoreProvider).write(onlineSession));
  }

  Future<AuthSession?> _sessionForConfig({
    required AuthSessionStore store,
    required ServerConfig config,
    required AuthSession? session,
  }) async {
    if (session == null) {
      return null;
    }
    if (session.isForServer(config.cacheScopeId)) {
      return session;
    }
    if (!config.endpointUrls.contains(session.serverBaseUrl)) {
      await store.clear();
      return null;
    }

    final migrated = session.copyWith(
      serverBaseUrl: config.baseUrl,
      serverScopeId: config.cacheScopeId,
    );
    await store.write(migrated);
    return migrated;
  }

  Future<void> _verifyCachedSession(
    ServerConfig config,
    AuthSession cachedSession,
  ) async {
    final store = ref.read(authSessionStoreProvider);
    try {
      final status = await ref.read(authApiProvider).fetchStatus();
      if (!status.initialized) {
        return;
      }
      final username = status.authenticated && status.username != null
          ? status.username!.trim()
          : await ref.read(authApiProvider).fetchCurrentUsername();
      final verifiedSession = AuthSession(
        token: cachedSession.token,
        username: username,
        serverBaseUrl: config.baseUrl,
        serverScopeId: config.cacheScopeId,
        offlineCredential: _offlineCredentialFor(cachedSession),
        lastOnlineValidatedAt: DateTime.now().toUtc(),
      );
      await store.write(verifiedSession);
      if (_hasCurrentCachedSession(cachedSession)) {
        state = AsyncData(
          AuthState.signedIn(
            serverInitialized: true,
            session: verifiedSession,
          ),
        );
      }
    } on ApiError catch (error) {
      if (error.statusCode != 401) {
        return;
      }
      await store.clear();
      if (_hasCurrentCachedSession(cachedSession)) {
        state = const AsyncData(AuthState.signedOut(serverInitialized: true));
      }
    }
  }

  bool _hasCurrentCachedSession(AuthSession cachedSession) {
    final current = state.valueOrNull?.session;
    return current != null &&
        current.token == cachedSession.token &&
        current.isForServer(
            cachedSession.serverScopeId ?? cachedSession.serverBaseUrl);
  }

  String _offlineCredentialFor(AuthSession session) {
    final credential = session.offlineCredential?.trim();
    return credential == null || credential.isEmpty
        ? session.token
        : credential;
  }
}
