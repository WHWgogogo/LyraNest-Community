import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../tracks/domain/track.dart';
import '../domain/offline_download_task.dart';
import '../domain/offline_media_metadata.dart';
import 'offline_cache_repository.dart';
import 'offline_download_manager.dart';
import 'offline_providers.dart';

const defaultOfflineCacheQuotaBytes = 5 * 1024 * 1024 * 1024;
const _offlineCacheQuotaKey = 'offline_cache_quota_bytes.v1';

final offlineQuotaStoreProvider = Provider<OfflineQuotaStore>((ref) {
  return SharedPreferencesOfflineQuotaStore();
});

abstract interface class OfflineQuotaStore {
  Future<int> read();

  Future<void> write(int quotaBytes);
}

class SharedPreferencesOfflineQuotaStore implements OfflineQuotaStore {
  @override
  Future<int> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getInt(_offlineCacheQuotaKey);
    return value == null || value < 0 ? defaultOfflineCacheQuotaBytes : value;
  }

  @override
  Future<void> write(int quotaBytes) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setInt(_offlineCacheQuotaKey, quotaBytes);
  }
}

@immutable
class OfflineDownloadsState {
  const OfflineDownloadsState({
    required this.quotaBytes,
    this.usedBytes = 0,
    this.tasks = const {},
    this.cacheAvailable = false,
    this.downloadDirectory = '',
    this.usesFallbackDirectory = false,
  });

  final int quotaBytes;
  final int usedBytes;
  final Map<String, OfflineDownloadTask> tasks;
  final bool cacheAvailable;
  final String downloadDirectory;
  final bool usesFallbackDirectory;

  List<OfflineDownloadTask> get orderedTasks {
    final result = tasks.values.toList()
      ..sort((left, right) => left.trackId.compareTo(right.trackId));
    return List.unmodifiable(result);
  }

  OfflineDownloadsState copyWith({
    int? quotaBytes,
    int? usedBytes,
    Map<String, OfflineDownloadTask>? tasks,
    bool? cacheAvailable,
    String? downloadDirectory,
    bool? usesFallbackDirectory,
  }) {
    return OfflineDownloadsState(
      quotaBytes: quotaBytes ?? this.quotaBytes,
      usedBytes: usedBytes ?? this.usedBytes,
      tasks: Map.unmodifiable(tasks ?? this.tasks),
      cacheAvailable: cacheAvailable ?? this.cacheAvailable,
      downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      usesFallbackDirectory:
          usesFallbackDirectory ?? this.usesFallbackDirectory,
    );
  }
}

final offlineDownloadsProvider =
    AsyncNotifierProvider<OfflineDownloadsController, OfflineDownloadsState>(
  OfflineDownloadsController.new,
);

class OfflineDownloadsController extends AsyncNotifier<OfflineDownloadsState> {
  final Map<String, OfflineDownloadControl> _controls = {};
  final Map<String, Future<void>> _activeDownloads = {};

  @override
  Future<OfflineDownloadsState> build() async {
    ref.onDispose(_pauseActiveDownloads);

    final quotaBytes = await ref.read(offlineQuotaStoreProvider).read();
    final cache = await ref.watch(offlineCacheRepositoryProvider.future);
    if (cache == null) {
      final directory =
          await ref.watch(offlineDownloadDirectoryProvider.future);
      return OfflineDownloadsState(
        quotaBytes: quotaBytes,
        downloadDirectory: directory.path,
        usesFallbackDirectory: directory.usesFallback,
      );
    }

    await cache.initialize();
    final entries = await cache.listEntries();
    final partials = await cache.listPartials();
    final tasks = <String, OfflineDownloadTask>{
      for (final entry in entries)
        entry.trackId: OfflineDownloadTask(
          id: _taskId(entry.trackId),
          scope: cache.scope,
          trackId: entry.trackId,
          sourceUri: _streamUri(
            baseUrl: cache.scope.serverBaseUrl,
            trackId: entry.trackId,
          ),
          status: OfflineDownloadStatus.completed,
          downloadedBytes: entry.bytes,
          totalBytes: entry.bytes,
          metadata: entry.metadata,
          trackSnapshot: entry.trackSnapshot,
        ),
      for (final partial in partials)
        partial.trackId: OfflineDownloadTask(
          id: _taskId(partial.trackId),
          scope: cache.scope,
          trackId: partial.trackId,
          sourceUri: partial.sourceUri,
          status: OfflineDownloadStatus.paused,
          downloadedBytes: partial.downloadedBytes,
          totalBytes: partial.totalBytes,
          metadata: partial.metadata,
          trackSnapshot: partial.trackSnapshot,
        ),
    };
    final initialState = OfflineDownloadsState(
      quotaBytes: quotaBytes,
      usedBytes: await cache.storageUsage(),
      tasks: Map.unmodifiable(tasks),
      cacheAvailable: true,
      downloadDirectory: cache.rootDirectory,
    );
    _backfillSupplementalResources(entries);
    return initialState;
  }

  Future<void> downloadTrack(Track track, {bool force = false}) async {
    final current = await future;
    final cache = await _requireCache();
    final existing = current.tasks[track.id];
    if (existing?.status == OfflineDownloadStatus.downloading) {
      return;
    }

    final task = OfflineDownloadTask(
      id: existing?.id ?? _taskId(track.id),
      scope: cache.scope,
      trackId: track.id,
      sourceUri: _sourceUriFor(track, cache),
      status: OfflineDownloadStatus.queued,
      downloadedBytes: force ? 0 : existing?.downloadedBytes ?? 0,
      totalBytes: force ? null : existing?.totalBytes,
      metadata: force
          ? const OfflineMediaMetadata()
          : existing?.metadata ?? const OfflineMediaMetadata(),
      trackSnapshot: OfflineTrackSnapshot.fromTrack(track),
    );
    _setTask(task);
    _startDownload(task, force: force);
  }

  Future<void> pause(String trackId) async {
    final current = await future;
    final task = current.tasks[trackId];
    if (task == null || task.status != OfflineDownloadStatus.downloading) {
      return;
    }
    _controls[trackId]?.pause();
    _setTask(task.copyWith(status: OfflineDownloadStatus.paused));
  }

  Future<void> resume(String trackId) async {
    final current = await future;
    final task = current.tasks[trackId];
    if (task == null ||
        task.status == OfflineDownloadStatus.completed ||
        task.status == OfflineDownloadStatus.downloading) {
      return;
    }
    _setTask(
      task.copyWith(
        status: OfflineDownloadStatus.queued,
        clearError: true,
      ),
    );
    _startDownload(task.copyWith(status: OfflineDownloadStatus.queued));
  }

  Future<void> delete(String trackId) async {
    final control = _controls[trackId];
    control?.pause();
    final active = _activeDownloads[trackId];
    if (active != null) {
      await active;
    }

    final cache = await _requireCache();
    await Future.wait([
      cache.removeEntry(trackId),
      cache.discardPartial(trackId),
    ]);
    final current = await future;
    final tasks = Map<String, OfflineDownloadTask>.of(current.tasks)
      ..remove(trackId);
    state = AsyncData(
      current.copyWith(
        tasks: tasks,
        usedBytes: await cache.storageUsage(),
      ),
    );
    _invalidateSupplementalResources(trackId);
  }

  Future<void> setQuotaBytes(int quotaBytes) async {
    if (quotaBytes < 0) {
      throw RangeError.value(quotaBytes, 'quotaBytes');
    }
    final current = await future;
    await ref.read(offlineQuotaStoreProvider).write(quotaBytes);
    state = AsyncData(current.copyWith(quotaBytes: quotaBytes));
  }

  Future<bool> selectDownloadDirectory() async {
    final current = await future;
    final selected =
        await ref.read(offlineDownloadDirectoryPickerProvider).selectDirectory(
              initialDirectory: current.downloadDirectory.isEmpty
                  ? null
                  : current.downloadDirectory,
            );
    if (selected == null || selected.trim().isEmpty) {
      return false;
    }

    final resolved = await resolveOfflineDownloadDirectory(
      selectedDirectory: selected,
    );
    if (resolved.usesFallback) {
      return false;
    }

    _pauseActiveDownloads();
    await Future.wait(List<Future<void>>.of(_activeDownloads.values));
    await ref.read(offlineDownloadDirectoryStoreProvider).write(resolved.path);
    ref.invalidate(offlineDownloadDirectoryProvider);
    ref.invalidate(offlineCacheRootDirectoryProvider);
    ref.invalidate(offlineCacheRepositoryProvider);
    ref.invalidate(offlineDownloadManagerProvider);
    ref.invalidateSelf();
    return true;
  }

  void _startDownload(OfflineDownloadTask task, {bool force = false}) {
    if (_activeDownloads.containsKey(task.trackId)) {
      return;
    }

    final control = OfflineDownloadControl();
    _controls[task.trackId] = control;
    late final Future<void> work;
    work = _runDownload(task, control, force: force).whenComplete(() {
      if (identical(_activeDownloads[task.trackId], work)) {
        _activeDownloads.remove(task.trackId);
        _controls.remove(task.trackId);
      }
    });
    _activeDownloads[task.trackId] = work;
    unawaited(work.catchError((Object _) {}));
  }

  Future<void> _runDownload(
    OfflineDownloadTask task,
    OfflineDownloadControl control, {
    required bool force,
  }) async {
    try {
      final manager = await ref.read(offlineDownloadManagerProvider.future);
      final current = state.valueOrNull;
      if (manager == null || current == null) {
        return;
      }
      await manager.download(
        task,
        maxCacheBytes: current.quotaBytes,
        force: force,
        control: control,
        onTaskChanged: (next) {
          if (identical(_controls[next.trackId], control)) {
            _setTask(next);
            if (next.status == OfflineDownloadStatus.completed) {
              _invalidateSupplementalResources(next.trackId);
            }
          }
        },
      );
    } catch (_) {
      // The manager has already emitted the failed task state.
    } finally {
      await _refreshUsage();
    }
  }

  Future<void> _refreshUsage() async {
    final cache = await ref.read(offlineCacheRepositoryProvider.future);
    final current = state.valueOrNull;
    if (cache == null || current == null) {
      return;
    }
    state = AsyncData(
      current.copyWith(usedBytes: await cache.storageUsage()),
    );
  }

  Future<OfflineCacheRepository> _requireCache() async {
    final cache = await ref.read(offlineCacheRepositoryProvider.future);
    if (cache == null) {
      throw StateError('Sign in before managing offline downloads.');
    }
    return cache;
  }

  void _setTask(OfflineDownloadTask task) {
    final current = state.valueOrNull;
    if (current == null) {
      return;
    }
    final tasks = Map<String, OfflineDownloadTask>.of(current.tasks)
      ..[task.trackId] = task;
    state = AsyncData(current.copyWith(tasks: tasks));
  }

  void _invalidateSupplementalResources(String trackId) {
    ref.invalidate(offlineCachedLyricsProvider(trackId));
    ref.invalidate(offlineCachedArtworkUriProvider(trackId));
  }

  void _backfillSupplementalResources(List<OfflineCacheEntry> entries) {
    final trackIds = entries
        .where(
          (entry) => !entry.resources.hasLyrics || !entry.resources.hasArtwork,
        )
        .map((entry) => entry.trackId)
        .toList(growable: false);
    if (trackIds.isEmpty) {
      return;
    }

    unawaited(_refreshMissingSupplementalResources(trackIds));
  }

  Future<void> _refreshMissingSupplementalResources(
    List<String> trackIds,
  ) async {
    final manager = await ref.read(offlineDownloadManagerProvider.future);
    if (manager == null) {
      return;
    }
    var changed = false;
    for (final trackId in trackIds) {
      final entry = await manager.refreshSupplementalResources(trackId);
      if (entry == null) {
        continue;
      }
      _invalidateSupplementalResources(trackId);
      changed = true;
    }
    if (changed) {
      await _refreshUsage();
    }
  }

  void _pauseActiveDownloads() {
    for (final control in _controls.values) {
      control.pause();
    }
  }
}

String _taskId(String trackId) => 'offline-download:$trackId';

Uri _sourceUriFor(Track track, OfflineCacheRepository cache) {
  final configured = Uri.tryParse(track.streamUrl ?? '');
  if (configured != null &&
      configured.hasScheme &&
      (configured.scheme == 'http' || configured.scheme == 'https')) {
    return configured;
  }
  return _streamUri(
    baseUrl: cache.scope.serverBaseUrl,
    trackId: track.id,
  );
}

Uri _streamUri({
  required String baseUrl,
  required String trackId,
}) {
  final baseUri = Uri.parse(baseUrl);
  return Uri(
    scheme: baseUri.scheme,
    userInfo: baseUri.userInfo,
    host: baseUri.host,
    port: baseUri.hasPort ? baseUri.port : null,
    pathSegments: ['api', 'v1', 'tracks', trackId, 'stream'],
  );
}
