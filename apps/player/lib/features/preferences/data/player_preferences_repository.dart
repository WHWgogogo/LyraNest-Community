import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/player_preferences.dart';

const _desktopLyricsBackgroundOpacityKey =
    'player_preferences.desktop_lyrics_background_opacity.v1';
const _lyricsColorArgbKey = 'player_preferences.lyrics_color_argb.v1';
const _legacyLyricsFontSizeKey = 'player_preferences.lyrics_font_size.v1';
const _inAppLyricsFontSizeKey = 'player_preferences.in_app_lyrics_font_size.v1';
const _desktopLyricsFontSizeKey =
    'player_preferences.desktop_lyrics_font_size.v1';
const _desktopLyricsAlignmentKey =
    'player_preferences.desktop_lyrics_alignment.v1';
const _inAppLyricsAlignmentKey =
    'player_preferences.in_app_lyrics_alignment.v1';
const _desktopLyricsLineModeKey =
    'player_preferences.desktop_lyrics_line_mode.v1';
const _resetPositionOnOpenKey =
    'player_preferences.reset_desktop_lyrics_position_on_open.v1';

final playerPreferencesRepositoryProvider =
    Provider<PlayerPreferencesRepository>(
  (ref) => SharedPreferencesPlayerPreferencesRepository(),
);

abstract interface class PlayerPreferencesRepository {
  Future<PlayerPreferences> load();

  Future<void> save(PlayerPreferences preferences);
}

class SharedPreferencesPlayerPreferencesRepository
    implements PlayerPreferencesRepository {
  SharedPreferencesPlayerPreferencesRepository({
    Future<SharedPreferences>? preferences,
  }) : _preferences = preferences ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _preferences;

  @override
  Future<PlayerPreferences> load() async {
    final preferences = await _preferences;
    final legacyLyricsFontSize =
        _readValidLyricsFontSize(preferences, _legacyLyricsFontSizeKey);
    final inAppLyricsFontSize = _readValidLyricsFontSize(
          preferences,
          _inAppLyricsFontSizeKey,
        ) ??
        legacyLyricsFontSize ??
        PlayerPreferences.defaultInAppLyricsFontSize;
    final desktopLyricsFontSize = _readValidLyricsFontSize(
          preferences,
          _desktopLyricsFontSizeKey,
        ) ??
        legacyLyricsFontSize ??
        PlayerPreferences.defaultDesktopLyricsFontSize;
    final playerPreferences = PlayerPreferences(
      desktopLyricsBackgroundOpacity: _readOpacity(preferences),
      lyricsColorArgb: _readArgb(preferences),
      inAppLyricsFontSize: inAppLyricsFontSize,
      desktopLyricsFontSize: desktopLyricsFontSize,
      desktopLyricsAlignment: _readAlignment(
        preferences,
        _desktopLyricsAlignmentKey,
        PlayerPreferences.defaultDesktopLyricsAlignment,
        allowSplit: true,
      ),
      inAppLyricsAlignment: _readAlignment(
        preferences,
        _inAppLyricsAlignmentKey,
        PlayerPreferences.defaultInAppLyricsAlignment,
        allowSplit: false,
      ),
      desktopLyricsLineMode: _readDesktopLyricsLineMode(preferences),
      resetPositionOnOpen: preferences.get(_resetPositionOnOpenKey) is bool
          ? preferences.getBool(_resetPositionOnOpenKey)!
          : PlayerPreferences.defaultResetPositionOnOpen,
    );
    await _migrateLegacyLyricsFontSize(
      preferences,
      legacyLyricsFontSize: legacyLyricsFontSize,
      inAppLyricsFontSize: inAppLyricsFontSize,
      desktopLyricsFontSize: desktopLyricsFontSize,
    );
    return playerPreferences;
  }

  @override
  Future<void> save(PlayerPreferences playerPreferences) async {
    final preferences = await _preferences;
    await preferences.setDouble(
      _desktopLyricsBackgroundOpacityKey,
      playerPreferences.desktopLyricsBackgroundOpacity,
    );
    await preferences.setInt(
      _lyricsColorArgbKey,
      playerPreferences.lyricsColorArgb,
    );
    await preferences.setDouble(
      _inAppLyricsFontSizeKey,
      playerPreferences.inAppLyricsFontSize,
    );
    await preferences.setDouble(
      _desktopLyricsFontSizeKey,
      playerPreferences.desktopLyricsFontSize,
    );
    await preferences.setString(
      _desktopLyricsAlignmentKey,
      playerPreferences.desktopLyricsAlignment.name,
    );
    await preferences.setString(
      _inAppLyricsAlignmentKey,
      playerPreferences.inAppLyricsAlignment.name,
    );
    await preferences.setString(
      _desktopLyricsLineModeKey,
      playerPreferences.desktopLyricsLineMode.name,
    );
    await preferences.setBool(
      _resetPositionOnOpenKey,
      playerPreferences.resetPositionOnOpen,
    );
  }

  static double _readOpacity(SharedPreferences preferences) {
    final value = preferences.get(_desktopLyricsBackgroundOpacityKey);
    if (value is double && value.isFinite && value >= 0 && value <= 1) {
      return value;
    }
    return PlayerPreferences.defaultDesktopLyricsBackgroundOpacity;
  }

  static int _readArgb(SharedPreferences preferences) {
    final value = preferences.get(_lyricsColorArgbKey);
    if (value is int && value >= 0 && value <= 0xffffffff) {
      return value;
    }
    return PlayerPreferences.defaultLyricsColorArgb;
  }

  static double? _readValidLyricsFontSize(
    SharedPreferences preferences,
    String key,
  ) {
    final value = preferences.get(key);
    if (value is num) {
      final fontSize = value.toDouble();
      if (PlayerPreferences.isValidInAppLyricsFontSize(fontSize) &&
          PlayerPreferences.isValidDesktopLyricsFontSize(fontSize)) {
        return fontSize;
      }
    }
    return null;
  }

  static Future<void> _migrateLegacyLyricsFontSize(
    SharedPreferences preferences, {
    required double? legacyLyricsFontSize,
    required double inAppLyricsFontSize,
    required double desktopLyricsFontSize,
  }) async {
    if (legacyLyricsFontSize == null) {
      return;
    }

    if (_readValidLyricsFontSize(preferences, _inAppLyricsFontSizeKey) ==
        null) {
      await preferences.setDouble(_inAppLyricsFontSizeKey, inAppLyricsFontSize);
    }
    if (_readValidLyricsFontSize(preferences, _desktopLyricsFontSizeKey) ==
        null) {
      await preferences.setDouble(
        _desktopLyricsFontSizeKey,
        desktopLyricsFontSize,
      );
    }
  }

  static LyricsAlignment _readAlignment(
    SharedPreferences preferences,
    String key,
    LyricsAlignment fallback, {
    required bool allowSplit,
  }) {
    final value = preferences.get(key);
    final alignment = value is String ? LyricsAlignment.fromName(value) : null;
    if (alignment == null ||
        (!allowSplit && alignment == LyricsAlignment.split)) {
      return fallback;
    }
    return alignment;
  }

  static DesktopLyricsLineMode _readDesktopLyricsLineMode(
    SharedPreferences preferences,
  ) {
    final value = preferences.get(_desktopLyricsLineModeKey);
    return value is String
        ? DesktopLyricsLineMode.fromName(value) ??
            PlayerPreferences.defaultDesktopLyricsLineMode
        : PlayerPreferences.defaultDesktopLyricsLineMode;
  }
}
