import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/config/server_config.dart';
import 'package:player/core/config/server_config_controller.dart';
import 'package:player/core/network/server_connection_validator.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('resolveDefaultServerUrl', () {
    test('uses configured default URL before platform defaults', () {
      final serverUrl = resolveDefaultServerUrl(
        platform: TargetPlatform.android,
        configuredDefaultUrl: ' https://api.example.test/ ',
      );

      expect(serverUrl, 'https://api.example.test');
    });

    test('uses Windows localhost when no default URL is configured', () {
      final serverUrl = resolveDefaultServerUrl(
        platform: TargetPlatform.windows,
        configuredDefaultUrl: '',
      );

      expect(serverUrl, 'http://127.0.0.1:8080');
    });

    test('uses Android emulator host when no default URL is configured', () {
      final serverUrl = resolveDefaultServerUrl(
        platform: TargetPlatform.android,
        configuredDefaultUrl: '',
      );

      expect(serverUrl, 'http://10.0.2.2:8080');
    });
  });

  group('normalizeServerUrl', () {
    test('accepts http and https URLs with hosts', () {
      expect(
        normalizeServerUrl(' http://localhost:8080/api/ '),
        'http://localhost:8080/api',
      );
      expect(
        normalizeServerUrl('https://api.example.test///'),
        'https://api.example.test',
      );
    });

    test('adds http scheme when it is omitted', () {
      expect(
        normalizeServerUrl(' 192.168.0.107:8080/ '),
        'http://192.168.0.107:8080',
      );
    });

    test('rejects unsupported schemes and missing hosts', () {
      expect(
          () => normalizeServerUrl('ftp://example.test'), throwsArgumentError);
      expect(() => normalizeServerUrl('http:///api'), throwsArgumentError);
      expect(() => normalizeServerUrl('/api'), throwsArgumentError);
    });
  });

  group('multiple server addresses', () {
    test('uses one stable cache scope for either configured address', () {
      const internal = 'http://192.168.1.20:8080';
      const external = 'https://music.example.test';
      final identity = serverIdentityForUrls([internal, external]);

      final internalConfig = ServerConfig(
        baseUrl: internal,
        internalBaseUrl: internal,
        externalBaseUrl: external,
        serverIdentity: identity,
      );
      final externalConfig = internalConfig.copyWith(baseUrl: external);

      expect(externalConfig.cacheScopeId, internalConfig.cacheScopeId);
      expect(externalConfig.endpointUrls, [external, internal]);
    });

    test('returns a healthy address without waiting for another timeout',
        () async {
      const internal = 'http://192.168.1.20:8080';
      const external = 'https://music.example.test';
      final delayedInternalProbe = Completer<void>();
      final validator = _FakeServerConnectionValidator((url) {
        return url == external ? Future.value() : delayedInternalProbe.future;
      });

      final selected = await selectHealthyServerUrl(
        validator,
        [internal, external],
      );

      expect(selected, external);
      delayedInternalProbe.complete();
    });
  });

  group('ServerConfigController', () {
    test('does not save when the health check fails', () async {
      SharedPreferences.setMockInitialValues({
        'server_base_url': 'http://saved.example.test',
      });
      final server = await _startHealthServer({'status': 'starting'});
      addTearDown(() => server.close(force: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(serverConfigControllerProvider.future);

      await expectLater(
        container
            .read(serverConfigControllerProvider.notifier)
            .setBaseUrl('127.0.0.1:${server.port}'),
        throwsA(
          isA<ServerHealthCheckException>().having(
            (error) => error.status,
            'status',
            'starting',
          ),
        ),
      );

      final preferences = await SharedPreferences.getInstance();
      expect(
        preferences.getString('server_base_url'),
        'http://saved.example.test',
      );
      expect(
        container.read(serverConfigControllerProvider).requireValue.baseUrl,
        'http://saved.example.test',
      );
    });

    test('keeps old config while validating and saves after success', () async {
      SharedPreferences.setMockInitialValues({
        'server_base_url': 'http://saved.example.test',
      });
      final responseGate = Completer<void>();
      final requestedPath = Completer<String>();
      final server = await _startHealthServer(
        {'status': 'ok'},
        responseGate: responseGate.future,
        requestedPath: requestedPath,
      );
      addTearDown(() => server.close(force: true));
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(serverConfigControllerProvider.future);

      final saveFuture = container
          .read(serverConfigControllerProvider.notifier)
          .setBaseUrl('127.0.0.1:${server.port}');

      expect(await requestedPath.future, '/healthz');
      final pendingConfig = container.read(serverConfigControllerProvider);
      expect(pendingConfig.isLoading, isFalse);
      expect(
        pendingConfig.requireValue.baseUrl,
        'http://saved.example.test',
      );

      responseGate.complete();
      await saveFuture;

      final normalized = 'http://127.0.0.1:${server.port}';
      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('server_base_url'), normalized);
      expect(
        container.read(serverConfigControllerProvider).requireValue.baseUrl,
        normalized,
      );
    });
  });
}

class _FakeServerConnectionValidator implements ServerConnectionValidator {
  _FakeServerConnectionValidator(this.validateUrl);

  final Future<void> Function(String url) validateUrl;

  @override
  Future<void> validate(String baseUrl) => validateUrl(baseUrl);
}

Future<HttpServer> _startHealthServer(
  Object responseBody, {
  Future<void>? responseGate,
  Completer<String>? requestedPath,
}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    requestedPath?.complete(request.uri.path);
    if (responseGate != null) {
      await responseGate;
    }
    request.response.headers.contentType = ContentType.json;
    request.response.write(jsonEncode(responseBody));
    await request.response.close();
  });
  return server;
}
