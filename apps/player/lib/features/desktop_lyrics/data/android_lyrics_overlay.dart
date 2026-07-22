import 'package:flutter/services.dart';

import '../domain/desktop_lyrics_overlay.dart';
import '../domain/overlay_capability.dart';
import '../domain/overlay_status.dart';

class AndroidLyricsOverlay implements DesktopLyricsOverlay {
  const AndroidLyricsOverlay();

  static const MethodChannel _channel = MethodChannel(
    'com.harmonymusic.player/desktop_lyrics',
  );

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    final status = await getStatus();

    return LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.android,
      supportsSystemOverlay: true,
      supportsTransparentWindow: true,
      supportsClickThrough: false,
      supportsLockPosition: true,
      requiresRuntimePermission: true,
      notes: status.message,
    );
  }

  @override
  Future<LyricsOverlayStatus> getStatus() {
    return _invokeStatus('getStatus');
  }

  @override
  Future<LyricsOverlayStatus> requestPermission() {
    return _invokeStatus('requestPermission');
  }

  @override
  Future<LyricsOverlayStatus> configure({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
    required bool resetPosition,
  }) {
    if (!backgroundOpacity.isFinite ||
        backgroundOpacity < 0 ||
        backgroundOpacity > 1) {
      return Future<LyricsOverlayStatus>.value(
        LyricsOverlayStatus.error(
          platform: LyricsOverlayPlatform.android,
          message: 'backgroundOpacity must be between 0 and 1.',
        ),
      );
    }
    if (textColor < 0 || textColor > 0xffffffff) {
      return Future<LyricsOverlayStatus>.value(
        LyricsOverlayStatus.error(
          platform: LyricsOverlayPlatform.android,
          message: 'textColor must be an ARGB value between 0x00000000 and '
              '0xFFFFFFFF.',
        ),
      );
    }
    if (!fontSize.isFinite || fontSize < 14 || fontSize > 36) {
      return Future<LyricsOverlayStatus>.value(
        LyricsOverlayStatus.error(
          platform: LyricsOverlayPlatform.android,
          message: 'fontSize must be between 14 and 36.',
        ),
      );
    }
    return _invokeStatus(
      'configure',
      <String, Object?>{
        'backgroundOpacity': backgroundOpacity,
        'textColor': textColor,
        'fontSize': fontSize,
        'textAlignment': textAlignment.name,
        'resetPosition': resetPosition,
      },
      false,
    );
  }

  @override
  Future<LyricsOverlayStatus> show(String text) {
    return _invokeStatus('show', <String, Object?>{'text': text});
  }

  @override
  Future<LyricsOverlayStatus> update(String text) {
    return _invokeStatus('update', <String, Object?>{'text': text});
  }

  @override
  Future<LyricsOverlayStatus> hide() {
    return _invokeStatus('hide');
  }

  @override
  Future<LyricsOverlayStatus> dispose() {
    return _invokeStatus('dispose');
  }

  Future<LyricsOverlayStatus> _invokeStatus(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
    bool applyPermissionState = true,
  ]) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      return _statusFromResponse(
        response,
        method,
        applyPermissionState: applyPermissionState,
      );
    } on MissingPluginException catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.android,
        message: _channelUnavailableMessage(method, error.message),
      );
    } on PlatformException catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.android,
        message: _platformExceptionMessage(method, error),
      );
    } catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.android,
        message: 'Android desktop lyrics $method failed unexpectedly: $error',
      );
    }
  }

  LyricsOverlayStatus _statusFromResponse(
    Object? response,
    String method, {
    required bool applyPermissionState,
  }) {
    final statusMap = _asNativeMap(response);
    if (statusMap == null) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.android,
        message: 'Android desktop lyrics $method returned an invalid status.',
      );
    }

    final status = LyricsOverlayStatus.fromNativeMap(
      statusMap,
      fallbackPlatform: LyricsOverlayPlatform.android,
    );
    if (status.platform != LyricsOverlayPlatform.android) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.android,
        message:
            'Android desktop lyrics $method returned a ${status.platform.name} status.',
      );
    }
    if (status.state == LyricsOverlayState.error ||
        status.state == LyricsOverlayState.unsupported) {
      return status;
    }
    if (!applyPermissionState) {
      return status;
    }
    if (!status.canDrawOverlays) {
      return LyricsOverlayStatus(
        platform: LyricsOverlayPlatform.android,
        state: status.state == LyricsOverlayState.permissionRequestOpened
            ? LyricsOverlayState.permissionRequestOpened
            : LyricsOverlayState.permissionDenied,
        canDrawOverlays: false,
        canPostNotifications: status.canPostNotifications,
        isVisible: status.isVisible,
        message: _messageOrFallback(
          status.message,
          'Display over other apps permission is required for Android desktop lyrics.',
        ),
      );
    }
    if (!status.canPostNotifications) {
      return LyricsOverlayStatus(
        platform: LyricsOverlayPlatform.android,
        state: LyricsOverlayState.notificationPermissionDenied,
        canDrawOverlays: true,
        canPostNotifications: false,
        isVisible: status.isVisible,
        message: _messageOrFallback(
          status.message,
          'Notification permission is required for Android desktop lyrics.',
        ),
      );
    }
    return status;
  }

  static Map<Object?, Object?>? _asNativeMap(Object? response) {
    if (response is Map<Object?, Object?>) {
      return response;
    }
    if (response is Map) {
      return Map<Object?, Object?>.from(response);
    }
    return null;
  }

  static String _channelUnavailableMessage(String method, String? message) {
    return 'Android desktop lyrics $method is unavailable: '
        '${_messageOrFallback(message, 'the native channel is not registered.')}';
  }

  static String _platformExceptionMessage(
    String method,
    PlatformException error,
  ) {
    return 'Android desktop lyrics $method failed (${error.code}): '
        '${_messageOrFallback(error.message, 'no native error message was provided.')}';
  }

  static String _messageOrFallback(String? message, String fallback) {
    if (message == null || message.trim().isEmpty) {
      return fallback;
    }
    return message;
  }
}
