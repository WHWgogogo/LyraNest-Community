import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:player/features/app_lifecycle/data/app_lifecycle_platform.dart';
import 'package:player/core/widgets/root_back_exit_guard.dart';
import 'package:player/l10n/l10n.dart';

const _appLifecycleChannel = MethodChannel(
  'com.harmonymusic.player/app_lifecycle',
);

void main() {
  test('Android lifecycle platform invokes native task methods', () async {
    final methodCalls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_appLifecycleChannel, (call) async {
      methodCalls.add(call.method);
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_appLifecycleChannel, null);
    });

    const platform = AndroidAppLifecyclePlatform();
    await platform.moveTaskToBack();
    await platform.exitApplication();

    expect(methodCalls, ['moveTaskToBack', 'exitApplication']);
  });

  testWidgets('shows localized choices for an Android root back action',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    await _pumpGuard(
      tester,
      platform: platform,
      locale: const Locale('zh'),
    );

    await _triggerBack(tester);

    expect(find.text('要退出律巢吗？'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('保留后台播放'), findsOneWidget);
    expect(find.text('退出应用'), findsOneWidget);
    expect(platform.moveTaskToBackCalls, 0);
    expect(platform.exitApplicationCalls, 0);
  });

  testWidgets('cancel keeps the Android app open', (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    await _pumpGuard(tester, platform: platform);

    await _triggerBack(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Exit LyraNest?'), findsNothing);
    expect(platform.moveTaskToBackCalls, 0);
    expect(platform.exitApplicationCalls, 0);
  });

  testWidgets('keep playing moves the Android task to the background',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    var stopPlaybackCalls = 0;
    await _pumpGuard(
      tester,
      platform: platform,
      stopPlayback: () async {
        stopPlaybackCalls++;
      },
    );

    await _triggerBack(tester);
    await tester.tap(find.text('Keep playing'));
    await tester.pumpAndSettle();

    expect(platform.moveTaskToBackCalls, 1);
    expect(platform.exitApplicationCalls, 0);
    expect(stopPlaybackCalls, 0);
  });

  testWidgets('exit stops playback before finishing the Android task',
      (tester) async {
    final events = <String>[];
    final platform = _FakeAppLifecyclePlatform(
      onExitApplication: () async {
        events.add('exit');
      },
    );
    await _pumpGuard(
      tester,
      platform: platform,
      stopPlayback: () async {
        events.add('stop');
      },
    );

    await _triggerBack(tester);
    await tester.tap(find.text('Exit app'));
    await tester.pumpAndSettle();

    expect(events, ['stop', 'exit']);
    expect(platform.moveTaskToBackCalls, 0);
    expect(platform.exitApplicationCalls, 1);
  });

  testWidgets('ShellRoute intercepts Android back at the exact root URI',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    final router = _shellRouter(platform: platform, initialLocation: '/');
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);

    expect(find.text('Root route'), findsOneWidget);
    expect(_popScope(tester).canPop, isFalse);

    await _triggerBack(tester);

    expect(find.text('Exit LyraNest?'), findsOneWidget);
    expect(platform.moveTaskToBackCalls, 0);
    expect(platform.exitApplicationCalls, 0);
  });

  testWidgets('ShellRoute does not intercept a non-exact root URI',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    final router = _shellRouter(
      platform: platform,
      initialLocation: '/?source=notification',
    );
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);

    expect(find.text('Root route'), findsOneWidget);
    expect(_popScope(tester).canPop, isTrue);
  });

  testWidgets('ShellRoute nested routes pop normally without an exit dialog',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    final router = _shellRouter(platform: platform, initialLocation: '/nested');
    addTearDown(router.dispose);
    await _pumpRouter(tester, router);
    expect(find.text('Nested route'), findsOneWidget);

    await _triggerBack(tester);
    await tester.pumpAndSettle();

    expect(find.text('Nested route'), findsNothing);
    expect(find.text('Exit LyraNest?'), findsNothing);
    expect(platform.moveTaskToBackCalls, 0);
    expect(platform.exitApplicationCalls, 0);
  });

  testWidgets('predictive Android back commits to the root exit dialog',
      (tester) async {
    final platform = _FakeAppLifecyclePlatform();
    await _pumpGuard(tester, platform: platform);

    final handledGesture = await _sendBackGesture<bool>(
      'startBackGesture',
      arguments: const {
        'touchOffset': [0.0, 0.0],
        'progress': 0.0,
        'swipeEdge': 0,
      },
    );
    expect(handledGesture, isFalse);

    await _sendBackGesture<void>('commitBackGesture');
    await tester.pump();

    expect(find.text('Exit LyraNest?'), findsOneWidget);
  });
}

GoRouter _shellRouter({
  required _FakeAppLifecyclePlatform platform,
  required String initialLocation,
}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: [
      ShellRoute(
        builder: (context, state, child) {
          return RootBackExitGuard(
            platform: platform,
            targetPlatform: TargetPlatform.android,
            isRootUri: state.uri.toString() == '/',
            child: Scaffold(body: child),
          );
        },
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => const Scaffold(
              body: Center(child: Text('Root route')),
            ),
            routes: [
              GoRoute(
                path: 'nested',
                builder: (context, state) => const Scaffold(
                  body: Center(child: Text('Nested route')),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

Future<void> _pumpRouter(WidgetTester tester, GoRouter router) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _pumpGuard(
  WidgetTester tester, {
  required _FakeAppLifecyclePlatform platform,
  Locale locale = const Locale('en'),
  Future<void> Function()? stopPlayback,
  Widget? child,
}) {
  return tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: RootBackExitGuard(
          platform: platform,
          targetPlatform: TargetPlatform.android,
          stopPlayback: stopPlayback,
          child: child ??
              const Scaffold(
                body: Center(child: Text('Root route')),
              ),
        ),
      ),
    ),
  );
}

Future<void> _triggerBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pump();
}

PopScope<Object?> _popScope(WidgetTester tester) {
  return tester.widget<PopScope<Object?>>(
    find.byWidgetPredicate((widget) => widget is PopScope<Object?>),
  );
}

Future<T?> _sendBackGesture<T>(
  String method, {
  Object? arguments,
}) async {
  final response = await TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .handlePlatformMessage(
    SystemChannels.backGesture.name,
    SystemChannels.backGesture.codec.encodeMethodCall(
      MethodCall(method, arguments),
    ),
    null,
  );
  return response == null
      ? null
      : SystemChannels.backGesture.codec.decodeEnvelope(response) as T?;
}

class _FakeAppLifecyclePlatform implements AppLifecyclePlatform {
  _FakeAppLifecyclePlatform({this.onExitApplication});

  final Future<void> Function()? onExitApplication;
  var moveTaskToBackCalls = 0;
  var exitApplicationCalls = 0;

  @override
  Future<void> moveTaskToBack() async {
    moveTaskToBackCalls++;
  }

  @override
  Future<void> exitApplication() async {
    exitApplicationCalls++;
    await onExitApplication?.call();
  }
}
