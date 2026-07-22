import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/offline_file_system.dart';
import '../domain/offline_cache_scope.dart';
import '../domain/offline_download_task.dart';
import '../domain/offline_supplemental_resources.dart';
import 'offline_sha256_verifier.dart';

class OfflineQuotaExceededException implements Exception {
  OfflineQuotaExceededException({
    required this.maxBytes,
    required this.requiredBytes,
    required this.usedBytes,
  });

  final int maxBytes;
  final int requiredBytes;
  final int usedBytes;

  @override
  String toString() {
    return 'Offline cache quota exceeded: $usedBytes bytes used, '
        '$requiredBytes additional bytes requested, $maxBytes byte limit.';
  }
}

class OfflineCacheRepository {
  OfflineCacheRepository({
    required this.rootDirectory,
    required this.scope,
    OfflineFileSystem? fileSystem,
    OfflineSha256Verifier? sha256Verifier,
    DateTime Function()? now,
  })  : _fileSystem = fileSystem ?? const DartOfflineFileSystem(),
        _sha256Verifier = sha256Verifier ?? const CryptoOfflineSha256Verifier(),
        _now = now ?? DateTime.now;

  final String rootDirectory;
  final OfflineCacheScope scope;
  final OfflineFileSystem _fileSystem;
  final OfflineSha256Verifier _sha256Verifier;
  final DateTime Function() _now;

  static const _indexVersion = 4;

  String get scopeDirectory => _join(rootDirectory, scope.cacheKey);

  String partPath(String trackId) =>
      _join(scopeDirectory, '${_trackKey(trackId)}.part');

  String partStatePath(String trackId) =>
      _join(scopeDirectory, '${_trackKey(trackId)}.part.json');

  String mediaPath(String trackId) =>
      _join(scopeDirectory, _mediaFileName(trackId));

  String lyricsPath(String trackId) =>
      _join(scopeDirectory, _lyricsFileName(trackId));

  String artworkPath(String trackId) =>
      _join(scopeDirectory, _artworkFileName(trackId));

  String get _indexPath => _join(scopeDirectory, 'index.json');

  Future<void> initialize() => _fileSystem.createDirectory(scopeDirectory);

  Future<OfflinePartialDownload?> readPartial(String trackId) async {
    await initialize();
    final partPathValue = partPath(trackId);
    final statePath = partStatePath(trackId);
    if (!await _fileSystem.fileExists(partPathValue) ||
        !await _fileSystem.fileExists(statePath)) {
      return null;
    }

    try {
      final decoded = jsonDecode(await _fileSystem.readString(statePath));
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      final partial = OfflinePartialDownload.fromJson(
        decoded.cast<String, Object?>(),
      );
      final partBytes = await _fileSystem.fileLength(partPathValue);
      if (partial.scope != scope ||
          partial.trackId != trackId ||
          (partial.totalBytes != null && partBytes > partial.totalBytes!)) {
        return null;
      }
      return partial.copyWith(downloadedBytes: partBytes);
    } on FormatException {
      return null;
    }
  }

  Future<void> writePartial(OfflinePartialDownload partial) async {
    if (partial.scope != scope) {
      throw ArgumentError.value(partial.scope, 'partial.scope', 'Wrong scope.');
    }
    await initialize();
    await _writeJsonAtomically(
      partStatePath(partial.trackId),
      partial.toJson(),
    );
  }

  Future<OfflineFileWriter> openPartWriter(
    String trackId, {
    required bool append,
  }) {
    return _fileSystem.openWrite(partPath(trackId), append: append);
  }

  Future<String> digestPart(
    String trackId,
    OfflineSha256Verifier verifier,
  ) {
    return verifier.digestFile(_fileSystem, partPath(trackId));
  }

  Future<void> discardPartial(String trackId) async {
    await Future.wait([
      _fileSystem.deleteFile(partPath(trackId)),
      _fileSystem.deleteFile(partStatePath(trackId)),
    ]);
  }

  Future<OfflineCacheEntry?> readEntry(String trackId) async {
    final entries = await _readIndex();
    return entries[trackId];
  }

  Future<List<OfflineCacheEntry>> listEntries() async {
    final entries = (await _readIndex()).values.toList()
      ..sort(
        (left, right) => right.lastAccessedAt.compareTo(left.lastAccessedAt),
      );
    return List.unmodifiable(entries);
  }

  Future<List<OfflinePartialDownload>> listPartials() async {
    await initialize();
    final partials = <OfflinePartialDownload>[];
    final files = await _fileSystem.listFiles(scopeDirectory);
    for (final file in files) {
      if (!file.path.endsWith('.part.json')) {
        continue;
      }
      try {
        final decoded = jsonDecode(await _fileSystem.readString(file.path));
        if (decoded is! Map<Object?, Object?>) {
          continue;
        }
        final candidate = OfflinePartialDownload.fromJson(
          decoded.cast<String, Object?>(),
        );
        if (candidate.scope != scope || candidate.trackId.isEmpty) {
          continue;
        }
        final partial = await readPartial(candidate.trackId);
        if (partial != null) {
          partials.add(partial);
        }
      } on FormatException {
        continue;
      }
    }
    partials.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return List.unmodifiable(partials);
  }

  Future<OfflineCacheEntry> completePartial(
    OfflinePartialDownload partial,
  ) async {
    if (partial.scope != scope) {
      throw ArgumentError.value(partial.scope, 'partial.scope', 'Wrong scope.');
    }
    final sourcePath = partPath(partial.trackId);
    if (!await _fileSystem.fileExists(sourcePath)) {
      throw StateError('No partial file exists for ${partial.trackId}.');
    }

    final bytes = await _fileSystem.fileLength(sourcePath);
    if (partial.downloadedBytes != bytes) {
      throw StateError('Partial byte count does not match the staged file.');
    }

    final entries = await _readIndex();
    final targetPath = mediaPath(partial.trackId);
    final existing = entries.remove(partial.trackId);
    if (existing != null) {
      await Future.wait([
        _fileSystem.deleteFile(_entryPath(existing)),
        _fileSystem.deleteFile(lyricsPath(partial.trackId)),
        _fileSystem.deleteFile(artworkPath(partial.trackId)),
      ]);
    }
    await _fileSystem.deleteFile(targetPath);
    await _fileSystem.rename(sourcePath, targetPath);
    await _fileSystem.deleteFile(partStatePath(partial.trackId));

    final now = _now().toUtc();
    final entry = OfflineCacheEntry(
      trackId: partial.trackId,
      fileName: _mediaFileName(partial.trackId),
      bytes: bytes,
      metadata: partial.metadata,
      trackSnapshot: partial.trackSnapshot,
      completedAt: now,
      lastAccessedAt: now,
    );
    entries[entry.trackId] = entry;
    await _writeIndex(entries);
    return entry;
  }

  Future<OfflineAvailability> evaluateAvailability(
    String trackId, {
    String? requiredMediaVersion,
    bool verifySha256 = false,
  }) async {
    final entry = await readEntry(trackId);
    if (entry == null) {
      return const OfflineAvailability(
        reason: OfflineAvailabilityReason.missingEntry,
      );
    }

    final path = _entryPath(entry);
    if (!await _fileSystem.fileExists(path)) {
      return OfflineAvailability(
        reason: OfflineAvailabilityReason.missingFile,
        entry: entry,
        path: path,
      );
    }
    if (await _fileSystem.fileLength(path) != entry.bytes) {
      return OfflineAvailability(
        reason: OfflineAvailabilityReason.sizeMismatch,
        entry: entry,
        path: path,
      );
    }
    if (requiredMediaVersion != null &&
        requiredMediaVersion.trim().isNotEmpty &&
        entry.metadata.mediaVersion != requiredMediaVersion.trim()) {
      return OfflineAvailability(
        reason: OfflineAvailabilityReason.mediaVersionMismatch,
        entry: entry,
        path: path,
      );
    }
    if (!verifySha256) {
      return OfflineAvailability(
        reason: OfflineAvailabilityReason.available,
        entry: entry,
        path: path,
      );
    }

    final expected = entry.metadata.expectedSha256 ?? entry.metadata.sha256;
    if (expected == null) {
      return OfflineAvailability(
        reason: OfflineAvailabilityReason.checksumUnavailable,
        entry: entry,
        path: path,
      );
    }
    final actual = await _sha256Verifier.digestFile(_fileSystem, path);
    return OfflineAvailability(
      reason: actual == expected
          ? OfflineAvailabilityReason.available
          : OfflineAvailabilityReason.checksumMismatch,
      entry: entry,
      path: path,
    );
  }

  Future<OfflineCacheEntry?> markAccessed(String trackId) async {
    final entries = await _readIndex();
    final entry = entries[trackId];
    if (entry == null || !await _fileSystem.fileExists(_entryPath(entry))) {
      return null;
    }
    final updated = entry.copyWith(lastAccessedAt: _now().toUtc());
    entries[trackId] = updated;
    await _writeIndex(entries);
    return updated;
  }

  Future<void> removeEntry(String trackId) async {
    final entries = await _readIndex();
    final entry = entries.remove(trackId);
    if (entry == null) {
      return;
    }
    await Future.wait([
      _fileSystem.deleteFile(_entryPath(entry)),
      _fileSystem.deleteFile(lyricsPath(trackId)),
      _fileSystem.deleteFile(artworkPath(trackId)),
    ]);
    await _writeIndex(entries);
  }

  Future<OfflineCachedLyrics?> readLyrics(String trackId) async {
    final entry = await readEntry(trackId);
    if (entry == null) {
      return null;
    }
    final path = _resourcePath(
      entry.resources.lyricsFileName,
      fallbackFileName: _lyricsFileName(trackId),
    );
    if (!await _fileSystem.fileExists(path)) {
      return null;
    }
    return OfflineCachedLyrics.tryDecode(await _fileSystem.readString(path));
  }

  Future<Uri?> readArtworkUri(String trackId) async {
    final entry = await readEntry(trackId);
    if (entry == null) {
      return null;
    }
    final path = _resourcePath(
      entry.resources.artworkFileName,
      fallbackFileName: _artworkFileName(trackId),
    );
    return await _fileSystem.fileExists(path) ? Uri.file(path) : null;
  }

  Future<void> writeSupplementalResources(
    String trackId, {
    OfflineCachedLyrics? lyrics,
    List<int>? artworkBytes,
    String? artworkContentType,
    bool replaceLyrics = false,
    bool replaceArtwork = false,
  }) async {
    final entries = await _readIndex();
    final entry = entries[trackId];
    if (entry == null) {
      return;
    }

    var resources = entry.resources;
    if (replaceLyrics) {
      if (lyrics == null || lyrics.content.trim().isEmpty) {
        await _fileSystem.deleteFile(lyricsPath(trackId));
        resources = resources.copyWith(clearLyrics: true);
      } else {
        await _writeStringAtomically(lyricsPath(trackId), lyrics.encode());
        resources = resources.copyWith(
          lyricsFileName: _lyricsFileName(trackId),
        );
      }
    }
    if (replaceArtwork) {
      if (artworkBytes == null || artworkBytes.isEmpty) {
        await _fileSystem.deleteFile(artworkPath(trackId));
        resources = resources.copyWith(clearArtwork: true);
      } else {
        await _writeBytesAtomically(artworkPath(trackId), artworkBytes);
        resources = resources.copyWith(
          artworkFileName: _artworkFileName(trackId),
          artworkContentType: artworkContentType,
        );
      }
    }
    final localArtworkUrl =
        resources.hasArtwork ? Uri.file(artworkPath(trackId)).toString() : null;
    entries[trackId] = entry.copyWith(
      resources: resources,
      trackSnapshot: OfflineTrackSnapshot(
        title: entry.trackSnapshot.title,
        artist: entry.trackSnapshot.artist,
        album: entry.trackSnapshot.album,
        durationSeconds: entry.trackSnapshot.durationSeconds,
        genres: entry.trackSnapshot.genres,
        artworkUrl: localArtworkUrl,
      ),
    );
    await _writeIndex(entries);
  }

  Future<int> storageUsage() async {
    final files = await _fileSystem.listFiles(scopeDirectory);
    return files
        .where((file) =>
            file.path.endsWith('.media') ||
            file.path.endsWith('.part') ||
            file.path.endsWith('.lyrics.json') ||
            file.path.endsWith('.artwork'))
        .fold<int>(0, (total, file) => total + file.bytes);
  }

  Future<OfflineQuotaResult> enforceQuota({
    required int maxBytes,
    required int incomingBytes,
    Set<String> protectedTrackIds = const {},
  }) async {
    if (maxBytes < 0 || incomingBytes < 0) {
      throw ArgumentError(
          'Quota and incoming byte counts must be non-negative.');
    }

    var usedBytes = await storageUsage();
    final evictedTrackIds = <String>[];
    final entries = await _readIndex();
    final indexedNames = <String>{
      ...entries.values.map((entry) => entry.fileName),
      ...entries.values
          .map((entry) => entry.resources.lyricsFileName)
          .whereType<String>(),
      ...entries.values
          .map((entry) => entry.resources.artworkFileName)
          .whereType<String>(),
    };
    final files = await _fileSystem.listFiles(scopeDirectory);
    for (final file in files) {
      final fileName = _fileName(file.path);
      if (_isManagedFile(file.path) && !indexedNames.contains(fileName)) {
        await _fileSystem.deleteFile(file.path);
        usedBytes -= file.bytes;
      }
    }

    final candidates = entries.values.toList()
      ..sort(
          (left, right) => left.lastAccessedAt.compareTo(right.lastAccessedAt));
    for (final entry in candidates) {
      if (usedBytes + incomingBytes <= maxBytes) {
        break;
      }
      if (protectedTrackIds.contains(entry.trackId)) {
        continue;
      }

      final paths = [
        _entryPath(entry),
        lyricsPath(entry.trackId),
        artworkPath(entry.trackId),
      ];
      var releasedBytes = 0;
      for (final path in paths) {
        if (await _fileSystem.fileExists(path)) {
          releasedBytes += await _fileSystem.fileLength(path);
        }
      }
      await Future.wait([
        _fileSystem.deleteFile(paths[0]),
        _fileSystem.deleteFile(lyricsPath(entry.trackId)),
        _fileSystem.deleteFile(artworkPath(entry.trackId)),
      ]);
      entries.remove(entry.trackId);
      usedBytes -= releasedBytes;
      evictedTrackIds.add(entry.trackId);
    }

    if (evictedTrackIds.isNotEmpty) {
      await _writeIndex(entries);
    }
    if (usedBytes + incomingBytes > maxBytes) {
      throw OfflineQuotaExceededException(
        maxBytes: maxBytes,
        requiredBytes: incomingBytes,
        usedBytes: usedBytes,
      );
    }
    return OfflineQuotaResult(
      usedBytes: usedBytes,
      evictedTrackIds: List.unmodifiable(evictedTrackIds),
    );
  }

  Future<Map<String, OfflineCacheEntry>> _readIndex() async {
    await initialize();
    if (!await _fileSystem.fileExists(_indexPath)) {
      return {};
    }

    try {
      final decoded = jsonDecode(await _fileSystem.readString(_indexPath));
      if (decoded is! Map<Object?, Object?>) {
        return {};
      }
      final rawEntries = decoded['entries'];
      if (rawEntries is! List<Object?>) {
        return {};
      }

      final result = <String, OfflineCacheEntry>{};
      var shouldRewrite = decoded['version'] != _indexVersion;
      for (final rawEntry in rawEntries) {
        if (rawEntry is! Map<Object?, Object?>) {
          continue;
        }
        final entry = OfflineCacheEntry.fromJson(
          rawEntry.cast<String, Object?>(),
        );
        if (entry.trackId.isEmpty ||
            entry.bytes < 0 ||
            !_isSafeManagedFileName(entry.fileName)) {
          continue;
        }
        final migrated = await _migrateEntry(entry);
        if (_entryChanged(entry, migrated)) {
          shouldRewrite = true;
        }
        result[migrated.trackId] = migrated;
      }
      if (shouldRewrite) {
        await _writeIndex(result);
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<void> _writeIndex(Map<String, OfflineCacheEntry> entries) {
    final sorted = entries.values.toList()
      ..sort((left, right) => left.trackId.compareTo(right.trackId));
    return _writeJsonAtomically(
      _indexPath,
      {
        'entries': sorted.map((entry) => entry.toJson()).toList(),
        'scope': scope.toJson(),
        'version': _indexVersion,
      },
    );
  }

  Future<OfflineCacheEntry> _migrateEntry(OfflineCacheEntry entry) async {
    final trackId = entry.trackId;
    final mediaFileName = _mediaFileName(trackId);
    await _migrateManagedFile(
      targetFileName: mediaFileName,
      candidateFileNames: [entry.fileName],
    );
    final lyricsFileName = await _migrateManagedFile(
      targetFileName: _lyricsFileName(trackId),
      candidateFileNames: [entry.resources.lyricsFileName],
    );
    final artworkFileName = await _migrateManagedFile(
      targetFileName: _artworkFileName(trackId),
      candidateFileNames: [
        entry.resources.artworkFileName,
        _localArtworkFileName(entry.trackSnapshot.artworkUrl),
      ],
    );
    final resources = OfflineSupplementalResources(
      lyricsFileName: lyricsFileName,
      artworkFileName: artworkFileName,
      artworkContentType:
          artworkFileName == null ? null : entry.resources.artworkContentType,
    );
    final artworkUrl = artworkFileName == null
        ? null
        : Uri.file(_join(scopeDirectory, artworkFileName)).toString();
    final snapshot = OfflineTrackSnapshot(
      title: entry.trackSnapshot.title,
      artist: entry.trackSnapshot.artist,
      album: entry.trackSnapshot.album,
      durationSeconds: entry.trackSnapshot.durationSeconds,
      genres: entry.trackSnapshot.genres,
      artworkUrl: artworkUrl ?? entry.trackSnapshot.artworkUrl,
    );
    return entry.copyWith(
      fileName: mediaFileName,
      resources: resources,
      trackSnapshot: snapshot,
    );
  }

  bool _entryChanged(OfflineCacheEntry left, OfflineCacheEntry right) {
    return left.fileName != right.fileName ||
        left.resources.lyricsFileName != right.resources.lyricsFileName ||
        left.resources.artworkFileName != right.resources.artworkFileName ||
        left.resources.artworkContentType !=
            right.resources.artworkContentType ||
        left.trackSnapshot.artworkUrl != right.trackSnapshot.artworkUrl;
  }

  Future<String?> _migrateManagedFile({
    required String targetFileName,
    required Iterable<String?> candidateFileNames,
  }) async {
    final targetPath = _join(scopeDirectory, targetFileName);
    if (await _fileSystem.fileExists(targetPath)) {
      return targetFileName;
    }

    for (final candidateFileName in candidateFileNames) {
      if (!_isSafeManagedFileName(candidateFileName)) {
        continue;
      }
      final sourcePath = _join(scopeDirectory, candidateFileName!);
      if (!await _fileSystem.fileExists(sourcePath)) {
        continue;
      }
      await _fileSystem.rename(sourcePath, targetPath);
      return targetFileName;
    }
    return null;
  }

  String _resourcePath(
    String? persistedFileName, {
    required String fallbackFileName,
  }) {
    final fileName = _isSafeManagedFileName(persistedFileName)
        ? persistedFileName!
        : fallbackFileName;
    return _join(scopeDirectory, fileName);
  }

  Future<void> _writeJsonAtomically(String path, Object value) async {
    await _writeStringAtomically(path, jsonEncode(value));
  }

  Future<void> _writeStringAtomically(String path, String value) async {
    final temporaryPath = '$path.tmp';
    await _fileSystem.writeString(temporaryPath, value);
    await _fileSystem.rename(temporaryPath, path);
  }

  Future<void> _writeBytesAtomically(String path, List<int> bytes) async {
    final temporaryPath = '$path.tmp';
    final writer = await _fileSystem.openWrite(temporaryPath, append: false);
    try {
      await writer.write(bytes);
    } finally {
      await writer.close();
    }
    await _fileSystem.rename(temporaryPath, path);
  }

  String _entryPath(OfflineCacheEntry entry) {
    return _join(scopeDirectory, entry.fileName);
  }
}

String _trackKey(String trackId) {
  final normalized = trackId.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(trackId, 'trackId', 'Must not be empty.');
  }
  return sha256.convert(utf8.encode(normalized)).toString();
}

String _mediaFileName(String trackId) => '${_trackKey(trackId)}.media';

String _lyricsFileName(String trackId) => '${_trackKey(trackId)}.lyrics.json';

String _artworkFileName(String trackId) => '${_trackKey(trackId)}.artwork';

bool _isManagedFile(String path) {
  return path.endsWith('.media') ||
      path.endsWith('.lyrics.json') ||
      path.endsWith('.artwork');
}

bool _isSafeManagedFileName(String? fileName) {
  if (fileName == null ||
      fileName.isEmpty ||
      fileName == '.' ||
      fileName == '..' ||
      fileName != _fileName(fileName)) {
    return false;
  }
  return fileName.endsWith('.media') ||
      fileName.endsWith('.lyrics.json') ||
      fileName.endsWith('.artwork');
}

String? _localArtworkFileName(String? artworkUrl) {
  final uri = Uri.tryParse(artworkUrl ?? '');
  if (uri?.scheme != 'file') {
    return null;
  }
  final fileName = _fileName(uri!.toFilePath());
  return _isSafeManagedFileName(fileName) ? fileName : null;
}

String _join(String left, String right) {
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left/$right';
}

String _fileName(String path) {
  final separator = path.lastIndexOf(RegExp(r'[/\\]'));
  return separator < 0 ? path : path.substring(separator + 1);
}
