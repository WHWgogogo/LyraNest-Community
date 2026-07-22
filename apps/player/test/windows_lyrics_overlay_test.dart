import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/data/windows_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';

const _channel = MethodChannel('com.harmonymusic.player/desktop_lyrics');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('Windows forwards configure parameters to the native channel', () async {
    final receivedArguments = <Map<Object?, Object?>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'configure');
      receivedArguments.add(call.arguments! as Map<Object?, Object?>);
      return <String, Object?>{
        'platform': 'windows',
        'state': 'updated',
        'canDrawOverlays': true,
        'isVisible': true,
        'message': 'Windows desktop lyrics configuration was updated.',
      };
    });

    const configurations = <({
      double backgroundOpacity,
      int textColor,
      double fontSize,
      LyricsTextAlignment textAlignment,
      bool resetPosition,
    })>[
      (
        backgroundOpacity: 0,
        textColor: 0x0012ab34,
        fontSize: 14,
        textAlignment: LyricsTextAlignment.left,
        resetPosition: false,
      ),
      (
        backgroundOpacity: 0.6,
        textColor: 0xff12ab34,
        fontSize: 22,
        textAlignment: LyricsTextAlignment.center,
        resetPosition: true,
      ),
      (
        backgroundOpacity: 1,
        textColor: 0xffffffff,
        fontSize: 36,
        textAlignment: LyricsTextAlignment.right,
        resetPosition: false,
      ),
      (
        backgroundOpacity: 0.35,
        textColor: 0xff80deea,
        fontSize: 24,
        textAlignment: LyricsTextAlignment.split,
        resetPosition: false,
      ),
    ];

    for (final configuration in configurations) {
      final status = await const WindowsLyricsOverlay().configure(
        backgroundOpacity: configuration.backgroundOpacity,
        textColor: configuration.textColor,
        fontSize: configuration.fontSize,
        textAlignment: configuration.textAlignment,
        resetPosition: configuration.resetPosition,
      );

      expect(status.state, LyricsOverlayState.updated);
      expect(status.isSuccess, isTrue);
    }

    expect(
      receivedArguments,
      <Map<Object?, Object?>>[
        <String, Object?>{
          'backgroundOpacity': 0.0,
          'textColor': 0x0012ab34,
          'fontSize': 14.0,
          'textAlignment': 'left',
          'resetPosition': false,
        },
        <String, Object?>{
          'backgroundOpacity': 0.6,
          'textColor': 0xff12ab34,
          'fontSize': 22.0,
          'textAlignment': 'center',
          'resetPosition': true,
        },
        <String, Object?>{
          'backgroundOpacity': 1.0,
          'textColor': 0xffffffff,
          'fontSize': 36.0,
          'textAlignment': 'right',
          'resetPosition': false,
        },
        <String, Object?>{
          'backgroundOpacity': 0.35,
          'textColor': 0xff80deea,
          'fontSize': 24.0,
          'textAlignment': 'split',
          'resetPosition': false,
        },
      ],
    );
  });

  test('Windows rejects invalid configure values before invoking native code',
      () async {
    var invocationCount = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (_) async {
      invocationCount += 1;
      return null;
    });

    for (final invalidConfiguration in <({
      double backgroundOpacity,
      int textColor,
      double fontSize,
      String message,
    })>[
      (
        backgroundOpacity: -0.1,
        textColor: 0xffffffff,
        fontSize: 22,
        message: 'backgroundOpacity must be between 0 and 1.',
      ),
      (
        backgroundOpacity: 1.1,
        textColor: 0xffffffff,
        fontSize: 22,
        message: 'backgroundOpacity must be between 0 and 1.',
      ),
      (
        backgroundOpacity: double.nan,
        textColor: 0xffffffff,
        fontSize: 22,
        message: 'backgroundOpacity must be between 0 and 1.',
      ),
      (
        backgroundOpacity: double.infinity,
        textColor: 0xffffffff,
        fontSize: 22,
        message: 'backgroundOpacity must be between 0 and 1.',
      ),
      (
        backgroundOpacity: 0.5,
        textColor: -1,
        fontSize: 22,
        message:
            'textColor must be an ARGB value between 0x00000000 and 0xFFFFFFFF.',
      ),
      (
        backgroundOpacity: 0.5,
        textColor: 4294967296,
        fontSize: 22,
        message:
            'textColor must be an ARGB value between 0x00000000 and 0xFFFFFFFF.',
      ),
    ]) {
      final status = await const WindowsLyricsOverlay().configure(
        backgroundOpacity: invalidConfiguration.backgroundOpacity,
        textColor: invalidConfiguration.textColor,
        fontSize: invalidConfiguration.fontSize,
        textAlignment: LyricsTextAlignment.center,
        resetPosition: false,
      );

      expect(status.state, LyricsOverlayState.error);
      expect(status.message, invalidConfiguration.message);
    }
    expect(invocationCount, 0);
  });

  test('Windows native overlay lays out split lyrics per line', () {
    final overlayHeader = File(
      'windows/runner/lyrics_overlay_window.h',
    ).readAsStringSync();
    final overlaySource = File(
      'windows/runner/lyrics_overlay_window.cpp',
    ).readAsStringSync();
    final channelSource = File(
      'windows/runner/desktop_lyrics_channel.cpp',
    ).readAsStringSync();

    expect(overlayHeader, contains('kSplit,'));
    expect(channelSource, contains('*native_alignment == "split"'));
    expect(overlaySource, contains('SplitCurrentAndNextLyrics(text_)'));
    expect(
      overlaySource,
      contains('Gdiplus::StringAlignmentNear'),
    );
    expect(
      overlaySource,
      contains('Gdiplus::StringAlignmentFar'),
    );
    expect(
      overlaySource,
      contains('graphics.DrawPath(&outline_pen, &current_text_path)'),
    );
    expect(
      overlaySource,
      contains('graphics.DrawPath(&outline_pen, &next_text_path)'),
    );
  });
}
