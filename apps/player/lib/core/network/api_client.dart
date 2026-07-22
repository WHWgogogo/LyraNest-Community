import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/data/auth_session_store.dart';
import '../../features/auth/domain/auth_session.dart';
import '../config/server_config.dart';
import '../config/server_config_controller.dart';

final unauthorizedGenerationProvider = StateProvider<int>((ref) => 0);
final authenticatedRequestGenerationProvider = StateProvider<int>((ref) => 0);
const skipAuthenticationExtraKey = 'skip_authentication';

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(serverConfigControllerProvider).valueOrNull ??
      const ServerConfig(baseUrl: ServerConfig.defaultBaseUrl);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.baseUrl,
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.json,
    ),
  );
  dio.interceptors.add(
    QueuedInterceptorsWrapper(
      onRequest: (options, handler) async {
        if (options.extra[skipAuthenticationExtraKey] == true) {
          handler.next(options);
          return;
        }
        final session = await ref.read(authSessionStoreProvider).read();
        if (session != null && _sessionMatchesConfig(session, config)) {
          options.headers['Authorization'] = 'Bearer ${session.token}';
        }
        handler.next(options);
      },
      onResponse: (response, handler) {
        if (response.requestOptions.extra[skipAuthenticationExtraKey] != true &&
            response.requestOptions.headers['Authorization'] != null) {
          ref.read(authenticatedRequestGenerationProvider.notifier).state++;
        }
        handler.next(response);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401) {
          final store = ref.read(authSessionStoreProvider);
          final session = await store.read();
          if (session != null && _sessionMatchesConfig(session, config)) {
            await store.clear();
            ref.read(unauthorizedGenerationProvider.notifier).state++;
          }
        }
        handler.next(error);
      },
    ),
  );
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

bool _sessionMatchesConfig(AuthSession session, ServerConfig config) {
  final savedScopeId = session.serverScopeId?.trim();
  if (savedScopeId != null && savedScopeId.isNotEmpty) {
    return savedScopeId == config.cacheScopeId;
  }
  return config.endpointUrls.contains(session.serverBaseUrl);
}
