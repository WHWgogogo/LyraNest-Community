import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/config/server_config_controller.dart';
import '../../../core/network/api_client.dart';
import '../../auth/application/auth_controller.dart';
import '../data/dio_offline_download_transport.dart';
import '../data/dio_offline_supplemental_resource_fetcher.dart';
import '../domain/offline_cache_scope.dart';
import '../domain/offline_supplemental_resources.dart';
import 'offline_cache_repository.dart';
import 'offline_download_manager.dart';
import 'offline_playback_source_resolver.dart';

const _offlineDownloadDirectoryKey = 'offline_download_directory.v1';

final offlineDownloadDirectoryStoreProvider =
    Provider<OfflineDownloadDirectoryStore>((ref) {
  return const SharedPreferencesOfflineDownloadDirectoryStore();
});

abstract interface class OfflineDownloadDirectoryStore {
  Future<String?> read();

  Future<void> write(String directoryPath);
}

class SharedPreferencesOfflineDownloadDirectoryStore
    implements OfflineDownloadDirectoryStore {
  const SharedPreferencesOfflineDownloadDirectoryStore();

  @override
  Future<String?> read() async {
    final preferences = await SharedPreferences.getInstance();
    final value = preferences.getString(_offlineDownloadDirectoryKey)?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  @override
  Future<void> write(String directoryPath) async {
    final normalized = directoryPath.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        directoryPath,
        'directoryPath',
        'Must not be empty.',
      );
    }
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_offlineDownloadDirectoryKey, normalized);
  }
}

abstract interface class OfflineDownloadDirectoryPicker {
  Future<String?> selectDirectory({String? initialDirectory});
}

class FileSelectorOfflineDownloadDirectoryPicker
    implements OfflineDownloadDirectoryPicker {
  const FileSelectorOfflineDownloadDirectoryPicker();

  @override
  Future<String?> selectDirectory({String? initialDirectory}) {
    return getDirectoryPath(
      initialDirectory: initialDirectory,
      confirmButtonText: 'Select',
    );
  }
}

final offlineDownloadDirectoryPickerProvider =
    Provider<OfflineDownloadDirectoryPicker>((ref) {
  return const FileSelectorOfflineDownloadDirectoryPicker();
});

class OfflineDownloadDirectory {
  const OfflineDownloadDirectory({
    required this.path,
    required this.usesFallback,
  });

  final String path;
  final bool usesFallback;
}

Future<OfflineDownloadDirectory> resolveOfflineDownloadDirectory({
  String? selectedDirectory,
  Future<Directory> Function()? applicationSupportDirectory,
}) async {
  final selected = selectedDirectory?.trim();
  if (selected != null &&
      selected.isNotEmpty &&
      await isWritableOfflineDownloadDirectory(selected)) {
    return OfflineDownloadDirectory(
      path: Directory(selected).absolute.path,
      usesFallback: false,
    );
  }

  final supportDirectory =
      await (applicationSupportDirectory ?? getApplicationSupportDirectory)();
  final fallback = Directory(
    '${supportDirectory.path}${Platform.pathSeparator}harmony-offline',
  ).absolute;
  await fallback.create(recursive: true);
  return OfflineDownloadDirectory(path: fallback.path, usesFallback: true);
}

Future<bool> isWritableOfflineDownloadDirectory(String directoryPath) async {
  try {
    final directory = Directory(directoryPath).absolute;
    await directory.create(recursive: true);
    final probe = File(
      '${directory.path}${Platform.pathSeparator}.harmony-write-probe',
    );
    await probe.writeAsString('', flush: true);
    await probe.delete();
    return true;
  } on FileSystemException {
    return false;
  }
}

final offlineDownloadDirectoryProvider =
    FutureProvider<OfflineDownloadDirectory>((ref) async {
  final selected =
      await ref.watch(offlineDownloadDirectoryStoreProvider).read();
  return resolveOfflineDownloadDirectory(selectedDirectory: selected);
});

final offlineCacheRootDirectoryProvider = FutureProvider<String>((ref) async {
  return (await ref.watch(offlineDownloadDirectoryProvider.future)).path;
});

final offlineCacheRepositoryProvider =
    FutureProvider<OfflineCacheRepository?>((ref) async {
  final auth = await ref.watch(authControllerProvider.future);
  final config = await ref.watch(serverConfigControllerProvider.future);
  final session = auth.session;
  if (session == null) {
    return null;
  }

  final rootDirectory =
      await ref.watch(offlineCacheRootDirectoryProvider.future);
  return OfflineCacheRepository(
    rootDirectory: rootDirectory,
    scope: OfflineCacheScope(
      profileId: 'primary',
      userId: session.username,
      serverBaseUrl: config.baseUrl,
      serverIdentity: config.cacheScopeId,
    ),
  );
});

final offlineDownloadManagerProvider =
    FutureProvider<OfflineDownloadManager?>((ref) async {
  final cache = await ref.watch(offlineCacheRepositoryProvider.future);
  if (cache == null) {
    return null;
  }
  return OfflineDownloadManager(
    cache: cache,
    transport: DioOfflineDownloadTransport(ref.watch(dioProvider)),
    supplementalResourceFetcher:
        DioOfflineSupplementalResourceFetcher(ref.watch(dioProvider)),
  );
});

final offlinePlaybackSourceResolverProvider =
    Provider<OfflinePlaybackSourceResolver>((ref) {
  return CachedOfflinePlaybackSourceResolver(
    () => ref.read(offlineCacheRepositoryProvider.future),
  );
});

final offlineCachedLyricsProvider =
    FutureProvider.autoDispose.family<OfflineCachedLyrics?, String>(
  (ref, trackId) async {
    final cache = await ref.watch(offlineCacheRepositoryProvider.future);
    return cache?.readLyrics(trackId);
  },
);

final offlineCachedArtworkUriProvider =
    FutureProvider.autoDispose.family<Uri?, String>(
  (ref, trackId) async {
    final cache = await ref.watch(offlineCacheRepositoryProvider.future);
    return cache?.readArtworkUri(trackId);
  },
);
