import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/auth_session.dart';

const _authTokenKey = 'auth_session_token';
const _authUsernameKey = 'auth_session_username';
const _authServerBaseUrlKey = 'auth_session_server_base_url';
const _authServerScopeIdKey = 'auth_session_server_scope_id';
const _authOfflineCredentialKey = 'auth_session_offline_credential';
const _authLastOnlineValidatedAtKey = 'auth_session_last_online_validated_at';

final authSessionStoreProvider = Provider<AuthSessionStore>((ref) {
  return const SharedPreferencesAuthSessionStore();
});

abstract interface class AuthSessionStore {
  Future<AuthSession?> read();

  Future<void> write(AuthSession session);

  Future<void> clear();
}

class SharedPreferencesAuthSessionStore implements AuthSessionStore {
  const SharedPreferencesAuthSessionStore();

  @override
  Future<AuthSession?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final token = preferences.getString(_authTokenKey)?.trim();
    final username = preferences.getString(_authUsernameKey)?.trim();
    final serverBaseUrl = preferences.getString(_authServerBaseUrlKey)?.trim();
    final serverScopeId = preferences.getString(_authServerScopeIdKey)?.trim();
    final offlineCredential =
        preferences.getString(_authOfflineCredentialKey)?.trim();
    final lastOnlineValidatedAt = DateTime.tryParse(
      preferences.getString(_authLastOnlineValidatedAtKey) ?? '',
    );

    if (token == null ||
        token.isEmpty ||
        username == null ||
        username.isEmpty ||
        serverBaseUrl == null ||
        serverBaseUrl.isEmpty) {
      return null;
    }

    return AuthSession(
      token: token,
      username: username,
      serverBaseUrl: serverBaseUrl,
      serverScopeId: serverScopeId?.isEmpty == true ? null : serverScopeId,
      offlineCredential:
          offlineCredential?.isEmpty == true ? null : offlineCredential,
      lastOnlineValidatedAt: lastOnlineValidatedAt?.toUtc(),
    );
  }

  @override
  Future<void> write(AuthSession session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_authTokenKey, session.token);
    await preferences.setString(_authUsernameKey, session.username);
    await preferences.setString(
      _authServerBaseUrlKey,
      session.serverBaseUrl,
    );
    final serverScopeId = session.serverScopeId?.trim();
    if (serverScopeId == null || serverScopeId.isEmpty) {
      await preferences.remove(_authServerScopeIdKey);
    } else {
      await preferences.setString(_authServerScopeIdKey, serverScopeId);
    }
    final offlineCredential = session.offlineCredential?.trim();
    if (offlineCredential == null || offlineCredential.isEmpty) {
      await preferences.remove(_authOfflineCredentialKey);
    } else {
      await preferences.setString(_authOfflineCredentialKey, offlineCredential);
    }
    final lastOnlineValidatedAt = session.lastOnlineValidatedAt;
    if (lastOnlineValidatedAt == null) {
      await preferences.remove(_authLastOnlineValidatedAtKey);
    } else {
      await preferences.setString(
        _authLastOnlineValidatedAtKey,
        lastOnlineValidatedAt.toUtc().toIso8601String(),
      );
    }
  }

  @override
  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.remove(_authTokenKey),
      preferences.remove(_authUsernameKey),
      preferences.remove(_authServerBaseUrlKey),
      preferences.remove(_authServerScopeIdKey),
      preferences.remove(_authOfflineCredentialKey),
      preferences.remove(_authLastOnlineValidatedAtKey),
    ]);
  }
}
