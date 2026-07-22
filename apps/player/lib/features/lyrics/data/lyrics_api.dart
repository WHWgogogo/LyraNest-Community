import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_error.dart';
import '../../offline/application/offline_providers.dart';
import '../domain/lyrics.dart';

final lyricsApiProvider = Provider<LyricsApi>((ref) {
  return LyricsApi(
    ref.watch(dioProvider),
    readCachedLyrics: (trackId) async {
      final cached =
          await ref.read(offlineCachedLyricsProvider(trackId).future);
      if (cached == null) {
        return null;
      }
      return Lyrics(
        trackId: trackId,
        path: cached.path,
        encoding: cached.encoding,
        content: cached.content,
      );
    },
  );
});

final lyricsProvider =
    FutureProvider.autoDispose.family<Lyrics, String>((ref, trackId) {
  return _readLyrics(ref, trackId);
});

Future<Lyrics> _readLyrics(Ref ref, String trackId) async {
  try {
    final cached = await ref.watch(offlineCachedLyricsProvider(trackId).future);
    if (cached != null) {
      return Lyrics(
        trackId: trackId,
        path: cached.path,
        encoding: cached.encoding,
        content: cached.content,
      );
    }
  } catch (_) {}
  return ref.watch(lyricsApiProvider).fetchLyrics(trackId);
}

class LyricsApi {
  const LyricsApi(
    this._dio, {
    this.readCachedLyrics,
  });

  final Dio _dio;
  final Future<Lyrics?> Function(String trackId)? readCachedLyrics;

  Future<Lyrics> fetchLyrics(String trackId) async {
    try {
      final cached = await readCachedLyrics?.call(trackId);
      if (cached != null) {
        return cached;
      }
    } catch (_) {}
    try {
      final response = await _dio.get(
        '/api/v1/tracks/${Uri.encodeComponent(trackId)}/lyrics',
      );
      return Lyrics.fromJson(trackId, response.data);
    } catch (error) {
      throw ApiError.fromObject(error);
    }
  }
}
