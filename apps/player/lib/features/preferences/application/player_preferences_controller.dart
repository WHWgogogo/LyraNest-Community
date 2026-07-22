import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../data/player_preferences_repository.dart';
import '../domain/player_preferences.dart';

final playerPreferencesProvider =
    AsyncNotifierProvider<PlayerPreferencesController, PlayerPreferences>(
  PlayerPreferencesController.new,
);

final playerPreferencesControllerProvider = playerPreferencesProvider;

final desktopLyricsBackgroundOpacityProvider = Provider<double>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.desktopLyricsBackgroundOpacity ??
      PlayerPreferences.defaultDesktopLyricsBackgroundOpacity;
});

final lyricsColorArgbProvider = Provider<int>((ref) {
  return ref.watch(playerPreferencesProvider).valueOrNull?.lyricsColorArgb ??
      PlayerPreferences.defaultLyricsColorArgb;
});

final desktopLyricsColorArgbProvider = lyricsColorArgbProvider;

final inAppLyricsFontSizeProvider = Provider<double>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.inAppLyricsFontSize ??
      PlayerPreferences.defaultInAppLyricsFontSize;
});

final desktopLyricsFontSizeProvider = Provider<double>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.desktopLyricsFontSize ??
      PlayerPreferences.defaultDesktopLyricsFontSize;
});

final desktopLyricsAlignmentProvider = Provider<LyricsAlignment>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.desktopLyricsAlignment ??
      PlayerPreferences.defaultDesktopLyricsAlignment;
});

final desktopLyricsTextAlignProvider = Provider<TextAlign>((ref) {
  return ref.watch(desktopLyricsAlignmentProvider).textAlign;
});

final inAppLyricsAlignmentProvider = Provider<LyricsAlignment>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.inAppLyricsAlignment ??
      PlayerPreferences.defaultInAppLyricsAlignment;
});

final inAppLyricsTextAlignProvider = Provider<TextAlign>((ref) {
  return ref.watch(inAppLyricsAlignmentProvider).textAlign;
});

final desktopLyricsLineModeProvider = Provider<DesktopLyricsLineMode>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.desktopLyricsLineMode ??
      PlayerPreferences.defaultDesktopLyricsLineMode;
});

final resetPositionOnOpenProvider = Provider<bool>((ref) {
  return ref
          .watch(playerPreferencesProvider)
          .valueOrNull
          ?.resetPositionOnOpen ??
      PlayerPreferences.defaultResetPositionOnOpen;
});

final resetDesktopLyricsPositionOnOpenProvider = resetPositionOnOpenProvider;

class PlayerPreferencesController extends AsyncNotifier<PlayerPreferences> {
  Future<void> _operationTail = Future<void>.value();

  @override
  Future<PlayerPreferences> build() {
    return ref.read(playerPreferencesRepositoryProvider).load();
  }

  Future<void> setDesktopLyricsBackgroundOpacity(double value) {
    if (!value.isFinite || value < 0 || value > 1) {
      return Future<void>.error(
        RangeError.range(value, 0, 1, 'value'),
      );
    }
    return _update(
      (preferences) => preferences.copyWith(
        desktopLyricsBackgroundOpacity: value,
      ),
    );
  }

  Future<void> setLyricsColorArgb(int value) {
    if (value < 0 || value > 0xffffffff) {
      return Future<void>.error(
        RangeError.range(value, 0, 0xffffffff, 'value'),
      );
    }
    return _update(
      (preferences) => preferences.copyWith(lyricsColorArgb: value),
    );
  }

  Future<void> setDesktopLyricsColorArgb(int value) {
    return setLyricsColorArgb(value);
  }

  Future<void> setInAppLyricsFontSize(double value) {
    if (!PlayerPreferences.isValidInAppLyricsFontSize(value)) {
      return Future<void>.error(
        RangeError.value(
          value,
          'value',
          'must be a ${PlayerPreferences.minInAppLyricsFontSize}–'
              '${PlayerPreferences.maxInAppLyricsFontSize} value in '
              '${PlayerPreferences.inAppLyricsFontSizeStep} point steps',
        ),
      );
    }
    return _update(
      (preferences) => preferences.copyWith(inAppLyricsFontSize: value),
    );
  }

  Future<void> setDesktopLyricsFontSize(double value) {
    if (!PlayerPreferences.isValidDesktopLyricsFontSize(value)) {
      return Future<void>.error(
        RangeError.value(
          value,
          'value',
          'must be a ${PlayerPreferences.minDesktopLyricsFontSize}–'
              '${PlayerPreferences.maxDesktopLyricsFontSize} value in '
              '${PlayerPreferences.desktopLyricsFontSizeStep} point steps',
        ),
      );
    }
    return _update(
      (preferences) => preferences.copyWith(desktopLyricsFontSize: value),
    );
  }

  Future<void> setDesktopLyricsAlignment(LyricsAlignment value) {
    return _update(
      (preferences) => preferences.copyWith(desktopLyricsAlignment: value),
    );
  }

  Future<void> setDesktopLyricsTextAlign(TextAlign value) {
    return setDesktopLyricsAlignment(LyricsAlignment.fromTextAlign(value));
  }

  Future<void> setInAppLyricsAlignment(LyricsAlignment value) {
    if (!value.supportsInAppLyrics) {
      return Future<void>.error(
        ArgumentError.value(
          value,
          'value',
          'split alignment is only supported for desktop lyrics',
        ),
      );
    }
    return _update(
      (preferences) => preferences.copyWith(inAppLyricsAlignment: value),
    );
  }

  Future<void> setInAppLyricsTextAlign(TextAlign value) {
    return setInAppLyricsAlignment(LyricsAlignment.fromTextAlign(value));
  }

  Future<void> setDesktopLyricsLineMode(DesktopLyricsLineMode value) {
    return _update(
      (preferences) => preferences.copyWith(desktopLyricsLineMode: value),
    );
  }

  Future<void> setResetPositionOnOpen(bool value) {
    return _update(
      (preferences) => preferences.copyWith(resetPositionOnOpen: value),
    );
  }

  Future<void> setResetDesktopLyricsPositionOnOpen(bool value) {
    return setResetPositionOnOpen(value);
  }

  Future<void> _update(
    PlayerPreferences Function(PlayerPreferences preferences) update,
  ) {
    final result = _operationTail.then((_) async {
      final current = await future;
      final next = update(current);
      if (next == current) {
        return;
      }
      await ref.read(playerPreferencesRepositoryProvider).save(next);
      state = AsyncData(next);
    });
    _operationTail = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );
    return result;
  }
}
