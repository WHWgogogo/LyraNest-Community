import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';
import 'package:player/features/preferences/player_preferences.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('exposes defaults through the aggregate and selector providers',
      () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    final preferences = await container.read(playerPreferencesProvider.future);

    expect(preferences, const PlayerPreferences());
    expect(
      container.read(desktopLyricsBackgroundOpacityProvider),
      PlayerPreferences.defaultDesktopLyricsBackgroundOpacity,
    );
    expect(
      container.read(lyricsColorArgbProvider),
      PlayerPreferences.defaultLyricsColorArgb,
    );
    expect(
      container.read(inAppLyricsFontSizeProvider),
      PlayerPreferences.defaultInAppLyricsFontSize,
    );
    expect(
      container.read(desktopLyricsFontSizeProvider),
      PlayerPreferences.defaultDesktopLyricsFontSize,
    );
    expect(
      container.read(desktopLyricsAlignmentProvider),
      PlayerPreferences.defaultDesktopLyricsAlignment,
    );
    expect(container.read(desktopLyricsTextAlignProvider), TextAlign.center);
    expect(
      container.read(inAppLyricsAlignmentProvider),
      PlayerPreferences.defaultInAppLyricsAlignment,
    );
    expect(container.read(inAppLyricsTextAlignProvider), TextAlign.center);
    expect(
      container.read(desktopLyricsLineModeProvider),
      PlayerPreferences.defaultDesktopLyricsLineMode,
    );
    expect(
      container.read(resetPositionOnOpenProvider),
      PlayerPreferences.defaultResetPositionOnOpen,
    );
  });

  test('updates providers and restores all preferences', () async {
    final firstContainer = ProviderContainer();
    final controller = firstContainer.read(playerPreferencesProvider.notifier);
    await firstContainer.read(playerPreferencesProvider.future);

    await controller.setDesktopLyricsBackgroundOpacity(0.7);
    await controller.setLyricsColorArgb(0xff80deea);
    await controller.setInAppLyricsFontSize(28);
    await controller.setDesktopLyricsFontSize(30);
    await controller.setDesktopLyricsAlignment(LyricsAlignment.split);
    await controller.setInAppLyricsTextAlign(TextAlign.left);
    await controller.setDesktopLyricsLineMode(DesktopLyricsLineMode.doubleLine);
    await controller.setResetPositionOnOpen(true);

    expect(firstContainer.read(desktopLyricsBackgroundOpacityProvider), 0.7);
    expect(firstContainer.read(lyricsColorArgbProvider), 0xff80deea);
    expect(firstContainer.read(inAppLyricsFontSizeProvider), 28);
    expect(firstContainer.read(desktopLyricsFontSizeProvider), 30);
    expect(
      firstContainer.read(desktopLyricsAlignmentProvider),
      LyricsAlignment.split,
    );
    expect(
      firstContainer.read(inAppLyricsAlignmentProvider),
      LyricsAlignment.left,
    );
    expect(
      firstContainer.read(desktopLyricsLineModeProvider),
      DesktopLyricsLineMode.doubleLine,
    );
    expect(firstContainer.read(resetPositionOnOpenProvider), isTrue);
    firstContainer.dispose();

    final secondContainer = ProviderContainer();
    addTearDown(secondContainer.dispose);
    final restored =
        await secondContainer.read(playerPreferencesProvider.future);

    expect(
      restored,
      const PlayerPreferences(
        desktopLyricsBackgroundOpacity: 0.7,
        lyricsColorArgb: 0xff80deea,
        inAppLyricsFontSize: 28,
        desktopLyricsFontSize: 30,
        desktopLyricsAlignment: LyricsAlignment.split,
        inAppLyricsAlignment: LyricsAlignment.left,
        desktopLyricsLineMode: DesktopLyricsLineMode.doubleLine,
        resetPositionOnOpen: true,
      ),
    );
  });

  test('falls back per field when stored values are invalid', () async {
    SharedPreferences.setMockInitialValues({
      'player_preferences.desktop_lyrics_background_opacity.v1': 1.5,
      'player_preferences.lyrics_color_argb.v1': -1,
      'player_preferences.in_app_lyrics_font_size.v1': 23.0,
      'player_preferences.desktop_lyrics_font_size.v1': 25.0,
      'player_preferences.desktop_lyrics_alignment.v1': 'justify',
      'player_preferences.in_app_lyrics_alignment.v1': 'split',
      'player_preferences.desktop_lyrics_line_mode.v1': 'threeLines',
      'player_preferences.reset_desktop_lyrics_position_on_open.v1': 'yes',
    });
    final repository = SharedPreferencesPlayerPreferencesRepository();

    final preferences = await repository.load();

    expect(
      preferences.desktopLyricsBackgroundOpacity,
      PlayerPreferences.defaultDesktopLyricsBackgroundOpacity,
    );
    expect(
      preferences.lyricsColorArgb,
      PlayerPreferences.defaultLyricsColorArgb,
    );
    expect(
      preferences.inAppLyricsFontSize,
      PlayerPreferences.defaultInAppLyricsFontSize,
    );
    expect(
      preferences.desktopLyricsFontSize,
      PlayerPreferences.defaultDesktopLyricsFontSize,
    );
    expect(
      preferences.desktopLyricsAlignment,
      PlayerPreferences.defaultDesktopLyricsAlignment,
    );
    expect(
      preferences.inAppLyricsAlignment,
      PlayerPreferences.defaultInAppLyricsAlignment,
    );
    expect(
      preferences.desktopLyricsLineMode,
      PlayerPreferences.defaultDesktopLyricsLineMode,
    );
    expect(
      preferences.resetPositionOnOpen,
      PlayerPreferences.defaultResetPositionOnOpen,
    );
  });

  test('validates opacity and ARGB writes', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(playerPreferencesProvider.notifier);
    await container.read(playerPreferencesProvider.future);

    await expectLater(
      controller.setDesktopLyricsBackgroundOpacity(double.nan),
      throwsRangeError,
    );
    await expectLater(
        controller.setLyricsColorArgb(0x100000000), throwsRangeError);
    await expectLater(controller.setInAppLyricsFontSize(23), throwsRangeError);
    await expectLater(
      controller.setDesktopLyricsFontSize(23),
      throwsRangeError,
    );
    await expectLater(
      controller.setInAppLyricsAlignment(LyricsAlignment.split),
      throwsArgumentError,
    );
    expect(
      container.read(playerPreferencesProvider).requireValue,
      const PlayerPreferences(),
    );
  });

  test('migrates a legacy shared font size to both independent values',
      () async {
    SharedPreferences.setMockInitialValues({
      'player_preferences.lyrics_font_size.v1': 28.0,
    });
    final repository = SharedPreferencesPlayerPreferencesRepository();

    final preferences = await repository.load();
    final storedPreferences = await SharedPreferences.getInstance();

    expect(preferences.inAppLyricsFontSize, 28);
    expect(preferences.desktopLyricsFontSize, 28);
    expect(
      storedPreferences.getDouble(
        'player_preferences.in_app_lyrics_font_size.v1',
      ),
      28,
    );
    expect(
      storedPreferences.getDouble(
        'player_preferences.desktop_lyrics_font_size.v1',
      ),
      28,
    );
  });

  test('keeps independently persisted font sizes over the legacy value',
      () async {
    SharedPreferences.setMockInitialValues({
      'player_preferences.lyrics_font_size.v1': 28.0,
      'player_preferences.in_app_lyrics_font_size.v1': 20.0,
      'player_preferences.desktop_lyrics_font_size.v1': 32.0,
    });
    final repository = SharedPreferencesPlayerPreferencesRepository();

    final preferences = await repository.load();

    expect(preferences.inAppLyricsFontSize, 20);
    expect(preferences.desktopLyricsFontSize, 32);
  });

  test('maps UI alignment and desktop configure arguments', () async {
    const preferences = PlayerPreferences(
      desktopLyricsBackgroundOpacity: 0.6,
      lyricsColorArgb: 0xff123456,
      inAppLyricsFontSize: 20,
      desktopLyricsFontSize: 30,
      desktopLyricsAlignment: LyricsAlignment.split,
      inAppLyricsAlignment: LyricsAlignment.left,
      resetPositionOnOpen: true,
    );
    final overlay = _RecordingDesktopLyricsOverlay();

    await preferences.configureDesktopLyrics(overlay);

    expect(preferences.desktopLyricsTextAlign, TextAlign.left);
    expect(preferences.inAppLyricsTextAlign, TextAlign.left);
    expect(
        LyricsAlignment.fromTextAlign(TextAlign.start), LyricsAlignment.left);
    expect(overlay.backgroundOpacity, 0.6);
    expect(overlay.textColor, 0xff123456);
    expect(overlay.fontSize, 30);
    expect(overlay.textAlignment, LyricsTextAlignment.split);
    expect(overlay.resetPosition, isTrue);
  });
}

class _RecordingDesktopLyricsOverlay implements DesktopLyricsOverlay {
  double? backgroundOpacity;
  int? textColor;
  double? fontSize;
  LyricsTextAlignment? textAlignment;
  bool? resetPosition;

  LyricsOverlayStatus get _status => const LyricsOverlayStatus(
        platform: LyricsOverlayPlatform.windows,
        state: LyricsOverlayState.updated,
        canDrawOverlays: true,
        canPostNotifications: true,
        isVisible: false,
        message: 'ok',
      );

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) async {
    this.backgroundOpacity = backgroundOpacity;
    this.textColor = textColor;
    this.fontSize = fontSize;
    this.textAlignment = textAlignment;
    this.resetPosition = resetPosition;
    return _status;
  }

  @override
  Future<LyricsOverlayStatus> dispose() async => _status;

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    return const LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.windows,
      supportsSystemOverlay: true,
      supportsTransparentWindow: true,
      supportsClickThrough: true,
      supportsLockPosition: true,
      requiresRuntimePermission: false,
      notes: '',
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() async => _status;

  @override
  Future<LyricsOverlayStatus> hide() async => _status;

  @override
  Future<LyricsOverlayStatus> requestPermission() async => _status;

  @override
  Future<LyricsOverlayStatus> show(String text) async => _status;

  @override
  Future<LyricsOverlayStatus> update(String text) async => _status;
}
