import '../domain/system_media_action.dart';
import '../domain/system_media_state.dart';

abstract interface class SystemMediaPlatform {
  Stream<SystemMediaAction> get actions;

  Future<void> update(SystemMediaState state);

  Future<void> acknowledgeAction(
    SystemMediaAction action, {
    required bool handled,
  });

  Future<void> clear();

  Future<void> dispose();
}
