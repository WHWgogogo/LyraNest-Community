import 'package:flutter_test/flutter_test.dart';
import 'package:player/core/network/api_error.dart';
import 'package:player/features/player/application/lyrics_not_found_fallback.dart';

void main() {
  test('lyrics 404 becomes empty lyrics content', () async {
    final lyrics = await loadLyricsAllowingNotFound(
      trackId: 'song-1',
      load: () => Future.error(
        const ApiError('Not found', statusCode: 404),
      ),
    );

    expect(lyrics.trackId, 'song-1');
    expect(lyrics.content, isEmpty);
  });

  test('non-404 lyrics failures still surface', () {
    expectLater(
      loadLyricsAllowingNotFound(
        trackId: 'song-1',
        load: () => Future.error(
          const ApiError('Server error', statusCode: 500),
        ),
      ),
      throwsA(
        isA<ApiError>().having(
          (error) => error.statusCode,
          'statusCode',
          500,
        ),
      ),
    );
  });
}
