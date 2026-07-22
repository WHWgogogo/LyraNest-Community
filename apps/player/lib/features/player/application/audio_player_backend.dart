import 'package:media_kit/media_kit.dart';

abstract interface class AudioPlayerBackend {
  Stream<bool> get playing;
  Stream<bool> get buffering;
  Stream<bool> get completed;
  Stream<Duration> get position;
  Stream<Duration> get duration;
  Stream<String> get errors;

  Future<void> open(Uri uri, {required bool play});
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> dispose();
}

class MediaKitAudioPlayerBackend implements AudioPlayerBackend {
  MediaKitAudioPlayerBackend({Player? player}) : _player = player ?? Player();

  final Player _player;

  @override
  Stream<bool> get playing => _player.stream.playing;

  @override
  Stream<bool> get buffering => _player.stream.buffering;

  @override
  Stream<bool> get completed => _player.stream.completed;

  @override
  Stream<Duration> get position => _player.stream.position;

  @override
  Stream<Duration> get duration => _player.stream.duration;

  @override
  Stream<String> get errors => _player.stream.error;

  @override
  Future<void> open(Uri uri, {required bool play}) {
    return _player.open(Media(uri.toString()), play: play);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() => _player.dispose();
}
