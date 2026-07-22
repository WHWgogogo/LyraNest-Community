import 'dart:async';

import '../../player/domain/playback_state.dart';
import '../../tracks/domain/track.dart';
import '../data/system_media_platform.dart';
import '../domain/system_media_action.dart';
import '../domain/system_media_state.dart';

typedef SystemMediaArtworkUrlResolver = String? Function(Track track);
typedef SystemMediaPlayerAction = Future<void> Function();

class SystemMediaController {
  SystemMediaController({
    required SystemMediaPlatform platform,
    required SystemMediaArtworkUrlResolver artworkUrlResolver,
    required SystemMediaPlayerAction onPrevious,
    required SystemMediaPlayerAction onPlay,
    required SystemMediaPlayerAction onPause,
    required SystemMediaPlayerAction onNext,
    required SystemMediaPlayerAction onCyclePlaybackMode,
    required SystemMediaPlayerAction onToggleDesktopLyrics,
  })  : _platform = platform,
        _artworkUrlResolver = artworkUrlResolver,
        _onPrevious = onPrevious,
        _onPlay = onPlay,
        _onPause = onPause,
        _onNext = onNext,
        _onCyclePlaybackMode = onCyclePlaybackMode,
        _onToggleDesktopLyrics = onToggleDesktopLyrics {
    _actionSubscription = _platform.actions.listen(
      _handleAction,
      onError: (_, __) {},
    );
  }

  static const _progressSyncInterval = Duration(milliseconds: 750);

  final SystemMediaPlatform _platform;
  final SystemMediaArtworkUrlResolver _artworkUrlResolver;
  final SystemMediaPlayerAction _onPrevious;
  final SystemMediaPlayerAction _onPlay;
  final SystemMediaPlayerAction _onPause;
  final SystemMediaPlayerAction _onNext;
  final SystemMediaPlayerAction _onCyclePlaybackMode;
  final SystemMediaPlayerAction _onToggleDesktopLyrics;

  StreamSubscription<SystemMediaAction>? _actionSubscription;
  SystemMediaState? _lastState;
  DateTime? _lastProgressSyncAt;
  Future<void> _pendingOperation = Future<void>.value();
  Future<void> _pendingAction = Future<void>.value();
  var _desktopLyricsEnabled = false;
  bool _isDisposed = false;

  Future<void> syncPlayback(PlaybackState playback) {
    if (_isDisposed) {
      return Future<void>.value();
    }

    if (playback.currentTrack == null) {
      if (_lastState == null) {
        return Future<void>.value();
      }
      _lastState = null;
      _lastProgressSyncAt = null;
      return _enqueue(_platform.clear);
    }

    final state = SystemMediaState.fromPlayback(
      playback,
      artworkUrl: _artworkUrlResolver(playback.currentTrack!),
    ).copyWith(desktopLyricsEnabled: _desktopLyricsEnabled);
    if (_shouldSkipSync(state)) {
      return Future<void>.value();
    }

    _lastState = state;
    _lastProgressSyncAt = DateTime.now();
    return _enqueue(() => _platform.update(state));
  }

  Future<void> syncDesktopLyricsEnabled(bool isEnabled) {
    if (_isDisposed || _desktopLyricsEnabled == isEnabled) {
      return Future<void>.value();
    }

    _desktopLyricsEnabled = isEnabled;
    final lastState = _lastState;
    if (lastState == null) {
      return Future<void>.value();
    }

    final state = lastState.copyWith(desktopLyricsEnabled: isEnabled);
    _lastState = state;
    return _enqueue(() => _platform.update(state));
  }

  bool _shouldSkipSync(SystemMediaState state) {
    final lastState = _lastState;
    if (lastState == null || !lastState.matchesPresentation(state)) {
      return false;
    }
    if (lastState.positionMs == state.positionMs) {
      return true;
    }
    final lastProgressSyncAt = _lastProgressSyncAt;
    return lastProgressSyncAt != null &&
        DateTime.now().difference(lastProgressSyncAt) < _progressSyncInterval;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final scheduled = _pendingOperation.then((_) async {
      if (_isDisposed) {
        return;
      }
      try {
        await operation();
      } catch (_) {}
    });
    _pendingOperation = scheduled;
    return scheduled;
  }

  void _handleAction(SystemMediaAction action) {
    if (_isDisposed) {
      return;
    }
    _pendingAction = _pendingAction.then((_) {
      return _runPlayerAction(action, _playerActionFor(action));
    });
  }

  SystemMediaPlayerAction _playerActionFor(SystemMediaAction action) {
    return switch (action) {
      SystemMediaAction.playbackMode => _onCyclePlaybackMode,
      SystemMediaAction.previous => _onPrevious,
      SystemMediaAction.play => _onPlay,
      SystemMediaAction.pause => _onPause,
      SystemMediaAction.next => _onNext,
      SystemMediaAction.desktopLyrics => _onToggleDesktopLyrics,
    };
  }

  Future<void> _runPlayerAction(
    SystemMediaAction mediaAction,
    SystemMediaPlayerAction playerAction,
  ) async {
    var handled = false;
    try {
      await playerAction();
      handled = true;
    } catch (_) {}
    if (_isDisposed) {
      return;
    }
    try {
      await _platform.acknowledgeAction(mediaAction, handled: handled);
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    await _actionSubscription?.cancel();
    _actionSubscription = null;
  }
}
