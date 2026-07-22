import '../domain/offline_supplemental_resources.dart';

class OfflineArtwork {
  const OfflineArtwork({
    required this.bytes,
    this.contentType,
  });

  final List<int> bytes;
  final String? contentType;
}

abstract interface class OfflineSupplementalResourceFetcher {
  Future<OfflineCachedLyrics?> fetchLyrics(String trackId);

  Future<OfflineArtwork?> fetchArtwork(String trackId);
}
