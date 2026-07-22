import '../../../core/network/api_error.dart';
import '../../lyrics/data/lyrics_api.dart';
import '../../lyrics/domain/lyrics.dart';

class LyricsNotFoundFallbackApi extends LyricsApi {
  const LyricsNotFoundFallbackApi(super.dio);

  @override
  Future<Lyrics> fetchLyrics(String trackId) {
    return loadLyricsAllowingNotFound(
      trackId: trackId,
      load: () => super.fetchLyrics(trackId),
    );
  }
}

Future<Lyrics> loadLyricsAllowingNotFound({
  required String trackId,
  required Future<Lyrics> Function() load,
}) async {
  try {
    return await load();
  } on ApiError catch (error) {
    if (error.statusCode != 404) {
      rethrow;
    }

    return Lyrics(
      trackId: trackId,
      path: null,
      encoding: null,
      content: '',
    );
  }
}
