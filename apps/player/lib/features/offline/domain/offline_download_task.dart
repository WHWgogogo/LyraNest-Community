import 'offline_cache_scope.dart';
import 'offline_media_metadata.dart';
import 'offline_supplemental_resources.dart';
import '../../tracks/domain/track.dart';

class OfflineTrackSnapshot {
  const OfflineTrackSnapshot({
    this.title,
    this.artist,
    this.album,
    this.durationSeconds,
    this.genres = const [],
    this.artworkUrl,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationSeconds;
  final List<String> genres;
  final String? artworkUrl;

  String get displayTitle {
    final value = title?.trim();
    return value == null || value.isEmpty ? Track.untitledTitle : value;
  }

  String? get displayArtist {
    final value = artist?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  String? get displayAlbum {
    final value = album?.trim();
    return value == null || value.isEmpty ? null : value;
  }

  factory OfflineTrackSnapshot.fromTrack(Track track) {
    return OfflineTrackSnapshot(
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationSeconds: track.durationSeconds,
      genres: track.genres,
      artworkUrl: track.artworkUrl,
    );
  }

  factory OfflineTrackSnapshot.fromJson(Map<String, Object?> json) {
    return OfflineTrackSnapshot(
      title: json['title'] as String?,
      artist: json['artist'] as String?,
      album: json['album'] as String?,
      durationSeconds: json['durationSeconds'] as int?,
      genres: (json['genres'] as List<Object?>?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const [],
      artworkUrl: json['artworkUrl'] as String?,
    );
  }

  Track toTrack(String trackId) {
    return Track(
      id: trackId,
      title: displayTitle,
      artist: displayArtist,
      album: displayAlbum,
      durationSeconds: durationSeconds,
      genres: genres,
      artworkUrl: artworkUrl,
    );
  }

  Map<String, Object?> toJson() => {
        'album': album,
        'artist': artist,
        'durationSeconds': durationSeconds,
        'genres': genres,
        'artworkUrl': artworkUrl,
        'title': title,
      };
}

enum OfflineDownloadStatus {
  queued,
  downloading,
  paused,
  failed,
  completed,
}

class OfflineDownloadTask {
  const OfflineDownloadTask({
    required this.id,
    required this.scope,
    required this.trackId,
    required this.sourceUri,
    this.status = OfflineDownloadStatus.queued,
    this.downloadedBytes = 0,
    this.totalBytes,
    this.metadata = const OfflineMediaMetadata(),
    this.trackSnapshot = const OfflineTrackSnapshot(),
    this.errorMessage,
  });

  final String id;
  final OfflineCacheScope scope;
  final String trackId;
  final Uri sourceUri;
  final OfflineDownloadStatus status;
  final int downloadedBytes;
  final int? totalBytes;
  final OfflineMediaMetadata metadata;
  final OfflineTrackSnapshot trackSnapshot;
  final String? errorMessage;

  double? get progress {
    final total = totalBytes;
    if (total == null || total == 0) {
      return null;
    }
    return downloadedBytes / total;
  }

  OfflineDownloadTask copyWith({
    OfflineDownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    OfflineMediaMetadata? metadata,
    OfflineTrackSnapshot? trackSnapshot,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OfflineDownloadTask(
      id: id,
      scope: scope,
      trackId: trackId,
      sourceUri: sourceUri,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      metadata: metadata ?? this.metadata,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Persisted alongside a `.part` file so interrupted downloads can resume.
class OfflinePartialDownload {
  const OfflinePartialDownload({
    required this.scope,
    required this.trackId,
    required this.sourceUri,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.metadata,
    this.trackSnapshot = const OfflineTrackSnapshot(),
    required this.updatedAt,
  });

  final OfflineCacheScope scope;
  final String trackId;
  final Uri sourceUri;
  final int downloadedBytes;
  final int? totalBytes;
  final OfflineMediaMetadata metadata;
  final OfflineTrackSnapshot trackSnapshot;
  final DateTime updatedAt;

  OfflinePartialDownload copyWith({
    int? downloadedBytes,
    int? totalBytes,
    OfflineMediaMetadata? metadata,
    OfflineTrackSnapshot? trackSnapshot,
    DateTime? updatedAt,
  }) {
    return OfflinePartialDownload(
      scope: scope,
      trackId: trackId,
      sourceUri: sourceUri,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      metadata: metadata ?? this.metadata,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'downloadedBytes': downloadedBytes,
        'metadata': metadata.toJson(),
        'trackSnapshot': trackSnapshot.toJson(),
        'scope': scope.toJson(),
        'sourceUri': sourceUri.toString(),
        'totalBytes': totalBytes,
        'trackId': trackId,
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  factory OfflinePartialDownload.fromJson(Map<String, Object?> json) {
    return OfflinePartialDownload(
      scope: OfflineCacheScope.fromJson(
        (json['scope'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
            const {},
      ),
      trackId: json['trackId'] as String? ?? '',
      sourceUri: Uri.parse(json['sourceUri'] as String? ?? ''),
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
      totalBytes: json['totalBytes'] as int?,
      metadata: OfflineMediaMetadata.fromJson(
        (json['metadata'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
            const {},
      ),
      trackSnapshot: OfflineTrackSnapshot.fromJson(
        (json['trackSnapshot'] as Map<Object?, Object?>?)
                ?.cast<String, Object?>() ??
            const {},
      ),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }
}

class OfflineCacheEntry {
  const OfflineCacheEntry({
    required this.trackId,
    required this.fileName,
    required this.bytes,
    required this.metadata,
    this.trackSnapshot = const OfflineTrackSnapshot(),
    this.resources = const OfflineSupplementalResources(),
    required this.completedAt,
    required this.lastAccessedAt,
  });

  final String trackId;
  final String fileName;
  final int bytes;
  final OfflineMediaMetadata metadata;
  final OfflineTrackSnapshot trackSnapshot;
  final OfflineSupplementalResources resources;
  final DateTime completedAt;
  final DateTime lastAccessedAt;

  OfflineCacheEntry copyWith({
    String? fileName,
    int? bytes,
    OfflineMediaMetadata? metadata,
    OfflineTrackSnapshot? trackSnapshot,
    OfflineSupplementalResources? resources,
    DateTime? completedAt,
    DateTime? lastAccessedAt,
  }) {
    return OfflineCacheEntry(
      trackId: trackId,
      fileName: fileName ?? this.fileName,
      bytes: bytes ?? this.bytes,
      metadata: metadata ?? this.metadata,
      trackSnapshot: trackSnapshot ?? this.trackSnapshot,
      resources: resources ?? this.resources,
      completedAt: completedAt ?? this.completedAt,
      lastAccessedAt: lastAccessedAt ?? this.lastAccessedAt,
    );
  }

  Map<String, Object?> toJson() => {
        'bytes': bytes,
        'completedAt': completedAt.toUtc().toIso8601String(),
        'fileName': fileName,
        'lastAccessedAt': lastAccessedAt.toUtc().toIso8601String(),
        'metadata': metadata.toJson(),
        'resources': resources.toJson(),
        'trackSnapshot': trackSnapshot.toJson(),
        'trackId': trackId,
      };

  factory OfflineCacheEntry.fromJson(Map<String, Object?> json) {
    final epoch = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    return OfflineCacheEntry(
      trackId: json['trackId'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      bytes: json['bytes'] as int? ?? 0,
      metadata: OfflineMediaMetadata.fromJson(
        (json['metadata'] as Map<Object?, Object?>?)?.cast<String, Object?>() ??
            const {},
      ),
      resources: OfflineSupplementalResources.fromJson(
        (json['resources'] as Map<Object?, Object?>?)
                ?.cast<String, Object?>() ??
            const {},
      ),
      trackSnapshot: OfflineTrackSnapshot.fromJson(
        (json['trackSnapshot'] as Map<Object?, Object?>?)
                ?.cast<String, Object?>() ??
            const {},
      ),
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '') ?? epoch,
      lastAccessedAt:
          DateTime.tryParse(json['lastAccessedAt'] as String? ?? '') ?? epoch,
    );
  }
}

enum OfflineAvailabilityReason {
  available,
  missingEntry,
  missingFile,
  sizeMismatch,
  mediaVersionMismatch,
  checksumMismatch,
  checksumUnavailable,
}

class OfflineAvailability {
  const OfflineAvailability({
    required this.reason,
    this.entry,
    this.path,
  });

  final OfflineAvailabilityReason reason;
  final OfflineCacheEntry? entry;
  final String? path;

  bool get isAvailable => reason == OfflineAvailabilityReason.available;
}

class OfflineQuotaResult {
  const OfflineQuotaResult({
    required this.usedBytes,
    required this.evictedTrackIds,
  });

  final int usedBytes;
  final List<String> evictedTrackIds;
}
