import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/data/android_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/data/windows_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_capability.dart';
import 'package:player/features/desktop_lyrics/domain/overlay_status.dart';

const _channel = MethodChannel('com.harmonymusic.player/desktop_lyrics');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('Android reports missing notification permission explicitly', () async {
    _setChannelHandler((call) async {
      expect(call.method, 'getStatus');
      return <String, Object?>{
        'platform': 'android',
        'state': 'hidden',
        'canDrawOverlays': true,
        'canPostNotifications': false,
        'isVisible': false,
        'message': '',
      };
    });

    final status = await const AndroidLyricsOverlay().getStatus();

    expect(status.platform, LyricsOverlayPlatform.android);
    expect(status.state, LyricsOverlayState.notificationPermissionDenied);
    expect(status.needsPermission, isTrue);
    expect(
      status.message,
      'Notification permission is required for Android desktop lyrics.',
    );
  });

  test('Android reports native channel failures with method context', () async {
    _setChannelHandler((_) async {
      throw PlatformException(code: 'security', message: 'blocked');
    });

    final status = await const AndroidLyricsOverlay().getStatus();

    expect(status.state, LyricsOverlayState.error);
    expect(
      status.message,
      'Android desktop lyrics getStatus failed (security): blocked',
    );
  });

  test('Android configures a transparent background without permissions',
      () async {
    _setChannelHandler((call) async {
      expect(call.method, 'configure');
      expect(
        call.arguments,
        <String, Object?>{
          'backgroundOpacity': 0.0,
          'textColor': 0xffffffff,
          'fontSize': 22.0,
          'textAlignment': 'right',
          'resetPosition': true,
        },
      );
      return <String, Object?>{
        'platform': 'android',
        'state': 'updated',
        'canDrawOverlays': false,
        'canPostNotifications': false,
        'isVisible': false,
        'message': 'Desktop lyrics overlay configuration was updated.',
      };
    });

    final status = await const AndroidLyricsOverlay().configure(
      backgroundOpacity: 0,
      textColor: 0xffffffff,
      fontSize: 22,
      textAlignment: LyricsTextAlignment.right,
      resetPosition: true,
    );

    expect(status.state, LyricsOverlayState.updated);
    expect(status.isSuccess, isTrue);
  });

  test('Windows turns an unavailable hidden status into an error', () async {
    _setChannelHandler((call) async {
      expect(call.method, 'getStatus');
      return <String, Object?>{
        'platform': 'windows',
        'state': 'hidden',
        'canDrawOverlays': false,
        'isVisible': false,
        'message': 'Transparent overlay creation failed.',
      };
    });

    final status = await const WindowsLyricsOverlay().getStatus();

    expect(status.platform, LyricsOverlayPlatform.windows);
    expect(status.state, LyricsOverlayState.error);
    expect(status.message, 'Transparent overlay creation failed.');
  });
}

void _setChannelHandler(Future<Object?> Function(MethodCall call) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_channel, handler);
}
