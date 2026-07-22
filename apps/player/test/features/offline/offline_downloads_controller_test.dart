import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/offline/application/offline_cache_repository.dart';
import 'package:player/features/offline/application/offline_download_manager.dart';
import 'package:player/features/offline/application/offline_downloads_controller.dart';
import 'package:player/features/offline/application/offline_providers.dart';
import 'package:player/features/offline/application/offline_supplemental_resource_fetcher.dart';
import 'package:player/features/offline/data/dio_offline_download_transport.dart';
import 'package:player/features/offline/domain/offline_cache_scope.dart';
import 'package:player/features/offline/domain/offline_download_task.dart';
import 'package:player/features/offline/domain/offline_supplemental_resources.dart';
import 'package:player/features/tracks/domain/track.dart';

void main() {
  test('downloads and deletes media through the registered providers',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'offline-download-controller-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final cache = OfflineCacheRepository(
      rootDirectory: directory.path,
      scope: OfflineCacheScope(
        profileId: 'primary',
        userId: 'alice',
        serverBaseUrl: 'https://music.example.test',
      ),
    );
    final manager = OfflineDownloadManager(
      cache: cache,
      transport: _ImmediateTransport(utf8.encode('offline media')),
    );
    final container = ProviderContainer(
      overrides: [
        offlineCacheRepositoryProvider.overrideWith((ref) async => cache),
        offlineDownloadManagerProvider.overrideWith((ref) async => manager),
        offlineQuotaStoreProvider.overrideWithValue(_MemoryQuotaStore(1024)),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(offlineDownloadsProvider.future);
    expect(initial.cacheAvailable, isTrue);
    expect(initial.quotaBytes, 1024);

    await container.read(offlineDownloadsProvider.notifier).downloadTrack(
          const Track(
            id: 'track-1',
            title: 'Offline track',
            streamUrl: 'https://music.example.test/media/track-1',
          ),
        );
    await _waitUntil(() {
      final state = container.read(offlineDownloadsProvider).valueOrNull;
      return state?.tasks['track-1']?.status ==
              OfflineDownloadStatus.completed &&
          state?.usedBytes == utf8.encode('offline media').length;
    });

    expect(
      container.read(offlineDownloadsProvider).valueOrNull?.usedBytes,
      utf8.encode('offline media').length,
    );
    expect(
      container
          .read(offlineDownloadsProvider)
          .valueOrNull
          ?.tasks['track-1']
          ?.trackSnapshot
          .displayTitle,
      'Offline track',
    );
    expect(await File(cache.mediaPath('track-1')).exists(), isTrue);

    await container.read(offlineDownloadsProvider.notifier).delete('track-1');

    expect(
      container.read(offlineDownloadsProvider).valueOrNull?.tasks,
      isEmpty,
    );
    expect(await File(cache.mediaPath('track-1')).exists(), isFalse);
  });

  test('uses a selected writable directory and falls back safely', () async {
    final directory = await Directory.systemTemp.createTemp(
      'offline-download-directory-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final selected = await resolveOfflineDownloadDirectory(
      selectedDirectory: directory.path,
    );
    expect(selected.path, Directory(directory.path).absolute.path);
    expect(selected.usesFallback, isFalse);

    final notADirectory =
        File('${directory.path}${Platform.pathSeparator}file');
    await notADirectory.writeAsString('not a directory');
    final fallback = await resolveOfflineDownloadDirectory(
      selectedDirectory: notADirectory.path,
      applicationSupportDirectory: () async => directory,
    );

    expect(fallback.usesFallback, isTrue);
    expect(fallback.path, endsWith('harmony-offline'));
  });

  test('backfills supplemental resources for completed legacy downloads',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'offline-download-controller-backfill-',
    );
    addTearDown(() async {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
    });

    final cache = OfflineCacheRepository(
      rootDirectory: directory.path,
      scope: OfflineCacheScope(
        profileId: 'primary',
        userId: 'alice',
        serverBaseUrl: 'https://music.example.test',
      ),
    );
    final media = utf8.encode('offline media');
    await OfflineDownloadManager(
      cache: cache,
      transport: _ImmediateTransport(media),
    ).download(
      _offlineTask(cache),
    );
    final manager = OfflineDownloadManager(
      cache: cache,
      transport: _ImmediateTransport(media),
      supplementalResourceFetcher: const _SupplementalFetcher(),
    );
    final container = ProviderContainer(
      overrides: [
        offlineCacheRepositoryProvider.overrideWith((ref) async => cache),
        offlineDownloadManagerProvider.overrideWith((ref) async => manager),
        offlineQuotaStoreProvider.overrideWithValue(_MemoryQuotaStore(1024)),
      ],
    );
    addTearDown(container.dispose);

    await container.read(offlineDownloadsProvider.future);
    await _waitUntilAsync(() async {
      final entry = await cache.readEntry('track-1');
      return entry?.resources.hasLyrics == true &&
          entry?.resources.hasArtwork == true;
    });

    expect((await cache.readLyrics('track-1'))?.content, 'Offline lyrics');
    expect(await cache.readArtworkUri('track-1'), isNotNull);
    expect(await File(cache.mediaPath('track-1')).readAsBytes(), media);
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for offline download state.');
}

Future<void> _waitUntilAsync(Future<bool> Function() condition) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    if (await condition()) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  throw StateError('Timed out waiting for asynchronous condition.');
}

OfflineDownloadTask _offlineTask(OfflineCacheRepository cache) {
  return OfflineDownloadTask(
    id: 'offline-download:track-1',
    scope: cache.scope,
    trackId: 'track-1',
    sourceUri: Uri.parse('https://music.example.test/media/track-1'),
  );
}

class _MemoryQuotaStore implements OfflineQuotaStore {
  _MemoryQuotaStore(this.value);

  int value;

  @override
  Future<int> read() async => value;

  @override
  Future<void> write(int quotaBytes) async {
    value = quotaBytes;
  }
}

class _ImmediateTransport implements OfflineDownloadTransport {
  _ImmediateTransport(this.bytes);

  final List<int> bytes;

  @override
  Future<OfflineHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    return OfflineHttpResponse(
      statusCode: 200,
      headers: {'content-length': bytes.length.toString()},
      body: Stream<List<int>>.fromIterable([bytes]),
    );
  }
}

class _SupplementalFetcher implements OfflineSupplementalResourceFetcher {
  const _SupplementalFetcher();

  @override
  Future<OfflineArtwork?> fetchArtwork(String trackId) async {
    return const OfflineArtwork(bytes: [1, 2, 3]);
  }

  @override
  Future<OfflineCachedLyrics?> fetchLyrics(String trackId) async {
    return const OfflineCachedLyrics(content: 'Offline lyrics');
  }
}
