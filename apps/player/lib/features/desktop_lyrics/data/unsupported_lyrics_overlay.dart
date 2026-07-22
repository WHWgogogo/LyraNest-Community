import '../domain/desktop_lyrics_overlay.dart';
import '../domain/overlay_capability.dart';
import '../domain/overlay_status.dart';
import '../../../l10n/l10n.dart';

class UnsupportedLyricsOverlay implements DesktopLyricsOverlay {
  const UnsupportedLyricsOverlay();

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    return LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.unsupported,
      supportsSystemOverlay: false,
      supportsTransparentWindow: false,
      supportsClickThrough: false,
      supportsLockPosition: false,
      requiresRuntimePermission: false,
      notes: await localizedLyricsOverlayCapabilityNotes(
        LyricsOverlayPlatform.unsupported,
      ),
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() async {
    return LyricsOverlayStatus.unsupported(
      platform: LyricsOverlayPlatform.unsupported,
      message: await localizedLyricsOverlayCapabilityNotes(
        LyricsOverlayPlatform.unsupported,
      ),
    );
  }

  @override
  Future<LyricsOverlayStatus> requestPermission() => getStatus();

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) =>
      _notImplemented();

  @override
  Future<LyricsOverlayStatus> show(String text) => _notImplemented();

  @override
  Future<LyricsOverlayStatus> update(String text) => _notImplemented();

  @override
  Future<LyricsOverlayStatus> hide() => _notImplemented();

  @override
  Future<LyricsOverlayStatus> dispose() => getStatus();

  Future<LyricsOverlayStatus> _notImplemented() async {
    return LyricsOverlayStatus.unsupported(
      platform: LyricsOverlayPlatform.unsupported,
      message: await localizedLyricsOverlayNotImplementedMessage(
        LyricsOverlayPlatform.unsupported,
      ),
    );
  }
}
