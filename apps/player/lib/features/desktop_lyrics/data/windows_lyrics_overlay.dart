import 'package:flutter/services.dart';

import '../domain/desktop_lyrics_overlay.dart';
import '../domain/overlay_capability.dart';
import '../domain/overlay_status.dart';

class WindowsLyricsOverlay implements DesktopLyricsOverlay {
  const WindowsLyricsOverlay();

  static const MethodChannel _channel = MethodChannel(
    'com.harmonymusic.player/desktop_lyrics',
  );

  @override
  Future<LyricsOverlayCapability> getCapability() async {
    try {
      final response = await _channel.invokeMethod<Object?>('getCapability');
      final capability = _asNativeMap(response);
      if (capability == null) {
        return _unavailableCapability(
          'Windows overlay returned an invalid capability response.',
        );
      }
      final platform = capability['platform'];
      if (platform != 'windows') {
        return _unavailableCapability(
          'Windows overlay returned a ${platform ?? 'missing'} platform capability.',
        );
      }

      return LyricsOverlayCapability(
        platform: LyricsOverlayPlatform.windows,
        supportsSystemOverlay: capability['supportsSystemOverlay'] == true,
        supportsTransparentWindow:
            capability['supportsTransparentWindow'] == true,
        supportsClickThrough: capability['supportsClickThrough'] == true,
        supportsLockPosition: capability['supportsLockPosition'] == true,
        requiresRuntimePermission:
            capability['requiresRuntimePermission'] == true,
        notes: capability['notes'] as String? ??
            'Windows lyrics overlay is available.',
      );
    } on MissingPluginException catch (error) {
      return _unavailableCapability(
        error.message ?? 'Windows overlay channel is unavailable.',
      );
    } on PlatformException catch (error) {
      return _unavailableCapability(error.message ?? error.code);
    } catch (error) {
      return _unavailableCapability(error.toString());
    }
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
          platform: LyricsOverlayPlatform.windows,
          message: 'backgroundOpacity must be between 0 and 1.',
        ),
      );
    }
    if (textColor < 0 || textColor > 0xffffffff) {
      return Future<LyricsOverlayStatus>.value(
        LyricsOverlayStatus.error(
          platform: LyricsOverlayPlatform.windows,
          message: 'textColor must be an ARGB value between 0x00000000 and '
              '0xFFFFFFFF.',
        ),
      );
    }
    if (!fontSize.isFinite || fontSize < 14 || fontSize > 36) {
      return Future<LyricsOverlayStatus>.value(
        LyricsOverlayStatus.error(
          platform: LyricsOverlayPlatform.windows,
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

  Future<LyricsOverlayStatus> setLocked(bool locked) {
    return _invokeStatus(
      'setLocked',
      <String, Object?>{'locked': locked},
    );
  }

  Future<LyricsOverlayStatus> _invokeStatus(
    String method, [
    Map<String, Object?> arguments = const <String, Object?>{},
  ]) async {
    try {
      final response = await _channel.invokeMethod<Object?>(method, arguments);
      final status = _asNativeMap(response);
      if (status != null) {
        return _statusFromNativeMap(status, method);
      }
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message: 'Windows desktop lyrics $method returned an invalid status.',
      );
    } on MissingPluginException catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message: _channelUnavailableMessage(method, error.message),
      );
    } on PlatformException catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message: _platformExceptionMessage(method, error),
      );
    } catch (error) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message: 'Windows desktop lyrics $method failed unexpectedly: $error',
      );
    }
  }

  LyricsOverlayStatus _statusFromNativeMap(
    Map<Object?, Object?> statusMap,
    String method,
  ) {
    final status = LyricsOverlayStatus.fromNativeMap(
      statusMap,
      fallbackPlatform: LyricsOverlayPlatform.windows,
    );
    if (status.platform != LyricsOverlayPlatform.windows) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message:
            'Windows desktop lyrics $method returned a ${status.platform.name} status.',
      );
    }
    if (_requiresAvailableOverlay(method) &&
        status.isSuccess &&
        !status.canDrawOverlays) {
      return LyricsOverlayStatus.error(
        platform: LyricsOverlayPlatform.windows,
        message: _messageOrFallback(
          status.message,
          'Windows desktop lyrics overlay is unavailable.',
        ),
      );
    }
    return status;
  }

  static bool _requiresAvailableOverlay(String method) {
    return switch (method) {
      'getStatus' || 'requestPermission' || 'show' || 'update' => true,
      _ => false,
    };
  }

  static String _channelUnavailableMessage(String method, String? message) {
    return 'Windows desktop lyrics $method is unavailable: '
        '${_messageOrFallback(message, 'the native channel is not registered.')}';
  }

  static String _platformExceptionMessage(
    String method,
    PlatformException error,
  ) {
    return 'Windows desktop lyrics $method failed (${error.code}): '
        '${_messageOrFallback(error.message, 'no native error message was provided.')}';
  }

  static String _messageOrFallback(String? message, String fallback) {
    if (message == null || message.trim().isEmpty) {
      return fallback;
    }
    return message;
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

  static LyricsOverlayCapability _unavailableCapability(String message) {
    return LyricsOverlayCapability(
      platform: LyricsOverlayPlatform.windows,
      supportsSystemOverlay: false,
      supportsTransparentWindow: false,
      supportsClickThrough: false,
      supportsLockPosition: false,
      requiresRuntimePermission: false,
      notes: message,
    );
  }
}
