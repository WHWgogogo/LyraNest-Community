import 'package:flutter/services.dart';

abstract interface class AppLifecyclePlatform {
  Future<void> moveTaskToBack();

  Future<void> exitApplication();
}

AppLifecyclePlatform appLifecyclePlatformFor(TargetPlatform platform) {
  return switch (platform) {
    TargetPlatform.android => const AndroidAppLifecyclePlatform(),
    _ => const UnsupportedAppLifecyclePlatform(),
  };
}

class AndroidAppLifecyclePlatform implements AppLifecyclePlatform {
  const AndroidAppLifecyclePlatform();

  static const _methodChannel = MethodChannel(
    'com.harmonymusic.player/app_lifecycle',
  );

  @override
  Future<void> moveTaskToBack() {
    return _methodChannel.invokeMethod<void>('moveTaskToBack');
  }

  @override
  Future<void> exitApplication() {
    return _methodChannel.invokeMethod<void>('exitApplication');
  }
}

class UnsupportedAppLifecyclePlatform implements AppLifecyclePlatform {
  const UnsupportedAppLifecyclePlatform();

  @override
  Future<void> moveTaskToBack() async {}

  @override
  Future<void> exitApplication() async {}
}
