import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/desktop_lyrics/data/android_lyrics_overlay.dart';
import 'package:player/features/desktop_lyrics/domain/desktop_lyrics_overlay.dart';

const _channel = MethodChannel('com.harmonymusic.player/desktop_lyrics');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, null);
  });

  test('Android sends canonical alignment names to the native channel',
      () async {
    final receivedAlignments = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
      expect(call.method, 'configure');
      final arguments = call.arguments! as Map<Object?, Object?>;
      receivedAlignments.add(arguments['textAlignment']! as String);
      return <String, Object?>{
        'platform': 'android',
        'state': 'updated',
        'canDrawOverlays': true,
        'canPostNotifications': true,
        'isVisible': false,
        'message': 'Desktop lyrics overlay configuration was updated.',
      };
    });

    for (final alignment in LyricsTextAlignment.values) {
      await const AndroidLyricsOverlay().configure(
        backgroundOpacity: 0.6,
        textColor: 0xffffffff,
        fontSize: 22,
        textAlignment: alignment,
        resetPosition: false,
      );
    }

    expect(
      receivedAlignments,
      <String>['left', 'center', 'right', 'split'],
    );
  });
}
