import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/config/server_config_controller.dart';
import 'package:player/core/network/server_connection_validator.dart';
import 'package:player/features/auth/data/auth_api.dart';
import 'package:player/features/auth/presentation/login_page.dart';
import 'package:player/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('accepts local and public server addresses on first login',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final validator = _RecordingValidator();
    final authApi = _RecordingAuthApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConnectionValidatorProvider.overrideWithValue(validator),
          authApiProvider.overrideWithValue(authApi),
        ],
        child: MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('auth-server-field')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('auth-external-server-field')),
      findsOneWidget,
    );
    expect(find.text('内网访问地址'), findsOneWidget);
    expect(find.text('外网访问地址（可选）'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('auth-server-field')),
      '192.168.1.20:8080',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-external-server-field')),
      'https://music.example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-username-field')),
      'admin',
    );
    await tester.enterText(
      find.byKey(const ValueKey('auth-password-field')),
      'secret',
    );
    await tester.tap(find.byKey(const ValueKey('auth-submit-button')));
    await tester.pumpAndSettle();

    expect(
      validator.candidates,
      containsAll([
        'http://192.168.1.20:8080',
        'https://music.example.test',
      ]),
    );
    expect(authApi.loggedInUsername, 'admin');
    expect(authApi.loggedInPassword, 'secret');

    final container = ProviderScope.containerOf(
      tester.element(find.byType(LoginPage)),
    );
    final config = container.read(serverConfigControllerProvider).requireValue;
    expect(config.internalBaseUrl, 'http://192.168.1.20:8080');
    expect(config.externalBaseUrl, 'https://music.example.test');
  });
}

class _RecordingValidator implements ServerConnectionValidator {
  final List<String> candidates = [];

  @override
  Future<void> validate(String baseUrl) async {
    candidates.add(baseUrl);
  }
}

class _RecordingAuthApi implements AuthApi {
  String? loggedInUsername;
  String? loggedInPassword;

  @override
  Future<AuthStatus> fetchStatus() async {
    return const AuthStatus(initialized: true);
  }

  @override
  Future<String> fetchCurrentUsername() {
    throw UnimplementedError();
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
  }) async {
    loggedInUsername = username;
    loggedInPassword = password;
    return AuthResult(token: 'token', username: username);
  }

  @override
  Future<void> logout() {
    throw UnimplementedError();
  }

  @override
  Future<void> registerAdmin({
    required String username,
    required String password,
  }) {
    throw UnimplementedError();
  }
}
