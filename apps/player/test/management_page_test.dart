import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/management/data/library_management_api.dart';
import 'package:player/features/management/domain/library_scan_result.dart';
import 'package:player/features/management/domain/library_status.dart';
import 'package:player/features/management/presentation/management_page.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('shows status and refreshes tracks after a scan', (tester) async {
    final api = _FakeLibraryManagementApi();
    var trackLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          libraryManagementApiProvider.overrideWithValue(api),
          tracksProvider.overrideWith((ref) async {
            trackLoads += 1;
            return const TrackList(
              tracks: [Track(id: 'track-1', title: 'Song')],
              total: 1,
            );
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(r'C:\Music'), findsOneWidget);
    expect(find.text('空闲'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '开始扫描'));
    await tester.pumpAndSettle();

    expect(api.scanCalls, 1);
    expect(api.statusCalls, 2);
    expect(trackLoads, 1);
    expect(find.text('本次扫描结果'), findsOneWidget);
    expect(find.text('音乐库扫描完成，共 1 首曲目。'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ManagementPage(),
    );
  }
}

class _FakeLibraryManagementApi implements LibraryManagementApi {
  var statusCalls = 0;
  var scanCalls = 0;

  @override
  Future<LibraryStatus> fetchStatus() async {
    statusCalls += 1;
    return const LibraryStatus(
      directory: r'C:\Music',
      trackCount: 2,
      scanning: false,
      lastScannedAt: null,
      lastError: null,
    );
  }

  @override
  Future<LibraryScanResult> scanLibrary() async {
    scanCalls += 1;
    return LibraryScanResult(
      tracks: const [Track(id: 'track-1', title: 'Song')],
      total: 1,
      scannedAt: DateTime.utc(2026, 7, 18, 12),
    );
  }
}
