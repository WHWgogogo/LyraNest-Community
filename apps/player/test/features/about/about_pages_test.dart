import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/about/presentation/about_page.dart';
import 'package:player/features/about/data/github_release_checker.dart';
import 'package:player/features/about/presentation/support_author_page.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('shows the branded about page and current version',
      (tester) async {
    await tester.pumpWidget(const _TestApp(child: AboutPage()));

    expect(find.text('LyraNest'), findsOneWidget);
    expect(find.text('Version 0.1.8'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Project address'), findsOneWidget);
    expect(find.text('Author homepage'), findsOneWidget);
    expect(find.text('Contact author'), findsOneWidget);
  });

  testWidgets('reports an available GitHub release', (tester) async {
    await tester.pumpWidget(
      _TestApp(
        child: AboutPage(
          releaseChecker: () async => LyraNestRelease(
            version: '0.1.9',
            releaseUri: Uri.parse('https://example.test/release'),
          ),
          linkOpener: (_) async => true,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('about-check-updates')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('LyraNest 0.1.9 is available.'), findsOneWidget);
  });

  testWidgets('shows the author support code', (tester) async {
    await tester.pumpWidget(const _TestApp(child: SupportAuthorPage()));

    expect(find.text('Support the author'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );
  }
}
