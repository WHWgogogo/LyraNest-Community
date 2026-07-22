import 'package:flutter/foundation.dart';

import 'auth_session.dart';

enum AuthConnectionState {
  online,
  offline,
}

@immutable
class AuthState {
  const AuthState({
    required this.serverInitialized,
    this.session,
    this.connectionState = AuthConnectionState.online,
  });

  const AuthState.signedOut({required bool serverInitialized})
      : this(
          serverInitialized: serverInitialized,
          connectionState: AuthConnectionState.online,
        );

  const AuthState.signedIn({
    required bool serverInitialized,
    required AuthSession session,
    AuthConnectionState connectionState = AuthConnectionState.online,
  }) : this(
          serverInitialized: serverInitialized,
          session: session,
          connectionState: connectionState,
        );

  final bool serverInitialized;
  final AuthSession? session;
  final AuthConnectionState connectionState;

  bool get isAuthenticated => session != null;

  bool get isOfflineAuthenticated {
    return isAuthenticated && connectionState == AuthConnectionState.offline;
  }
}
