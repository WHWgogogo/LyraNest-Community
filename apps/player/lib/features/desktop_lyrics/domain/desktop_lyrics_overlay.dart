import 'overlay_capability.dart';
import 'overlay_status.dart';

enum LyricsTextAlignment {
  left,
  center,
  right,
  split,
}

abstract interface class DesktopLyricsOverlay {
  Future<LyricsOverlayCapability> getCapability();

  Future<LyricsOverlayStatus> getStatus();

  Future<LyricsOverlayStatus> requestPermission();

  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  });

  Future<LyricsOverlayStatus> show(String text);

  Future<LyricsOverlayStatus> update(String text);

  Future<LyricsOverlayStatus> hide();

  Future<LyricsOverlayStatus> dispose();
}
