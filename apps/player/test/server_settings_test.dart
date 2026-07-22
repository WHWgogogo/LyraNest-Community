import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/core/network/server_connection_validator.dart';
import 'package:player/features/settings/presentation/server_settings_page.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/l10n/l10n.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('shows localized details and does not save after failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://saved.example.test',
      'auth_session_token': 'old-token',
      'auth_session_username': 'old-user',
      'auth_session_server_base_url': 'http://saved.example.test',
      'auth_session_offline_credential': 'old-offline-token',
    });
    final validator = _FakeServerConnectionValidator(
      error: const ApiError('Connection refused'),
    );
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConnectionValidatorProvider.overrideWithValue(validator),
        ],
        child: _TestApp(router: router, locale: const Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      '192.168.0.107:8080',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(validator.candidates, ['http://192.168.0.107:8080']);
    expect(
      find.text('Could not connect to server: Connection refused'),
      findsOneWidget,
    );
    expect(find.text('Tracks destination'), findsNothing);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('server_base_url'),
      'http://saved.example.test',
    );
  });

  testWidgets('saves, refreshes tracks, and keeps the login session',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'server_base_url': 'http://saved.example.test',
      'auth_session_token': 'old-token',
      'auth_session_username': 'old-user',
      'auth_session_server_base_url': 'http://saved.example.test',
      'auth_session_offline_credential': 'old-offline-token',
    });
    final validator = _FakeServerConnectionValidator();
    var trackLoads = 0;
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          serverConnectionValidatorProvider.overrideWithValue(validator),
          tracksProvider.overrideWith((ref) async {
            trackLoads += 1;
            return const TrackList(tracks: [], total: 0);
          }),
        ],
        child: _TestApp(
          router: router,
          locale: const Locale('zh'),
          watchTracks: true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(trackLoads, 1);

    await tester.enterText(
      find.byKey(const ValueKey('server-url-field')),
      '192.168.0.107:8080',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(validator.candidates, ['http://192.168.0.107:8080']);
    expect(find.text('Tracks destination'), findsOneWidget);
    expect(find.text('连接成功'), findsOneWidget);
    expect(trackLoads, 2);

    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString('server_base_url'),
      'http://192.168.0.107:8080',
    );
    expect(preferences.getString('auth_session_token'), 'old-token');
    expect(preferences.getString('auth_session_username'), 'old-user');
    expect(
      preferences.getString('auth_session_server_base_url'),
      'http://192.168.0.107:8080',
    );
    expect(
      preferences.getString('auth_session_server_scope_id'),
      isNotEmpty,
    );
    expect(
      preferences.getString('auth_session_offline_credential'),
      'old-offline-token',
    );
  });

  testWidgets('shows the About indicator once and persists its dismissal',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final router = _createRouter();
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        child: _TestApp(router: router, locale: const Locale('en')),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('about-entry-unread-indicator')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('about-settings-entry')));
    await tester.pumpAndSettle();

    expect(find.text('About destination'), findsOneWidget);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(aboutPageViewedPreferenceKey), isTrue);

    router.go('/settings');
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('about-entry-unread-indicator')),
      findsNothing,
    );
  });
}

GoRouter _createRouter() {
  return GoRouter(
    initialLocation: '/settings',
    routes: [
      GoRoute(
        path: '/settings',
        builder: (context, state) => const ServerSettingsPage(),
      ),
      GoRoute(
        path: '/tracks',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('Tracks destination')),
        ),
      ),
      GoRoute(
        path: '/about',
        builder: (context, state) => const Scaffold(
          body: Center(child: Text('About destination')),
        ),
      ),
    ],
  );
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.router,
    required this.locale,
    this.watchTracks = false,
  });

  final GoRouter router;
  final Locale locale;
  final bool watchTracks;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
      builder: (context, child) {
        if (!watchTracks) {
          return child!;
        }

        return Consumer(
          builder: (context, ref, _) {
            ref.watch(tracksProvider);
            return child!;
          },
        );
      },
    );
  }
}

class _FakeServerConnectionValidator implements ServerConnectionValidator {
  _FakeServerConnectionValidator({this.error});

  final Object? error;
  final List<String> candidates = [];

  @override
  Future<void> validate(String baseUrl) async {
    candidates.add(baseUrl);
    final validationError = error;
    if (validationError != null) {
      throw validationError;
    }
  }
}
