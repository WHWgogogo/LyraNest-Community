import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences/data/lyrics_offset_repository.dart';

final lyricsOffsetProvider =
    AsyncNotifierProvider.family<LyricsOffsetController, Duration, String>(
  LyricsOffsetController.new,
);

class LyricsOffsetController extends FamilyAsyncNotifier<Duration, String> {
  Future<void> _saveTail = Future<void>.value();
  late String _trackId;

  @override
  Future<Duration> build(String trackId) {
    _trackId = trackId;
    return ref.read(lyricsOffsetRepositoryProvider).load(trackId);
  }

  Future<void> setOffset(Duration offset) {
    state = AsyncData(offset);
    final result = _saveTail.then(
      (_) => ref.read(lyricsOffsetRepositoryProvider).save(_trackId, offset),
    );
    _saveTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
