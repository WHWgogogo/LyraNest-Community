import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/data/lyrics_api.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/offline/application/offline_cache_repository.dart';
import 'package:player/features/offline/application/offline_download_manager.dart';
import 'package:player/features/offline/application/offline_providers.dart';
import 'package:player/features/offline/application/offline_supplemental_resource_fetcher.dart';
import 'package:player/features/offline/data/dio_offline_download_transport.dart';
import 'package:player/features/offline/domain/offline_cache_scope.dart';
import 'package:player/features/offline/domain/offline_download_task.dart';
import 'package:player/features/offline/domain/offline_media_metadata.dart';
import 'package:player/features/offline/domain/offline_supplemental_resources.dart';

void main() {
  group('offline cache scope and metadata', () {
    test('isolates each profile, user, and server namespace', () {
      final baseline = OfflineCacheScope(
        profileId: 'main',
        userId: 'alice',
        serverBaseUrl: 'https://music.example.test/library/',
      );
      final anotherUser = OfflineCacheScope(
        profileId: 'main',
        userId: 'bob',
        serverBaseUrl: 'https://music.example.test/library/',
      );
      final anotherServer = OfflineCacheScope(
        profileId: 'main',
        userId: 'alice',
        serverBaseUrl: 'https://other.example.test/library/',
      );

      expect(baseline.cacheKey, hasLength(64));
      expect(anotherUser.cacheKey, isNot(baseline.cacheKey));
      expect(anotherServer.cacheKey, isNot(baseline.cacheKey));
      expect(baseline.serverBaseUrl, 'https://music.example.test/library');
    });

    test('shares one namespace for paired server addresses', () {
      const identity = 'music-server-identity';
      final internal = OfflineCacheScope(
        profileId: 'main',
        userId: 'alice',
        serverBaseUrl: 'http://192.168.1.20:8080',
        serverIdentity: identity,
      );
      final external = OfflineCacheScope(
        profileId: 'main',
        userId: 'alice',
        serverBaseUrl: 'https://music.example.test',
        serverIdentity: identity,
      );

      expect(external.cacheKey, internal.cacheKey);
      expect(external, internal);
    });

    test('reads LyraNest ETag, Digest, and media version hashes', () {
      final bytes = utf8.encode('metadata bytes');
      final hash = sha256.convert(bytes).toString();
      final metadata = OfflineMediaMetadata.fromHeaders({
        'Digest': 'sha-256=${base64.encode(sha256.convert(bytes).bytes)}',
        'ETag': '"$hash"',
        'X-Media-Version': hash,
      });

      expect(metadata.expectedSha256, hash);
      expect(
        OfflineMediaMetadata.fromHeaders({
          'Digest': 'sha-256=${base64.encode(sha256.convert(bytes).bytes)}',
        }).expectedSha256,
        hash,
      );
    });
  });

  group('offline download manager', () {
    late Directory temporaryDirectory;
    late OfflineCacheScope scope;

    setUp(() async {
      temporaryDirectory =
          await Directory.systemTemp.createTemp('offline-core-');
      scope = OfflineCacheScope(
        profileId: 'profile-1',
        userId: 'alice',
        serverBaseUrl: 'https://music.example.test',
      );
    });

    tearDown(() async {
      if (await temporaryDirectory.exists()) {
        await temporaryDirectory.delete(recursive: true);
      }
    });

    OfflineCacheRepository repository({DateTime Function()? now}) {
      return OfflineCacheRepository(
        rootDirectory: temporaryDirectory.path,
        scope: scope,
        now: now,
      );
    }

    OfflineDownloadTask task({
      String trackId = 'track-1',
      OfflineTrackSnapshot snapshot = const OfflineTrackSnapshot(),
    }) {
      return OfflineDownloadTask(
        id: 'download-$trackId',
        scope: scope,
        trackId: trackId,
        sourceUri: Uri.parse(
          'https://music.example.test/api/v1/tracks/$trackId/stream',
        ),
        trackSnapshot: snapshot,
      );
    }

    test('resumes a matching .part download and atomically completes it',
        () async {
      final cache = repository();
      final completeBytes = utf8.encode('hello world');
      final firstBytes = utf8.encode('hello ');
      final hash = sha256.convert(completeBytes).toString();
      final metadata = _metadataFor(completeBytes);
      final prior = task();
      await _stagePartial(
        cache,
        task: prior,
        bytes: firstBytes,
        totalBytes: completeBytes.length,
        metadata: metadata,
      );

      final transport = _FakeTransport([
        (uri, headers) {
          expect(uri, prior.sourceUri);
          expect(headers['Range'], 'bytes=${firstBytes.length}-');
          expect(headers['If-Range'], '"$hash"');
          return _response(
            statusCode: 206,
            bytes: utf8.encode('world'),
            headers: _headersFor(
              completeBytes,
              contentRange:
                  'bytes ${firstBytes.length}-${completeBytes.length - 1}/${completeBytes.length}',
            ),
          );
        },
      ]);
      final changes = <OfflineDownloadTask>[];

      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: transport,
      ).download(
        prior,
        maxCacheBytes: 100,
        onTaskChanged: changes.add,
      );

      expect(completed.status, OfflineDownloadStatus.completed);
      expect(completed.downloadedBytes, completeBytes.length);
      expect(completed.metadata.sha256, hash);
      expect(await File(cache.mediaPath(prior.trackId)).readAsBytes(),
          completeBytes);
      expect(await File(cache.partPath(prior.trackId)).exists(), isFalse);
      expect(await File(cache.partStatePath(prior.trackId)).exists(), isFalse);
      expect(
        (await cache.evaluateAvailability(prior.trackId, verifySha256: true))
            .isAvailable,
        isTrue,
      );
      expect(changes.first.status, OfflineDownloadStatus.downloading);
      expect(changes.last.status, OfflineDownloadStatus.completed);
    });

    test('persists a readable track snapshot in the completed index', () async {
      final cache = repository();
      final bytes = utf8.encode('snapshot media');
      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport([
          (uri, headers) => _response(
                statusCode: 200,
                bytes: bytes,
                headers: _headersFor(bytes),
              ),
        ]),
      ).download(
        task(
          snapshot: const OfflineTrackSnapshot(
            title: 'Track title',
            artist: 'Track artist',
            album: 'Track album',
            durationSeconds: 245,
            genres: ['Jazz'],
          ),
        ),
      );

      final entry = await cache.readEntry(completed.trackId);
      expect(entry?.trackSnapshot.displayTitle, 'Track title');
      expect(entry?.trackSnapshot.displayArtist, 'Track artist');
      expect(entry?.trackSnapshot.displayAlbum, 'Track album');
      expect(entry?.trackSnapshot.durationSeconds, 245);
      expect(entry?.trackSnapshot.toTrack(completed.trackId).genres, ['Jazz']);
    });

    test('persists lyrics and artwork without failing media download',
        () async {
      final cache = repository();
      final bytes = utf8.encode('media with supplemental resources');
      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport([
          (uri, headers) => _response(
                statusCode: 200,
                bytes: bytes,
                headers: _headersFor(bytes),
              ),
        ]),
        supplementalResourceFetcher: _FakeSupplementalResourceFetcher(
          lyrics: const OfflineCachedLyrics(
            path: 'lyrics.lrc',
            encoding: 'utf-8',
            content: '[00:01.00]Cached line',
          ),
          artwork: const OfflineArtwork(
            bytes: [1, 2, 3],
            contentType: 'image/jpeg',
          ),
        ),
      ).download(task());

      final entry = await cache.readEntry(completed.trackId);
      final lyrics = await cache.readLyrics(completed.trackId);
      final artworkUri = await cache.readArtworkUri(completed.trackId);

      expect(completed.status, OfflineDownloadStatus.completed);
      expect(lyrics?.content, '[00:01.00]Cached line');
      expect(await File(artworkUri!.toFilePath()).readAsBytes(), [1, 2, 3]);
      expect(entry?.resources.artworkContentType, 'image/jpeg');
      expect(entry?.trackSnapshot.artworkUrl, artworkUri.toString());
      expect(await cache.storageUsage(),
          bytes.length + 3 + utf8.encode(lyrics!.encode()).length);
    });

    test('treats missing supplemental resources as an optional downgrade',
        () async {
      final cache = repository();
      final bytes = utf8.encode('media without supplemental resources');
      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport([
          (uri, headers) => _response(
                statusCode: 200,
                bytes: bytes,
                headers: _headersFor(bytes),
              ),
        ]),
        supplementalResourceFetcher: const _FakeSupplementalResourceFetcher(),
      ).download(task());

      final entry = await cache.readEntry(completed.trackId);
      expect(completed.status, OfflineDownloadStatus.completed);
      expect(entry?.resources.hasLyrics, isFalse);
      expect(entry?.resources.hasArtwork, isFalse);
      expect(await cache.readLyrics(completed.trackId), isNull);
      expect(await cache.readArtworkUri(completed.trackId), isNull);
    });

    test('keeps media when supplemental resource requests fail', () async {
      final cache = repository();
      final bytes = utf8.encode('media when supplemental requests fail');
      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport([
          (uri, headers) => _response(
                statusCode: 200,
                bytes: bytes,
                headers: _headersFor(bytes),
              ),
        ]),
        supplementalResourceFetcher:
            const _FailingSupplementalResourceFetcher(),
      ).download(task());

      expect(completed.status, OfflineDownloadStatus.completed);
      expect(
          await File(cache.mediaPath(completed.trackId)).readAsBytes(), bytes);
      expect((await cache.readEntry(completed.trackId))?.resources.hasLyrics,
          isFalse);
      expect((await cache.readEntry(completed.trackId))?.resources.hasArtwork,
          isFalse);
    });

    test('migrates supplemental files from a legacy index into local resources',
        () async {
      final cache = repository();
      await cache.initialize();
      final bytes = utf8.encode('legacy media');
      const cachedLyrics = OfflineCachedLyrics(
        path: 'legacy.lrc',
        encoding: 'utf-8',
        content: '[00:01.00]Legacy cached line',
      );
      await File(cache.mediaPath('track-1')).writeAsBytes(bytes);
      await File(cache.lyricsPath('track-1'))
          .writeAsString(cachedLyrics.encode());
      await File(cache.artworkPath('track-1')).writeAsBytes([4, 5, 6]);
      final timestamp = DateTime.utc(2026, 7, 21).toIso8601String();
      await File('${cache.scopeDirectory}/index.json').writeAsString(
        jsonEncode({
          'version': 2,
          'scope': scope.toJson(),
          'entries': [
            {
              'trackId': 'track-1',
              'fileName': _legacyMediaFileName('track-1'),
              'bytes': bytes.length,
              'metadata': const OfflineMediaMetadata().toJson(),
              'trackSnapshot': const OfflineTrackSnapshot(
                title: 'Legacy track',
                artworkUrl:
                    'https://music.example.test/api/v1/tracks/track-1/artwork',
              ).toJson(),
              'completedAt': timestamp,
              'lastAccessedAt': timestamp,
            },
          ],
        }),
      );

      final entry = await cache.readEntry('track-1');
      final lyrics = await cache.readLyrics('track-1');
      final artworkUri = await cache.readArtworkUri('track-1');
      final migrated = jsonDecode(
        await File('${cache.scopeDirectory}/index.json').readAsString(),
      ) as Map<String, dynamic>;

      expect(entry?.trackSnapshot.displayTitle, 'Legacy track');
      expect(entry?.resources.hasLyrics, isTrue);
      expect(entry?.resources.hasArtwork, isTrue);
      expect(lyrics?.content, cachedLyrics.content);
      expect(await File(artworkUri!.toFilePath()).readAsBytes(), [4, 5, 6]);
      expect(entry?.trackSnapshot.artworkUrl, artworkUri.toString());
      expect(migrated['version'], 4);
      expect(
          migrated['entries'].single['resources'], isA<Map<String, dynamic>>());
    });

    test('renames indexed legacy supplemental files into canonical paths',
        () async {
      final cache = repository();
      await cache.initialize();
      const trackId = 'track-1';
      final bytes = utf8.encode('legacy supplemental media');
      final trackKey = sha256.convert(utf8.encode(trackId)).toString();
      final legacyLyricsFileName = '$trackKey.legacy.lyrics.json';
      final legacyArtworkFileName = '$trackKey.legacy.artwork';
      const cachedLyrics = OfflineCachedLyrics(
        content: '[00:01.00]Migrated lyrics',
      );
      await File(cache.mediaPath(trackId)).writeAsBytes(bytes);
      await File(
        '${cache.scopeDirectory}${Platform.pathSeparator}$legacyLyricsFileName',
      ).writeAsString(cachedLyrics.encode());
      await File(
        '${cache.scopeDirectory}${Platform.pathSeparator}$legacyArtworkFileName',
      ).writeAsBytes([7, 8, 9]);
      final timestamp = DateTime.utc(2026, 7, 21).toIso8601String();
      await File('${cache.scopeDirectory}/index.json').writeAsString(
        jsonEncode({
          'version': 3,
          'scope': scope.toJson(),
          'entries': [
            {
              'trackId': trackId,
              'fileName': _legacyMediaFileName(trackId),
              'bytes': bytes.length,
              'metadata': const OfflineMediaMetadata().toJson(),
              'resources': {
                'lyricsFileName': legacyLyricsFileName,
                'artworkFileName': legacyArtworkFileName,
                'artworkContentType': 'image/png',
              },
              'trackSnapshot': const OfflineTrackSnapshot(
                title: 'Legacy track',
              ).toJson(),
              'completedAt': timestamp,
              'lastAccessedAt': timestamp,
            },
          ],
        }),
      );

      final entry = await cache.readEntry(trackId);
      final lyrics = await cache.readLyrics(trackId);
      final artworkUri = await cache.readArtworkUri(trackId);

      expect(entry?.resources.lyricsFileName, endsWith('.lyrics.json'));
      expect(entry?.resources.artworkFileName, endsWith('.artwork'));
      expect(lyrics?.content, cachedLyrics.content);
      expect(await File(artworkUri!.toFilePath()).readAsBytes(), [7, 8, 9]);
      expect(
          await File(
            '${cache.scopeDirectory}${Platform.pathSeparator}$legacyLyricsFileName',
          ).exists(),
          isFalse);
      expect(
          await File(
            '${cache.scopeDirectory}${Platform.pathSeparator}$legacyArtworkFileName',
          ).exists(),
          isFalse);
    });

    test('backfills only missing supplemental resources for completed media',
        () async {
      final cache = repository();
      final bytes = utf8.encode('completed media');
      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport([
          (uri, headers) => _response(
                statusCode: 200,
                bytes: bytes,
                headers: _headersFor(bytes),
              ),
        ]),
      ).download(task());

      final refreshed = await OfflineDownloadManager(
        cache: cache,
        transport: _FakeTransport(const []),
        supplementalResourceFetcher: const _FakeSupplementalResourceFetcher(
          lyrics: OfflineCachedLyrics(content: 'Offline lyrics'),
          artwork: OfflineArtwork(bytes: [9, 8, 7]),
        ),
      ).refreshSupplementalResources(completed.trackId);

      expect(
          await File(cache.mediaPath(completed.trackId)).readAsBytes(), bytes);
      expect(refreshed?.resources.hasLyrics, isTrue);
      expect(refreshed?.resources.hasArtwork, isTrue);
      expect((await cache.readLyrics(completed.trackId))?.content,
          'Offline lyrics');
      expect(await cache.readArtworkUri(completed.trackId), isNotNull);
    });

    test('restarts from zero when a resumed request receives a full response',
        () async {
      final cache = repository();
      final oldBytes = utf8.encode('stale');
      final completeBytes = utf8.encode('fresh media');
      final prior = task();
      await _stagePartial(
        cache,
        task: prior,
        bytes: oldBytes,
        totalBytes: oldBytes.length + 99,
        metadata: _metadataFor(oldBytes),
      );

      final transport = _FakeTransport([
        (uri, headers) {
          expect(headers['Range'], 'bytes=${oldBytes.length}-');
          return _response(
            statusCode: 200,
            bytes: completeBytes,
            headers: _headersFor(completeBytes),
          );
        },
      ]);

      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: transport,
      ).download(prior);

      expect(completed.status, OfflineDownloadStatus.completed);
      expect(await File(cache.mediaPath(prior.trackId)).readAsBytes(),
          completeBytes);
      expect(await cache.readPartial(prior.trackId), isNull);
    });

    test('keeps .part state after an interrupted transfer', () async {
      final cache = repository();
      final completeBytes = utf8.encode('hello world');
      final receivedBytes = utf8.encode('hello ');
      final prior = task();
      final transport = _FakeTransport([
        (uri, headers) {
          return OfflineHttpResponse(
            statusCode: 200,
            headers: _headersFor(completeBytes),
            body: _interruptedBody(receivedBytes),
          );
        },
      ]);
      final changes = <OfflineDownloadTask>[];

      await expectLater(
        OfflineDownloadManager(cache: cache, transport: transport).download(
          prior,
          onTaskChanged: changes.add,
        ),
        throwsA(isA<StateError>()),
      );

      final partial = await cache.readPartial(prior.trackId);
      expect(partial?.downloadedBytes, receivedBytes.length);
      expect(await File(cache.partPath(prior.trackId)).readAsBytes(),
          receivedBytes);
      expect(
        (await cache.evaluateAvailability(prior.trackId)).reason,
        OfflineAvailabilityReason.missingEntry,
      );
      expect(changes.last.status, OfflineDownloadStatus.failed);
    });

    test('reconciles a partial state that lags its file', () async {
      final cache = repository();
      final prior = task();
      final firstBytes = utf8.encode('hello ');
      final remainingBytes = utf8.encode('world');
      await _stagePartial(
        cache,
        task: prior,
        bytes: firstBytes,
        totalBytes: firstBytes.length + remainingBytes.length,
        metadata: _metadataFor(firstBytes),
      );
      final writer = await cache.openPartWriter(prior.trackId, append: true);
      await writer.write(remainingBytes);
      await writer.close();

      final partial = await cache.readPartial(prior.trackId);

      expect(
          partial?.downloadedBytes, firstBytes.length + remainingBytes.length);
    });

    test('rejects a completed file with a mismatched server SHA-256', () async {
      final cache = repository();
      final body = utf8.encode('corrupted payload');
      final expected = List<int>.filled(body.length, 0x78);
      final prior = task();
      final transport = _FakeTransport([
        (uri, headers) {
          return _response(
            statusCode: 200,
            bytes: body,
            headers: _headersFor(expected),
          );
        },
      ]);

      await expectLater(
        OfflineDownloadManager(cache: cache, transport: transport)
            .download(prior),
        throwsA(isA<OfflineIntegrityException>()),
      );

      expect(await File(cache.partPath(prior.trackId)).exists(), isFalse);
      expect(await File(cache.mediaPath(prior.trackId)).exists(), isFalse);
      expect(
        (await cache.evaluateAvailability(prior.trackId)).reason,
        OfflineAvailabilityReason.missingEntry,
      );
    });

    test('reports stale versions and same-size checksum corruption', () async {
      final cache = repository();
      final prior = task();
      final bytes = utf8.encode('same-size');
      final mediaVersion = sha256.convert(bytes).toString();
      await _storeCompleted(
        cache,
        task: prior,
        bytes: bytes,
        metadata: OfflineMediaMetadata(
          mediaVersion: mediaVersion,
          sha256: sha256.convert(bytes).toString(),
        ),
      );

      expect(
        (await cache.evaluateAvailability(
          prior.trackId,
          requiredMediaVersion: mediaVersion,
          verifySha256: true,
        ))
            .isAvailable,
        isTrue,
      );
      expect(
        (await cache.evaluateAvailability(
          prior.trackId,
          requiredMediaVersion: List.filled(64, 'b').join(),
        ))
            .reason,
        OfflineAvailabilityReason.mediaVersionMismatch,
      );

      await File(cache.mediaPath(prior.trackId)).writeAsBytes(
        utf8.encode('tamper-ed'),
        flush: true,
      );
      expect(
        (await cache.evaluateAvailability(prior.trackId, verifySha256: true))
            .reason,
        OfflineAvailabilityReason.checksumMismatch,
      );
    });

    test('evicts least recently used completed media to satisfy quota',
        () async {
      var clock = DateTime.utc(2026, 7, 19, 10);
      final cache = repository(now: () => clock);
      final oldest = task(trackId: 'oldest');
      final newest = task(trackId: 'newest');
      await _storeCompleted(
        cache,
        task: oldest,
        bytes: utf8.encode('12345'),
        metadata: _metadataFor(utf8.encode('12345')),
      );
      clock = clock.add(const Duration(minutes: 1));
      await _storeCompleted(
        cache,
        task: newest,
        bytes: utf8.encode('67890'),
        metadata: _metadataFor(utf8.encode('67890')),
      );

      final quota = await cache.enforceQuota(
        maxBytes: 12,
        incomingBytes: 4,
      );

      expect(quota.evictedTrackIds, ['oldest']);
      expect(quota.usedBytes, 5);
      expect(await cache.readEntry(oldest.trackId), isNull);
      expect(await cache.readEntry(newest.trackId), isNotNull);
    });

    test('cancels a response body when quota enforcement rejects it', () async {
      final cache = repository();
      var cancelled = false;
      final controller = StreamController<List<int>>(
        onCancel: () {
          cancelled = true;
        },
      );
      final transport = _FakeTransport([
        (uri, headers) {
          return OfflineHttpResponse(
            statusCode: 200,
            headers: _headersFor(utf8.encode('media')),
            body: controller.stream,
          );
        },
      ]);

      await expectLater(
        OfflineDownloadManager(cache: cache, transport: transport).download(
          task(),
          maxCacheBytes: 1,
        ),
        throwsA(isA<OfflineQuotaExceededException>()),
      );

      expect(cancelled, isTrue);
      await controller.close();
    });

    test('coalesces chunk progress updates', () async {
      final clock = DateTime.utc(2026, 7, 20);
      final cache = repository(now: () => clock);
      final bytes = utf8.encode('chunked media');
      final changes = <OfflineDownloadTask>[];
      final transport = _FakeTransport([
        (uri, headers) {
          return OfflineHttpResponse(
            statusCode: 200,
            headers: _headersFor(bytes),
            body: Stream<List<int>>.fromIterable([
              utf8.encode('chunk'),
              utf8.encode('ed '),
              utf8.encode('media'),
            ]),
          );
        },
      ]);

      final completed = await OfflineDownloadManager(
        cache: cache,
        transport: transport,
        now: () => clock,
      ).download(task(), onTaskChanged: changes.add);

      expect(completed.status, OfflineDownloadStatus.completed);
      expect(changes, hasLength(2));
      expect(changes.first.status, OfflineDownloadStatus.downloading);
      expect(changes.last.status, OfflineDownloadStatus.completed);
    });

    test('pauses an active download without marking it as failed', () async {
      final cache = repository();
      final control = OfflineDownloadControl();
      final body = StreamController<List<int>>();
      final transport = _FakeTransport([
        (uri, headers) {
          return OfflineHttpResponse(
            statusCode: 200,
            headers: _headersFor(utf8.encode('media')),
            body: body.stream,
          );
        },
      ]);
      final changes = <OfflineDownloadTask>[];

      final pending = OfflineDownloadManager(
        cache: cache,
        transport: transport,
      ).download(
        task(),
        control: control,
        onTaskChanged: (next) {
          changes.add(next);
          if (next.status == OfflineDownloadStatus.downloading) {
            control.pause();
          }
        },
      );

      final paused = await pending;

      expect(paused.status, OfflineDownloadStatus.paused);
      expect(changes.last.status, OfflineDownloadStatus.paused);
      expect(await cache.readPartial('track-1'), isNotNull);
    });

    test('Dio transport preserves streamed status and headers', () async {
      final dio = Dio()..httpClientAdapter = _DioStreamAdapter();
      final response = await DioOfflineDownloadTransport(dio).get(
        Uri.parse('https://music.example.test/media'),
      );

      expect(response.statusCode, 206);
      expect(response.header('etag'), '"test-etag"');
      expect(await response.body.expand((chunk) => chunk).toList(), [1, 2, 3]);
    });
  });

  group('offline lyrics fallback', () {
    test('uses persisted lyrics before making a network request', () async {
      final api = LyricsApi(
        Dio(),
        readCachedLyrics: (trackId) async => const Lyrics(
          trackId: 'track-1',
          path: 'cached.lrc',
          encoding: 'utf-8',
          content: 'Cached lyrics',
        ),
      );

      final lyrics = await api.fetchLyrics('track-1');

      expect(lyrics.content, 'Cached lyrics');
      expect(lyrics.path, 'cached.lrc');
    });

    test('lyrics provider returns persisted lyrics before its network fallback',
        () async {
      final container = ProviderContainer(
        overrides: [
          offlineCachedLyricsProvider('track-1').overrideWith(
            (ref) async => const OfflineCachedLyrics(
              path: 'offline.lrc',
              encoding: 'utf-8',
              content: 'Offline lyrics',
            ),
          ),
          lyricsApiProvider.overrideWithValue(_FailingLyricsApi()),
        ],
      );
      addTearDown(container.dispose);

      final lyrics = await container.read(lyricsProvider('track-1').future);

      expect(lyrics.content, 'Offline lyrics');
      expect(lyrics.path, 'offline.lrc');
    });
  });
}

OfflineMediaMetadata _metadataFor(List<int> bytes) {
  return OfflineMediaMetadata.fromHeaders(_headersFor(bytes));
}

Map<String, String> _headersFor(
  List<int> bytes, {
  String? contentRange,
}) {
  final digest = sha256.convert(bytes);
  return {
    'Content-Length': bytes.length.toString(),
    'Digest': 'sha-256=${base64.encode(digest.bytes)}',
    'ETag': '"$digest"',
    'X-Media-Version': digest.toString(),
    if (contentRange != null) 'Content-Range': contentRange,
  };
}

OfflineHttpResponse _response({
  required int statusCode,
  required List<int> bytes,
  required Map<String, String> headers,
}) {
  return OfflineHttpResponse(
    statusCode: statusCode,
    headers: headers,
    body: Stream<List<int>>.fromIterable([bytes]),
  );
}

Stream<List<int>> _interruptedBody(List<int> bytes) async* {
  yield bytes;
  throw StateError('connection lost');
}

Future<void> _stagePartial(
  OfflineCacheRepository cache, {
  required OfflineDownloadTask task,
  required List<int> bytes,
  required int? totalBytes,
  required OfflineMediaMetadata metadata,
}) async {
  final writer = await cache.openPartWriter(task.trackId, append: false);
  await writer.write(bytes);
  await writer.close();
  await cache.writePartial(
    OfflinePartialDownload(
      scope: task.scope,
      trackId: task.trackId,
      sourceUri: task.sourceUri,
      downloadedBytes: bytes.length,
      totalBytes: totalBytes,
      metadata: metadata,
      updatedAt: DateTime.utc(2026, 7, 19),
    ),
  );
}

Future<void> _storeCompleted(
  OfflineCacheRepository cache, {
  required OfflineDownloadTask task,
  required List<int> bytes,
  required OfflineMediaMetadata metadata,
}) async {
  await _stagePartial(
    cache,
    task: task,
    bytes: bytes,
    totalBytes: bytes.length,
    metadata: metadata,
  );
  final partial = await cache.readPartial(task.trackId);
  await cache.completePartial(partial!);
}

class _FakeTransport implements OfflineDownloadTransport {
  _FakeTransport(this._factories);

  final List<OfflineHttpResponse Function(Uri uri, Map<String, String> headers)>
      _factories;
  final List<Map<String, String>> requests = [];

  @override
  Future<OfflineHttpResponse> get(
    Uri uri, {
    Map<String, String> headers = const {},
  }) async {
    requests.add(Map.unmodifiable(headers));
    if (_factories.isEmpty) {
      throw StateError('No response was configured.');
    }
    return _factories.removeAt(0)(uri, headers);
  }
}

class _FakeSupplementalResourceFetcher
    implements OfflineSupplementalResourceFetcher {
  const _FakeSupplementalResourceFetcher({
    this.lyrics,
    this.artwork,
  });

  final OfflineCachedLyrics? lyrics;
  final OfflineArtwork? artwork;

  @override
  Future<OfflineArtwork?> fetchArtwork(String trackId) async => artwork;

  @override
  Future<OfflineCachedLyrics?> fetchLyrics(String trackId) async => lyrics;
}

class _FailingSupplementalResourceFetcher
    implements OfflineSupplementalResourceFetcher {
  const _FailingSupplementalResourceFetcher();

  @override
  Future<OfflineArtwork?> fetchArtwork(String trackId) {
    throw StateError('artwork unavailable');
  }

  @override
  Future<OfflineCachedLyrics?> fetchLyrics(String trackId) {
    throw StateError('lyrics unavailable');
  }
}

class _FailingLyricsApi extends LyricsApi {
  _FailingLyricsApi() : super(Dio());

  @override
  Future<Lyrics> fetchLyrics(String trackId) {
    throw StateError('Network lyrics should not be requested.');
  }
}

String _legacyMediaFileName(String trackId) =>
    '${sha256.convert(utf8.encode(trackId))}.media';

class _DioStreamAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody(
      Stream<Uint8List>.fromIterable([
        Uint8List.fromList([1, 2, 3]),
      ]),
      206,
      headers: {
        'etag': ['"test-etag"'],
      },
    );
  }
}
