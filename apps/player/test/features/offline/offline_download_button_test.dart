import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/offline/application/offline_downloads_controller.dart';
import 'package:player/features/offline/domain/offline_cache_scope.dart';
import 'package:player/features/offline/domain/offline_download_task.dart';
import 'package:player/features/offline/presentation/offline_download_button.dart';
import 'package:player/features/tracks/domain/track.dart';

void main() {
  const track = Track(id: 'track-1', title: 'Offline track');

  setUp(_TestOfflineDownloadsController.reset);

  testWidgets('completed downloads show a disabled downloaded indicator',
      (tester) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(offlineDownloadsProvider.future);

    await _pumpButton(tester, container);
    await tester.tap(find.byIcon(Icons.download_outlined));
    await tester.pump();

    expect(
      container
          .read(offlineDownloadsProvider)
          .valueOrNull
          ?.tasks[track.id]
          ?.status,
      OfflineDownloadStatus.completed,
    );
    final completedButton = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.download_done_outlined),
        matching: find.byType(IconButton),
      ),
    );
    expect(completedButton.onPressed, isNull);
    await tester.tap(
      find.byIcon(Icons.download_done_outlined),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(_TestOfflineDownloadsController.deleteCalls, 0);
  });

  testWidgets('paused and failed downloads remain resumable', (tester) async {
    for (final status in [
      OfflineDownloadStatus.paused,
      OfflineDownloadStatus.failed,
    ]) {
      _TestOfflineDownloadsController.reset(initialStatus: status);
      final container = _container();
      addTearDown(container.dispose);
      await container.read(offlineDownloadsProvider.future);

      await _pumpButton(tester, container);
      final button = tester.widget<IconButton>(find.byType(IconButton));
      expect(button.onPressed, isNotNull);
      await tester.tap(find.byType(IconButton));
      await tester.pump();

      expect(_TestOfflineDownloadsController.resumeCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    }
  });
}

ProviderContainer _container() {
  return ProviderContainer(
    overrides: [
      offlineDownloadsProvider
          .overrideWith(_TestOfflineDownloadsController.new),
    ],
  );
}

Future<void> _pumpButton(
  WidgetTester tester,
  ProviderContainer container,
) {
  return tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: OfflineDownloadButton(
            track: Track(id: 'track-1', title: 'Offline track'),
          ),
        ),
      ),
    ),
  );
}

class _TestOfflineDownloadsController extends OfflineDownloadsController {
  static final _scope = OfflineCacheScope(
    profileId: 'primary',
    userId: 'alice',
    serverBaseUrl: 'https://music.example.test',
  );
  static OfflineDownloadStatus? _initialStatus;
  static var resumeCalls = 0;
  static var deleteCalls = 0;

  static void reset({OfflineDownloadStatus? initialStatus}) {
    _initialStatus = initialStatus;
    resumeCalls = 0;
    deleteCalls = 0;
  }

  @override
  Future<OfflineDownloadsState> build() async {
    final status = _initialStatus;
    return OfflineDownloadsState(
      cacheAvailable: true,
      quotaBytes: 1024,
      tasks: status == null
          ? const {}
          : {
              'track-1': OfflineDownloadTask(
                id: 'offline-download:track-1',
                scope: _scope,
                trackId: 'track-1',
                sourceUri: Uri.parse(
                  'https://music.example.test/api/v1/tracks/track-1/stream',
                ),
                status: status,
              ),
            },
    );
  }

  @override
  Future<void> downloadTrack(Track track, {bool force = false}) async {
    final current = await future;
    state = AsyncData(
      current.copyWith(
        tasks: {
          ...current.tasks,
          track.id: OfflineDownloadTask(
            id: 'offline-download:${track.id}',
            scope: _scope,
            trackId: track.id,
            sourceUri: Uri.parse(
              'https://music.example.test/api/v1/tracks/${track.id}/stream',
            ),
            status: OfflineDownloadStatus.completed,
          ),
        },
      ),
    );
  }

  @override
  Future<void> resume(String trackId) async {
    resumeCalls += 1;
  }

  @override
  Future<void> delete(String trackId) async {
    deleteCalls += 1;
  }
}
