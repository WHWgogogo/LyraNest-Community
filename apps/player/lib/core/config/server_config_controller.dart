import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../network/server_connection_validator.dart';
import 'server_config.dart';

const _serverBaseUrlKey = 'server_base_url';
const _serverInternalBaseUrlKey = 'server_internal_base_url';
const _serverExternalBaseUrlKey = 'server_external_base_url';
const _serverActiveBaseUrlKey = 'server_active_base_url';
const _serverIdentityKey = 'server_identity';

final serverConfigControllerProvider =
    AsyncNotifierProvider<ServerConfigController, ServerConfig>(
  ServerConfigController.new,
);

class ServerConfigController extends AsyncNotifier<ServerConfig> {
  @override
  Future<ServerConfig> build() async {
    final preferences = await SharedPreferences.getInstance();
    final legacyBaseUrl = _readUrl(preferences.getString(_serverBaseUrlKey));
    final internalBaseUrl =
        _readUrl(preferences.getString(_serverInternalBaseUrlKey)) ??
            legacyBaseUrl;
    final externalBaseUrl =
        _readUrl(preferences.getString(_serverExternalBaseUrlKey));
    final endpoints = _endpointUrls(
      internalBaseUrl: internalBaseUrl,
      externalBaseUrl: externalBaseUrl,
    );
    final activeBaseUrl =
        _readUrl(preferences.getString(_serverActiveBaseUrlKey));
    final selectedBaseUrl =
        endpoints.contains(activeBaseUrl) ? activeBaseUrl! : endpoints.first;
    final identity = preferences.getString(_serverIdentityKey)?.trim();
    final config = ServerConfig(
      baseUrl: selectedBaseUrl,
      internalBaseUrl: internalBaseUrl,
      externalBaseUrl: externalBaseUrl,
      serverIdentity: identity == null || identity.isEmpty
          ? serverIdentityForUrls(endpoints)
          : identity,
    );
    return config;
  }

  Future<void> setBaseUrl(String value) async {
    final normalized = normalizeServerUrl(value);
    await ref.read(serverConnectionValidatorProvider).validate(normalized);

    await _persist(
      ServerConfig(
        baseUrl: normalized,
        internalBaseUrl: normalized,
        serverIdentity: serverIdentityForUrls([normalized]),
      ),
    );
  }

  Future<void> setServerAddresses({
    String? internalBaseUrl,
    String? externalBaseUrl,
  }) async {
    final internal = _normalizeOptionalUrl(internalBaseUrl);
    final external = _normalizeOptionalUrl(externalBaseUrl);
    final endpoints = _endpointUrls(
      internalBaseUrl: internal,
      externalBaseUrl: external,
    );
    final current = state.valueOrNull;
    final preferred = current?.endpointUrls
        .where(endpoints.contains)
        .cast<String?>()
        .firstOrNull;
    final ordered = <String>[
      if (preferred != null) preferred,
      ...endpoints.where((endpoint) => endpoint != preferred),
    ];
    final selected = endpoints.length == 1
        ? await _validateSingleEndpoint(endpoints.single)
        : await selectHealthyServerUrl(
            ref.read(serverConnectionValidatorProvider),
            ordered,
          );
    if (selected == null) {
      throw StateError('No configured server address passed the health check.');
    }

    final retainsCurrentIdentity =
        current?.endpointUrls.any(endpoints.contains) ?? false;
    final identity = retainsCurrentIdentity
        ? current!.cacheScopeId
        : serverIdentityForUrls(endpoints);
    await _persist(
      ServerConfig(
        baseUrl: selected,
        internalBaseUrl: internal,
        externalBaseUrl: external,
        serverIdentity: identity,
      ),
    );
  }

  /// Alias kept for settings code that names the addresses by network role.
  Future<void> setEndpointAddresses({
    String? internalBaseUrl,
    String? externalBaseUrl,
  }) {
    return setServerAddresses(
      internalBaseUrl: internalBaseUrl,
      externalBaseUrl: externalBaseUrl,
    );
  }

  Future<void> refreshActiveEndpoint() async {
    final config = state.valueOrNull;
    if (config != null) {
      await _refreshActiveEndpoint(config);
    }
  }

  Future<String> _validateSingleEndpoint(String endpoint) async {
    await ref.read(serverConnectionValidatorProvider).validate(endpoint);
    return endpoint;
  }

  Future<void> _refreshActiveEndpoint(ServerConfig config) async {
    final selected = await selectHealthyServerUrl(
      ref.read(serverConnectionValidatorProvider),
      config.endpointUrls,
    );
    if (selected == null || selected == config.baseUrl) {
      return;
    }
    await _persist(config.copyWith(baseUrl: selected));
  }

  Future<void> _persist(ServerConfig config) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_serverBaseUrlKey, config.baseUrl),
      preferences.setString(_serverActiveBaseUrlKey, config.baseUrl),
      preferences.setString(_serverIdentityKey, config.cacheScopeId),
      _writeOptionalString(
        preferences,
        _serverInternalBaseUrlKey,
        config.internalBaseUrl,
      ),
      _writeOptionalString(
        preferences,
        _serverExternalBaseUrlKey,
        config.externalBaseUrl,
      ),
    ]);
    state = AsyncData(config);
  }
}

String? _readUrl(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  try {
    return normalizeServerUrl(value);
  } on ArgumentError {
    return null;
  }
}

String? _normalizeOptionalUrl(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }
  return normalizeServerUrl(value);
}

List<String> _endpointUrls({
  required String? internalBaseUrl,
  required String? externalBaseUrl,
}) {
  final endpoints = [
    if (internalBaseUrl != null) internalBaseUrl,
    if (externalBaseUrl != null) externalBaseUrl,
  ];
  if (endpoints.isEmpty) {
    return [ServerConfig.preferredDefaultBaseUrl];
  }
  return endpoints.toSet().toList(growable: false);
}

Future<void> _writeOptionalString(
  SharedPreferences preferences,
  String key,
  String? value,
) {
  if (value == null || value.trim().isEmpty) {
    return preferences.remove(key);
  }
  return preferences.setString(key, value);
}
