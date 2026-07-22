import 'dart:async';

import '../data/dio_offline_download_transport.dart';
import '../domain/offline_download_task.dart';
import '../domain/offline_media_metadata.dart';
import 'offline_cache_repository.dart';
import 'offline_sha256_verifier.dart';
import 'offline_supplemental_resource_fetcher.dart';

typedef OfflineDownloadTaskListener = void Function(OfflineDownloadTask task);

class OfflineDownloadControl {
  final Completer<void> _pauseCompleter = Completer<void>();

  bool get isPauseRequested => _pauseCompleter.isCompleted;

  Future<void> get whenPaused => _pauseCompleter.future;

  void pause() {
    if (_pauseCompleter.isCompleted) {
      return;
    }
    _pauseCompleter.complete();
  }
}

class OfflineDownloadException implements Exception {
  OfflineDownloadException(this.message);

  final String message;

  @override
  String toString() => 'OfflineDownloadException: $message';
}

class OfflineIntegrityException extends OfflineDownloadException {
  OfflineIntegrityException({
    required this.expectedSha256,
    required this.actualSha256,
  }) : super('Downloaded media SHA-256 does not match server metadata.');

  final String expectedSha256;
  final String actualSha256;
}

class OfflineDownloadPausedException extends OfflineDownloadException {
  OfflineDownloadPausedException() : super('Download paused.');
}

class OfflineDownloadManager {
  OfflineDownloadManager({
    required OfflineCacheRepository cache,
    required OfflineDownloadTransport transport,
    OfflineSha256Verifier? sha256Verifier,
    OfflineSupplementalResourceFetcher? supplementalResourceFetcher,
    DateTime Function()? now,
  })  : _cache = cache,
        _transport = transport,
        _sha256Verifier = sha256Verifier ?? const CryptoOfflineSha256Verifier(),
        _supplementalResourceFetcher = supplementalResourceFetcher,
        _now = now ?? DateTime.now;

  final OfflineCacheRepository _cache;
  final OfflineDownloadTransport _transport;
  final OfflineSha256Verifier _sha256Verifier;
  final OfflineSupplementalResourceFetcher? _supplementalResourceFetcher;
  final DateTime Function() _now;

  static const _partialPersistenceInterval = Duration(seconds: 1);
  static const _taskUpdateInterval = Duration(milliseconds: 250);

  Future<OfflineCacheEntry?> refreshSupplementalResources(
    String trackId,
  ) async {
    final entry = await _cache.readEntry(trackId);
    if (entry == null) {
      return null;
    }
    await _downloadSupplementalResources(trackId, onlyMissing: true);
    return _cache.readEntry(trackId);
  }

  Future<OfflineDownloadTask> download(
    OfflineDownloadTask task, {
    int? maxCacheBytes,
    bool force = false,
    OfflineDownloadControl? control,
    OfflineDownloadTaskListener? onTaskChanged,
  }) async {
    if (task.scope != _cache.scope) {
      throw ArgumentError.value(task.scope, 'task.scope', 'Wrong cache scope.');
    }
    if (maxCacheBytes != null && maxCacheBytes < 0) {
      throw ArgumentError.value(maxCacheBytes, 'maxCacheBytes');
    }

    OfflineDownloadTask current = task;
    OfflinePartialDownload? recoverablePartial;
    void emit(OfflineDownloadTask next) {
      current = next;
      onTaskChanged?.call(next);
    }

    try {
      if (control?.isPauseRequested == true) {
        emit(current.copyWith(status: OfflineDownloadStatus.paused));
        return current;
      }
      await _cache.initialize();
      if (force) {
        await _cache.removeEntry(task.trackId);
      } else {
        final available = await _cache.evaluateAvailability(
          task.trackId,
          requiredMediaVersion: task.metadata.mediaVersion,
        );
        if (available.isAvailable) {
          await _cache.markAccessed(task.trackId);
          await _downloadSupplementalResources(task.trackId);
          final entry = await _cache.readEntry(task.trackId);
          emit(
            current.copyWith(
              status: OfflineDownloadStatus.completed,
              downloadedBytes: entry?.bytes ?? available.entry!.bytes,
              totalBytes: entry?.bytes ?? available.entry!.bytes,
              metadata: entry?.metadata ?? available.entry!.metadata,
              trackSnapshot: entry?.trackSnapshot ?? current.trackSnapshot,
              clearError: true,
            ),
          );
          return current;
        }
      }

      var partial = await _cache.readPartial(task.trackId);
      if (partial == null || partial.sourceUri != task.sourceUri) {
        await _cache.discardPartial(task.trackId);
        partial = null;
      }

      var restartCount = 0;
      while (true) {
        _throwIfPaused(control);
        final previousBytes = partial?.downloadedBytes ?? 0;
        final response = await _transport.get(
          task.sourceUri,
          headers: _resumeHeaders(partial),
        );
        StreamIterator<List<int>>? responseBody;
        try {
          if (response.statusCode == 416 &&
              previousBytes > 0 &&
              restartCount == 0) {
            await _cache.discardPartial(task.trackId);
            partial = null;
            restartCount++;
            continue;
          }
          if (response.statusCode != 200 && response.statusCode != 206) {
            throw OfflineDownloadException(
              'Media server returned HTTP ${response.statusCode}.',
            );
          }

          final responseMetadata =
              OfflineMediaMetadata.fromHeaders(response.headers);
          final metadata = responseMetadata.mergeFallback(
            partial?.metadata ?? task.metadata,
          );
          final trackSnapshot = task.trackSnapshot;
          final range =
              _OfflineContentRange.tryParse(response.header('content-range'));
          var append = false;
          var downloadedBytes = previousBytes;
          int? totalBytes;

          if (response.statusCode == 206) {
            if (range == null || range.start != previousBytes) {
              if (restartCount == 0) {
                await _cache.discardPartial(task.trackId);
                partial = null;
                restartCount++;
                continue;
              }
              throw OfflineDownloadException('Invalid Content-Range response.');
            }
            final previousExpected = partial?.metadata.expectedSha256;
            final responseExpected = metadata.expectedSha256;
            if (previousExpected != null &&
                responseExpected != null &&
                previousExpected != responseExpected) {
              if (restartCount == 0) {
                await _cache.discardPartial(task.trackId);
                partial = null;
                restartCount++;
                continue;
              }
              throw OfflineDownloadException('Media changed during resume.');
            }
            append = previousBytes > 0;
            final remainingBytes = _contentLength(
              response.header('content-length'),
            );
            totalBytes = range.totalBytes ??
                (remainingBytes == null
                    ? null
                    : previousBytes + remainingBytes);
          } else {
            if (previousBytes > 0) {
              await _cache.discardPartial(task.trackId);
            }
            downloadedBytes = 0;
            totalBytes = _contentLength(response.header('content-length'));
          }

          if (maxCacheBytes != null) {
            if (totalBytes == null) {
              throw OfflineDownloadException(
                'Cannot enforce a cache quota without Content-Length.',
              );
            }
            await _cache.enforceQuota(
              maxBytes: maxCacheBytes,
              incomingBytes: totalBytes - downloadedBytes,
              protectedTrackIds: {task.trackId},
            );
          }

          var staged = OfflinePartialDownload(
            scope: task.scope,
            trackId: task.trackId,
            sourceUri: task.sourceUri,
            downloadedBytes: downloadedBytes,
            totalBytes: totalBytes,
            metadata: metadata,
            trackSnapshot: trackSnapshot,
            updatedAt: _now().toUtc(),
          );
          recoverablePartial = staged;
          await _cache.writePartial(staged);
          var lastPartialPersistedAt = staged.updatedAt;
          var lastTaskUpdateAt = staged.updatedAt;
          emit(
            current.copyWith(
              status: OfflineDownloadStatus.downloading,
              downloadedBytes: downloadedBytes,
              totalBytes: totalBytes,
              metadata: metadata,
              clearError: true,
            ),
          );

          final writer =
              await _cache.openPartWriter(task.trackId, append: append);
          try {
            responseBody = StreamIterator<List<int>>(response.body);
            while (await _moveNext(responseBody, control)) {
              _throwIfPaused(control);
              final chunk = responseBody.current;
              await writer.write(chunk);
              downloadedBytes += chunk.length;
              staged = staged.copyWith(
                downloadedBytes: downloadedBytes,
                updatedAt: _now().toUtc(),
              );
              recoverablePartial = staged;
              if (_hasElapsed(
                lastPartialPersistedAt,
                staged.updatedAt,
                _partialPersistenceInterval,
              )) {
                await _cache.writePartial(staged);
                lastPartialPersistedAt = staged.updatedAt;
              }
              if (_hasElapsed(
                lastTaskUpdateAt,
                staged.updatedAt,
                _taskUpdateInterval,
              )) {
                emit(
                  current.copyWith(
                    downloadedBytes: downloadedBytes,
                    totalBytes: totalBytes,
                    metadata: metadata,
                  ),
                );
                lastTaskUpdateAt = staged.updatedAt;
              }
            }
          } finally {
            await writer.close();
          }

          _throwIfPaused(control);
          if (totalBytes != null && downloadedBytes != totalBytes) {
            throw OfflineDownloadException(
              'Download ended at $downloadedBytes bytes; expected $totalBytes.',
            );
          }

          await _cache.writePartial(staged);
          final actualSha256 = await _cache.digestPart(
            task.trackId,
            _sha256Verifier,
          );
          final expectedSha256 = metadata.expectedSha256;
          if (expectedSha256 != null && actualSha256 != expectedSha256) {
            await _cache.discardPartial(task.trackId);
            recoverablePartial = null;
            throw OfflineIntegrityException(
              expectedSha256: expectedSha256,
              actualSha256: actualSha256,
            );
          }

          staged = staged.copyWith(
            metadata: metadata.copyWith(sha256: actualSha256),
            updatedAt: _now().toUtc(),
          );
          recoverablePartial = staged;
          await _cache.writePartial(staged);
          final entry = await _cache.completePartial(staged);
          recoverablePartial = null;
          await _downloadSupplementalResources(task.trackId);
          final persisted = await _cache.readEntry(task.trackId);
          emit(
            current.copyWith(
              status: OfflineDownloadStatus.completed,
              downloadedBytes: entry.bytes,
              totalBytes: entry.bytes,
              metadata: entry.metadata,
              trackSnapshot: persisted?.trackSnapshot ?? current.trackSnapshot,
              clearError: true,
            ),
          );
          return current;
        } finally {
          final activeResponseBody = responseBody;
          if (activeResponseBody == null) {
            await response.body.listen(null).cancel();
          } else if (control?.isPauseRequested == true) {
            unawaited(activeResponseBody.cancel());
          } else {
            await activeResponseBody.cancel();
          }
        }
      }
    } on OfflineDownloadPausedException {
      final partial = recoverablePartial;
      if (partial != null) {
        try {
          await _cache.writePartial(partial);
        } catch (_) {}
      }
      emit(
        current.copyWith(
          status: OfflineDownloadStatus.paused,
          clearError: true,
        ),
      );
      return current;
    } catch (error) {
      final partial = recoverablePartial;
      if (partial != null) {
        try {
          await _cache.writePartial(partial);
        } catch (_) {}
      }
      emit(
        current.copyWith(
          status: OfflineDownloadStatus.failed,
          errorMessage: error.toString(),
        ),
      );
      rethrow;
    }
  }

  bool _hasElapsed(
    DateTime previous,
    DateTime current,
    Duration interval,
  ) {
    return current.difference(previous) >= interval;
  }

  Future<bool> _moveNext(
    StreamIterator<List<int>> body,
    OfflineDownloadControl? control,
  ) {
    if (control == null) {
      return body.moveNext();
    }
    if (control.isPauseRequested) {
      throw OfflineDownloadPausedException();
    }
    return Future.any<bool>([
      body.moveNext(),
      control.whenPaused.then<bool>((_) {
        throw OfflineDownloadPausedException();
      }),
    ]);
  }

  void _throwIfPaused(OfflineDownloadControl? control) {
    if (control?.isPauseRequested == true) {
      throw OfflineDownloadPausedException();
    }
  }

  Map<String, String> _resumeHeaders(OfflinePartialDownload? partial) {
    if (partial == null || partial.downloadedBytes == 0) {
      return const {};
    }
    final headers = <String, String>{
      'Range': 'bytes=${partial.downloadedBytes}-',
    };
    final eTag = partial.metadata.eTag;
    if (eTag != null && eTag.isNotEmpty) {
      headers['If-Range'] = eTag;
    }
    return headers;
  }

  Future<void> _downloadSupplementalResources(
    String trackId, {
    bool onlyMissing = false,
  }) async {
    final fetcher = _supplementalResourceFetcher;
    if (fetcher == null) {
      return;
    }

    final existing = await _cache.readEntry(trackId);
    if (existing == null) {
      return;
    }
    if (!onlyMissing || !existing.resources.hasLyrics) {
      try {
        final lyrics = await fetcher.fetchLyrics(trackId);
        await _cache.writeSupplementalResources(
          trackId,
          lyrics: lyrics,
          replaceLyrics: true,
        );
      } catch (_) {}
    }
    if (!onlyMissing || !existing.resources.hasArtwork) {
      try {
        final artwork = await fetcher.fetchArtwork(trackId);
        await _cache.writeSupplementalResources(
          trackId,
          artworkBytes: artwork?.bytes,
          artworkContentType: artwork?.contentType,
          replaceArtwork: true,
        );
      } catch (_) {}
    }
  }
}

class _OfflineContentRange {
  const _OfflineContentRange({
    required this.start,
    required this.end,
    required this.totalBytes,
  });

  final int start;
  final int end;
  final int? totalBytes;

  static _OfflineContentRange? tryParse(String? value) {
    if (value == null) {
      return null;
    }
    final match =
        RegExp(r'^bytes\s+(\d+)-(\d+)/(\d+|\*)$').firstMatch(value.trim());
    if (match == null) {
      return null;
    }
    final start = int.tryParse(match.group(1)!);
    final end = int.tryParse(match.group(2)!);
    final total = match.group(3) == '*' ? null : int.tryParse(match.group(3)!);
    if (start == null || end == null || end < start) {
      return null;
    }
    if (total != null && total <= end) {
      return null;
    }
    return _OfflineContentRange(start: start, end: end, totalBytes: total);
  }
}

int? _contentLength(String? value) {
  final length = int.tryParse(value?.trim() ?? '');
  return length == null || length < 0 ? null : length;
}
