import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Identifies one isolated offline cache namespace.
///
/// A cache namespace deliberately excludes authentication tokens so refreshing
/// a session does not discard downloads, while profile, user, and server
/// changes always select a different on-disk directory.
class OfflineCacheScope {
  OfflineCacheScope({
    required String profileId,
    required String userId,
    required String serverBaseUrl,
    String? serverIdentity,
  })  : profileId = _requiredValue(profileId, 'profileId'),
        userId = _requiredValue(userId, 'userId'),
        serverBaseUrl = normalizeOfflineServerUrl(serverBaseUrl),
        serverIdentity = _requiredValue(
          serverIdentity ?? normalizeOfflineServerUrl(serverBaseUrl),
          'serverIdentity',
        );

  final String profileId;
  final String userId;
  final String serverBaseUrl;
  final String serverIdentity;

  /// A filesystem-safe, non-reversible namespace name.
  String get cacheKey {
    final identity = jsonEncode({
      'profileId': profileId,
      'serverIdentity': serverIdentity,
      'userId': userId,
    });
    return sha256.convert(utf8.encode(identity)).toString();
  }

  Map<String, Object> toJson() => {
        'profileId': profileId,
        'serverIdentity': serverIdentity,
        'serverBaseUrl': serverBaseUrl,
        'userId': userId,
      };

  factory OfflineCacheScope.fromJson(Map<String, Object?> json) {
    return OfflineCacheScope(
      profileId: json['profileId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      serverBaseUrl: json['serverBaseUrl'] as String? ?? '',
      serverIdentity: json['serverIdentity'] as String?,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is OfflineCacheScope &&
        other.profileId == profileId &&
        other.userId == userId &&
        other.serverIdentity == serverIdentity;
  }

  @override
  int get hashCode => Object.hash(profileId, userId, serverIdentity);

  @override
  String toString() {
    return 'OfflineCacheScope(profileId: $profileId, userId: $userId, '
        'serverIdentity: $serverIdentity)';
  }
}

String normalizeOfflineServerUrl(String value) {
  final parsed = Uri.tryParse(value.trim());
  if (parsed == null ||
      (parsed.scheme != 'http' && parsed.scheme != 'https') ||
      parsed.host.isEmpty) {
    throw ArgumentError.value(
      value,
      'serverBaseUrl',
      'Must be an http(s) URL with a host.',
    );
  }

  final normalizedPath = parsed.path.replaceFirst(RegExp(r'/+$'), '');
  return parsed
      .replace(
        scheme: parsed.scheme.toLowerCase(),
        host: parsed.host.toLowerCase(),
        path: normalizedPath,
        query: null,
        fragment: null,
      )
      .toString();
}

String _requiredValue(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be empty.');
  }
  return normalized;
}
