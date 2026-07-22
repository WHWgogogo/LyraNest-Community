import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../auth/domain/auth_session.dart';

@immutable
class CollectionsScope {
  const CollectionsScope._({
    required this.serverBaseUrl,
    required this.username,
    required this.isRemote,
  });

  const CollectionsScope.local()
      : serverBaseUrl = '',
        username = '',
        isRemote = false;

  factory CollectionsScope.fromSession(AuthSession session) {
    final serverBaseUrl = session.serverBaseUrl.trim();
    final username = session.username.trim();
    if (serverBaseUrl.isEmpty || username.isEmpty) {
      throw ArgumentError.value(session, 'session', 'Invalid auth session.');
    }
    return CollectionsScope._(
      serverBaseUrl: serverBaseUrl,
      username: username,
      isRemote: true,
    );
  }

  final String serverBaseUrl;
  final String username;
  final bool isRemote;

  String get storageKey {
    if (!isRemote) {
      return 'local';
    }
    final identity = '${serverBaseUrl.toLowerCase()}\u0000$username';
    return base64Url.encode(utf8.encode(identity)).replaceAll('=', '');
  }

  @override
  bool operator ==(Object other) {
    return other is CollectionsScope &&
        other.isRemote == isRemote &&
        other.serverBaseUrl == serverBaseUrl &&
        other.username == username;
  }

  @override
  int get hashCode => Object.hash(serverBaseUrl, username, isRemote);
}
