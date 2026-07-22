import 'offline_cache_repository.dart';

abstract interface class OfflinePlaybackSourceResolver {
  Future<Uri?> resolve(String trackId);
}

class CachedOfflinePlaybackSourceResolver
    implements OfflinePlaybackSourceResolver {
  CachedOfflinePlaybackSourceResolver(this._repository);

  final Future<OfflineCacheRepository?> Function() _repository;

  @override
  Future<Uri?> resolve(String trackId) async {
    final cache = await _repository();
    if (cache == null) {
      return null;
    }

    final availability = await cache.evaluateAvailability(trackId);
    if (!availability.isAvailable || availability.path == null) {
      return null;
    }
    await cache.markAccessed(trackId);
    return Uri.file(availability.path!);
  }
}
