import 'overlay_capability.dart';

enum LyricsOverlayState {
  unsupported,
  permissionGranted,
  permissionDenied,
  permissionRequestOpened,
  notificationPermissionDenied,
  showRequested,
  visible,
  updated,
  hidden,
  disposed,
  error,
}

class LyricsOverlayStatus {
  const LyricsOverlayStatus({
    required this.platform,
    required this.state,
    required this.canDrawOverlays,
    required this.canPostNotifications,
    required this.isVisible,
    required this.message,
  });

  final LyricsOverlayPlatform platform;
  final LyricsOverlayState state;
  final bool canDrawOverlays;
  final bool canPostNotifications;
  final bool isVisible;
  final String message;

  bool get isSuccess {
    return state != LyricsOverlayState.error &&
        state != LyricsOverlayState.permissionDenied &&
        state != LyricsOverlayState.notificationPermissionDenied &&
        state != LyricsOverlayState.unsupported;
  }

  bool get needsPermission {
    return state == LyricsOverlayState.permissionDenied ||
        state == LyricsOverlayState.permissionRequestOpened ||
        state == LyricsOverlayState.notificationPermissionDenied;
  }

  factory LyricsOverlayStatus.fromNativeMap(
    Map<Object?, Object?> map, {
    LyricsOverlayPlatform fallbackPlatform = LyricsOverlayPlatform.unsupported,
  }) {
    final platformName = map['platform'] as String?;
    final stateName = map['state'] as String?;
    final message = map['message'] as String?;

    return LyricsOverlayStatus(
      platform: _platformFromName(platformName) ?? fallbackPlatform,
      state: _stateFromName(stateName) ?? LyricsOverlayState.error,
      canDrawOverlays: map['canDrawOverlays'] == true,
      canPostNotifications: map['canPostNotifications'] == true,
      isVisible: map['isVisible'] == true,
      message: message ?? 'Unknown desktop lyrics overlay status.',
    );
  }

  factory LyricsOverlayStatus.unsupported({
    required LyricsOverlayPlatform platform,
    required String message,
  }) {
    return LyricsOverlayStatus(
      platform: platform,
      state: LyricsOverlayState.unsupported,
      canDrawOverlays: false,
      canPostNotifications: false,
      isVisible: false,
      message: message,
    );
  }

  factory LyricsOverlayStatus.error({
    required LyricsOverlayPlatform platform,
    required String message,
  }) {
    return LyricsOverlayStatus(
      platform: platform,
      state: LyricsOverlayState.error,
      canDrawOverlays: false,
      canPostNotifications: false,
      isVisible: false,
      message: message,
    );
  }

  static LyricsOverlayPlatform? _platformFromName(String? name) {
    for (final platform in LyricsOverlayPlatform.values) {
      if (platform.name == name) {
        return platform;
      }
    }
    return null;
  }

  static LyricsOverlayState? _stateFromName(String? name) {
    for (final state in LyricsOverlayState.values) {
      if (state.name == name) {
        return state;
      }
    }
    return null;
  }
}
