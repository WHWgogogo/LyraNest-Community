import 'package:flutter/foundation.dart';

@immutable
class AuthSession {
  const AuthSession({
    required this.token,
    required this.username,
    required this.serverBaseUrl,
    this.serverScopeId,
    this.offlineCredential,
    this.lastOnlineValidatedAt,
  });

  final String token;
  final String username;
  final String serverBaseUrl;
  final String? serverScopeId;
  final String? offlineCredential;
  final DateTime? lastOnlineValidatedAt;

  bool get canAuthenticateOffline {
    return offlineCredential?.trim().isNotEmpty == true &&
        lastOnlineValidatedAt != null;
  }

  bool isForServer(String scopeId) {
    final savedScopeId = serverScopeId?.trim();
    return savedScopeId == null || savedScopeId.isEmpty
        ? serverBaseUrl == scopeId
        : savedScopeId == scopeId;
  }

  AuthSession copyWith({
    String? token,
    String? username,
    String? serverBaseUrl,
    String? serverScopeId,
    String? offlineCredential,
    DateTime? lastOnlineValidatedAt,
  }) {
    return AuthSession(
      token: token ?? this.token,
      username: username ?? this.username,
      serverBaseUrl: serverBaseUrl ?? this.serverBaseUrl,
      serverScopeId: serverScopeId ?? this.serverScopeId,
      offlineCredential: offlineCredential ?? this.offlineCredential,
      lastOnlineValidatedAt:
          lastOnlineValidatedAt ?? this.lastOnlineValidatedAt,
    );
  }
}
