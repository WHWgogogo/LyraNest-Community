import 'dart:convert';

import 'package:flutter/foundation.dart';

const _defaultServerUrlFromEnvironment =
    String.fromEnvironment('DEFAULT_SERVER_URL');

@immutable
class ServerConfig {
  const ServerConfig({
    required this.baseUrl,
    this.internalBaseUrl,
    this.externalBaseUrl,
    this.serverIdentity,
  });

  static const defaultBaseUrl = 'http://127.0.0.1:8080';
  static const androidEmulatorDefaultBaseUrl = 'http://10.0.2.2:8080';

  static String get preferredDefaultBaseUrl {
    return resolveDefaultServerUrl(platform: defaultTargetPlatform);
  }

  final String baseUrl;
  final String? internalBaseUrl;
  final String? externalBaseUrl;

  /// Stable identity for a server configuration.
  ///
  /// The active URL may change when a device moves between a LAN and the
  /// internet. Authentication and offline media use this identity instead of
  /// the active URL so that switch does not create a new local profile.
  final String? serverIdentity;

  String get cacheScopeId {
    final identity = serverIdentity?.trim();
    return identity == null || identity.isEmpty ? baseUrl : identity;
  }

  List<String> get endpointUrls {
    final endpoints = <String>[baseUrl];
    if (internalBaseUrl != null) {
      endpoints.add(internalBaseUrl!);
    }
    if (externalBaseUrl != null) {
      endpoints.add(externalBaseUrl!);
    }
    return List.unmodifiable(_deduplicateServerUrls(endpoints));
  }

  ServerConfig copyWith({
    String? baseUrl,
    String? internalBaseUrl,
    String? externalBaseUrl,
    String? serverIdentity,
  }) {
    return ServerConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      internalBaseUrl: internalBaseUrl ?? this.internalBaseUrl,
      externalBaseUrl: externalBaseUrl ?? this.externalBaseUrl,
      serverIdentity: serverIdentity ?? this.serverIdentity,
    );
  }
}

String resolveDefaultServerUrl({
  required TargetPlatform platform,
  String configuredDefaultUrl = _defaultServerUrlFromEnvironment,
}) {
  if (configuredDefaultUrl.trim().isNotEmpty) {
    return normalizeServerUrl(configuredDefaultUrl);
  }

  return switch (platform) {
    TargetPlatform.android => ServerConfig.androidEmulatorDefaultBaseUrl,
    _ => ServerConfig.defaultBaseUrl,
  };
}

String normalizeServerUrl(String value) {
  final trimmed = value.trim();
  final candidate = RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(trimmed)
      ? trimmed
      : 'http://$trimmed';
  final uri = Uri.tryParse(candidate);
  final hasSupportedScheme = uri?.scheme == 'http' || uri?.scheme == 'https';

  if (uri == null || !hasSupportedScheme || uri.host.isEmpty) {
    throw ArgumentError.value(
      value,
      'value',
      'Server URL must be an http(s) URL with a host.',
    );
  }

  var normalizedPath = uri.path;
  while (normalizedPath.endsWith('/')) {
    normalizedPath = normalizedPath.substring(0, normalizedPath.length - 1);
  }

  return uri.replace(path: normalizedPath).toString();
}

String serverIdentityForUrls(Iterable<String> urls) {
  final normalized = _deduplicateServerUrls(urls)..sort();
  if (normalized.isEmpty) {
    throw ArgumentError.value(urls, 'urls', 'At least one URL is required.');
  }
  return base64Url.encode(utf8.encode(jsonEncode(normalized)));
}

List<String> _deduplicateServerUrls(Iterable<String?> urls) {
  final result = <String>[];
  for (final value in urls) {
    if (value == null || value.trim().isEmpty) {
      continue;
    }
    final normalized = normalizeServerUrl(value);
    if (!result.contains(normalized)) {
      result.add(normalized);
    }
  }
  return result;
}
