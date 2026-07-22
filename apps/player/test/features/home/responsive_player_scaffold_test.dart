import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/tracks/presentation/library_ui.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('uses a collapsible sidebar on desktop widths', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _TestApp());

    expect(find.text('曲库'), findsOneWidget);
    expect(find.text('LyraNest'), findsOneWidget);
    expect(find.text('和声'), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.text('播放器控制区'), findsOneWidget);

    await tester.tap(find.byTooltip('收起导航'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('展开导航'), findsOneWidget);
    expect(find.text('曲库'), findsNothing);
  });

  testWidgets('uses mini player and bottom navigation on compact widths', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const _TestApp());

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('迷你播放器'), findsOneWidget);
    expect(find.text('我的'), findsOneWidget);
  });
}

class _TestApp extends StatefulWidget {
  const _TestApp();

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  var _selectedDestination = MusicNavigationDestination.home;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9A7DFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: ResponsivePlayerScaffold(
        title: _selectedDestination.label,
        selectedDestination: _selectedDestination,
        onDestinationSelected: (destination) {
          setState(() {
            _selectedDestination = destination;
          });
        },
        child: const SizedBox.expand(),
      ),
    );
  }
}
