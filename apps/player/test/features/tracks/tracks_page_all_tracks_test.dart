import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/collections/application/collections_controller.dart';
import 'package:player/features/offline/application/offline_downloads_controller.dart';
import 'package:player/features/offline/domain/offline_cache_scope.dart';
import 'package:player/features/offline/domain/offline_download_task.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/features/tracks/presentation/tracks_page.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('all tracks keeps favorite, scrape, and download in More',
      (tester) async {
    await tester.pumpWidget(_TestApp());
    await tester.pumpAndSettle();

    expect(find.byTooltip('更多操作'), findsNWidgets(2));
    expect(find.byTooltip('刮削元数据'), findsNothing);
    expect(find.byTooltip('下载到本地'), findsNothing);

    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();

    expect(find.text('收藏'), findsWidgets);
    expect(find.text('刮削元数据'), findsOneWidget);
    expect(find.text('下载'), findsWidgets);
  });

  testWidgets('long press enters selection mode and taps toggle selection',
      (tester) async {
    await tester.pumpWidget(_TestApp());
    await tester.pumpAndSettle();

    await tester.longPress(find.text('Zebra'));
    await tester.pumpAndSettle();

    expect(find.text('已选 1 首'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNothing);
    expect(
        find.byKey(const ValueKey('all_tracks_add_to_queue')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('all_tracks_add_to_playlist')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('all_tracks_download')), findsOneWidget);

    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    expect(find.text('已选 2 首'), findsOneWidget);
  });

  testWidgets('sort control switches all tracks to descending order',
      (tester) async {
    await tester.pumpWidget(_TestApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('all_tracks_sort')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('降序'));
    await tester.pumpAndSettle();

    final titles = tester
        .widgetList<Text>(find.textContaining(RegExp(r'^(Zebra|Alpha)$')))
        .map((widget) => widget.data)
        .toList();
    expect(titles, ['Zebra', 'Alpha']);
  });

  testWidgets('download tab displays completed local tracks', (tester) async {
    await tester.pumpWidget(_TestApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('下载'),
        matching: find.byType(ChoiceChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zebra'), findsOneWidget);
    expect(find.text('Alpha'), findsNothing);
  });

  testWidgets(
      'download tab stays available with local tracks when remote loading fails',
      (tester) async {
    await tester.pumpWidget(_TestApp(tracksError: true));
    await tester.pumpAndSettle();

    expect(
      find.ancestor(
        of: find.text('下载'),
        matching: find.byType(ChoiceChip),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.ancestor(
        of: find.text('下载'),
        matching: find.byType(ChoiceChip),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Zebra'), findsOneWidget);
  });

  testWidgets('download tab confirms before deleting a local download',
      (tester) async {
    await tester.pumpWidget(_TestApp());
    await tester.pumpAndSettle();

    await tester.tap(
      find.ancestor(
        of: find.text('下载'),
        matching: find.byType(ChoiceChip),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除本地下载'));
    await tester.pumpAndSettle();

    expect(find.text('删除本地下载？'), findsOneWidget);
    expect(find.textContaining('Zebra'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();

    expect(find.text('Zebra'), findsNothing);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({this.tracksError = false});

  final bool tracksError;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        tracksProvider.overrideWith((ref) async {
          if (tracksError) {
            throw StateError('server unavailable');
          }
          return const TrackList(
            total: 2,
            tracks: [
              Track(id: 'zebra', title: 'Zebra', artist: 'Zed'),
              Track(id: 'alpha', title: 'Alpha', artist: 'Ada'),
            ],
          );
        }),
        favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
        offlineDownloadsProvider
            .overrideWith(_TestOfflineDownloadsController.new),
      ],
      child: MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const Scaffold(body: TracksPage()),
      ),
    );
  }
}

class _TestOfflineDownloadsController extends OfflineDownloadsController {
  static final _scope = OfflineCacheScope(
    profileId: 'primary',
    userId: 'tester',
    serverBaseUrl: 'https://music.example.test',
  );

  @override
  Future<OfflineDownloadsState> build() async {
    return OfflineDownloadsState(
      cacheAvailable: true,
      quotaBytes: 1024,
      tasks: {
        'zebra': OfflineDownloadTask(
          id: 'offline-download:zebra',
          scope: _scope,
          trackId: 'zebra',
          sourceUri: Uri.parse(
            'https://music.example.test/api/v1/tracks/zebra/stream',
          ),
          status: OfflineDownloadStatus.completed,
          trackSnapshot: const OfflineTrackSnapshot(
            title: 'Zebra',
            artist: 'Zed',
          ),
        ),
      },
    );
  }

  @override
  Future<void> delete(String trackId) async {
    final current = await future;
    final tasks = Map<String, OfflineDownloadTask>.of(current.tasks)
      ..remove(trackId);
    state = AsyncData(current.copyWith(tasks: tasks));
  }
}
