import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _lyricsOffsetKeyPrefix = 'player_preferences.lyrics_offset.';
const _lyricsOffsetKeyVersion = '.v1';

final lyricsOffsetRepositoryProvider = Provider<LyricsOffsetRepository>((ref) {
  return SharedPreferencesLyricsOffsetRepository();
});

abstract interface class LyricsOffsetRepository {
  Future<Duration> load(String trackId);

  Future<void> save(String trackId, Duration offset);
}

class SharedPreferencesLyricsOffsetRepository
    implements LyricsOffsetRepository {
  @override
  Future<Duration> load(String trackId) async {
    final preferences = await SharedPreferences.getInstance();
    final milliseconds = preferences.getInt(_keyFor(trackId));
    return milliseconds == null
        ? Duration.zero
        : Duration(milliseconds: milliseconds);
  }

  @override
  Future<void> save(String trackId, Duration offset) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _keyFor(trackId);
    if (offset == Duration.zero) {
      await preferences.remove(key);
      return;
    }
    await preferences.setInt(key, offset.inMilliseconds);
  }

  static String _keyFor(String trackId) {
    return '$_lyricsOffsetKeyPrefix${Uri.encodeComponent(trackId)}'
        '$_lyricsOffsetKeyVersion';
  }
}
