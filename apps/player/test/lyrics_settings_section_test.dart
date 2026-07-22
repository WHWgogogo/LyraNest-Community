import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_controller.dart';
import 'package:player/features/desktop_lyrics/application/desktop_lyrics_overlay_provider.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/preferences/player_preferences.dart';
import 'package:player/features/settings/presentation/lyrics_settings_section.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('in-app and desktop font size steppers persist independently',
      (tester) async {
    final overlay = _RecordingDesktopLyricsOverlay();
    final container = ProviderContainer(
      overrides: [
        desktopLyricsControllerProvider.overrideWith(
          (ref) => DesktopLyricsController(
            overlay: overlay,
            loadLyrics: (_) async => const Lyrics(
              trackId: 'test',
              path: null,
              encoding: null,
              content: '',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(playerPreferencesProvider.future);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LyricsSettingsSection(
                backgroundOpacity: .35,
                lyricsColorArgb: 0xffffffff,
                desktopLyricsAlignment: LyricsAlignment.center,
                inAppLyricsAlignment: LyricsAlignment.center,
                desktopLyricsLineMode: DesktopLyricsLineMode.singleLine,
                resetPositionOnOpen: false,
                onBackgroundOpacityChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setDesktopLyricsBackgroundOpacity(value);
                  return true;
                },
                onLyricsColorArgbChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setLyricsColorArgb(value);
                  return true;
                },
                onDesktopLyricsAlignmentChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setDesktopLyricsAlignment(value);
                  return true;
                },
                onInAppLyricsAlignmentChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setInAppLyricsAlignment(value);
                  return true;
                },
                onDesktopLyricsLineModeChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setDesktopLyricsLineMode(value);
                  return true;
                },
                onResetPositionOnOpenChanged: (value) async {
                  await container
                      .read(playerPreferencesProvider.notifier)
                      .setResetPositionOnOpen(value);
                  return true;
                },
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('In-app lyrics font size'), findsOneWidget);
    expect(find.text('Desktop lyrics font size'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('in-app-lyrics-font-size-value')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktop-lyrics-font-size-value')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('increase-in-app-lyrics-font-size')),
    );
    await tester.pumpAndSettle();

    expect(
      _fontSizeValue(
        tester,
        const ValueKey('in-app-lyrics-font-size-value'),
      ),
      '24',
    );
    expect(
      container
          .read(playerPreferencesProvider)
          .requireValue
          .inAppLyricsFontSize,
      24,
    );
    expect(
      container
          .read(playerPreferencesProvider)
          .requireValue
          .desktopLyricsFontSize,
      22,
    );
    expect(overlay.fontSizes, isEmpty);

    await tester.tap(
      find.byKey(const ValueKey('increase-desktop-lyrics-font-size')),
    );
    await tester.pumpAndSettle();

    expect(
      _fontSizeValue(
        tester,
        const ValueKey('desktop-lyrics-font-size-value'),
      ),
      '24',
    );
    expect(
      container
          .read(playerPreferencesProvider)
          .requireValue
          .desktopLyricsFontSize,
      24,
    );
    expect(overlay.fontSizes, <double>[24]);

    expect(
      find.byKey(const ValueKey('apply-desktop-lyrics-style')),
      findsNothing,
    );

    final slider = tester.widget<Slider>(
      find.byKey(const ValueKey('desktop-lyrics-background-opacity')),
    );
    slider.onChanged!(0.5);
    await tester.pumpAndSettle();

    expect(overlay.backgroundOpacities.last, 0.5);

    await tester.enterText(find.byType(TextField), '#FF80DEEA');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(overlay.textColors.last, 0xff80deea);

    expect(find.text('Split'), findsNothing);
    final selectors = tester.widgetList<SegmentedButton<LyricsAlignment>>(
      find.byType(SegmentedButton<LyricsAlignment>),
    );
    expect(selectors.first.segments, hasLength(4));
    expect(selectors.first.segments.every((segment) => segment.label == null),
        isTrue);
    expect(selectors.first.segments.last.tooltip, 'Split lyrics alignment');

    await tester.ensureVisible(find.byIcon(Icons.format_align_justify));
    await tester.tap(find.byIcon(Icons.format_align_justify));
    await tester.pumpAndSettle();

    expect(overlay.alignments.last, LyricsTextAlignment.split);

    final updatedSelectors =
        tester.widgetList<SegmentedButton<LyricsAlignment>>(
      find.byType(SegmentedButton<LyricsAlignment>),
    );
    expect(updatedSelectors.last.segments, hasLength(3));
  });

  testWidgets('reports the selected desktop lyrics line mode', (tester) async {
    final selectedModes = <DesktopLyricsLineMode>[];

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: LyricsSettingsSection(
                backgroundOpacity: .35,
                lyricsColorArgb: 0xffffffff,
                desktopLyricsAlignment: LyricsAlignment.center,
                inAppLyricsAlignment: LyricsAlignment.center,
                desktopLyricsLineMode: DesktopLyricsLineMode.singleLine,
                resetPositionOnOpen: false,
                onBackgroundOpacityChanged: (_) async => true,
                onLyricsColorArgbChanged: (_) async => true,
                onDesktopLyricsAlignmentChanged: (_) async => true,
                onInAppLyricsAlignmentChanged: (_) async => true,
                onDesktopLyricsLineModeChanged: (value) async {
                  selectedModes.add(value);
                  return true;
                },
                onResetPositionOnOpenChanged: (_) async => true,
              ),
            ),
          ),
        ),
      ),
    );

    final lineModeSelector =
        tester.widget<SegmentedButton<DesktopLyricsLineMode>>(
      find.byType(SegmentedButton<DesktopLyricsLineMode>),
    );
    expect(lineModeSelector.selected, {DesktopLyricsLineMode.singleLine});

    final doubleLine = find.text('Double line');
    await tester.ensureVisible(doubleLine);
    await tester.tap(doubleLine);
    await tester.pump();

    expect(selectedModes, [DesktopLyricsLineMode.doubleLine]);
  });
}

String _fontSizeValue(WidgetTester tester, Key key) {
  return tester.widget<Text>(find.byKey(key)).data!;
}

class _RecordingDesktopLyricsOverlay implements DesktopLyricsOverlay {
  final fontSizes = <double>[];
  final backgroundOpacities = <double>[];
  final textColors = <int>[];
  final alignments = <LyricsTextAlignment>[];

  static const _status = LyricsOverlayStatus(
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
    fontSizes.add(fontSize);
    backgroundOpacities.add(backgroundOpacity);
    textColors.add(textColor);
    alignments.add(textAlignment);
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
      notes: 'ok',
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
