import 'dart:async';

import 'package:flutter/services.dart';

import '../domain/system_media_action.dart';
import '../domain/system_media_state.dart';
import 'system_media_platform.dart';

class AndroidSystemMediaPlatform implements SystemMediaPlatform {
  const AndroidSystemMediaPlatform();

  static const _methodChannel = MethodChannel(
    'com.harmonymusic.player/system_media',
  );
  static const _eventChannel = EventChannel(
    'com.harmonymusic.player/system_media_events',
  );

  @override
  Stream<SystemMediaAction> get actions {
    return _eventChannel
        .receiveBroadcastStream()
        .map(SystemMediaAction.fromEvent)
        .where((action) => action != null)
        .cast<SystemMediaAction>();
  }

  @override
  Future<void> update(SystemMediaState state) {
    return _methodChannel.invokeMethod<void>(
      'update',
      state.toChannelArguments(),
    );
  }

  @override
  Future<void> acknowledgeAction(
    SystemMediaAction action, {
    required bool handled,
  }) {
    return _methodChannel.invokeMethod<void>(
      'ackAction',
      <String, Object?>{
        'action': action.name,
        'handled': handled,
      },
    );
  }

  @override
  Future<void> clear() {
    return _methodChannel.invokeMethod<void>('clear');
  }

  @override
  Future<void> dispose() {
    return _methodChannel.invokeMethod<void>('dispose');
  }
}

class UnsupportedSystemMediaPlatform implements SystemMediaPlatform {
  const UnsupportedSystemMediaPlatform();

  @override
  Stream<SystemMediaAction> get actions => Stream<SystemMediaAction>.empty();

  @override
  Future<void> update(SystemMediaState state) async {}

  @override
  Future<void> acknowledgeAction(
    SystemMediaAction action, {
    required bool handled,
  }) async {}

  @override
  Future<void> clear() async {}

  @override
  Future<void> dispose() async {}
}
