import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error.dart';
import '../../lyrics/domain/lyrics.dart';
import '../../lyrics/domain/lyrics_offset.dart';
import '../../player/domain/playback_state.dart';
import '../../preferences/domain/player_preferences.dart';
import '../domain/desktop_lyrics_overlay.dart';
import '../domain/overlay_capability.dart';
import '../domain/overlay_status.dart';

typedef DesktopLyricsLoader = Future<Lyrics> Function(String trackId);
typedef DesktopLyricsConfigurator = Future<LyricsOverlayStatus> Function({
  required bool resetPosition,
});

@immutable
class DesktopLyricsState {
  const DesktopLyricsState({
    this.isEnabled = false,
    this.isLoadingLyrics = false,
    this.hasLyrics = false,
    this.hasTimedLyrics = false,
    this.overlayStatus,
    this.lyricsErrorMessage,
  });

  final bool isEnabled;
  final bool isLoadingLyrics;
  final bool hasLyrics;
  final bool hasTimedLyrics;
  final LyricsOverlayStatus? overlayStatus;
  final String? lyricsErrorMessage;

  bool get needsPermission => overlayStatus?.needsPermission ?? false;

  DesktopLyricsState copyWith({
    bool? isEnabled,
    bool? isLoadingLyrics,
    bool? hasLyrics,
    bool? hasTimedLyrics,
    LyricsOverlayStatus? overlayStatus,
    String? lyricsErrorMessage,
    bool clearLyricsError = false,
  }) {
    return DesktopLyricsState(
      isEnabled: isEnabled ?? this.isEnabled,
      isLoadingLyrics: isLoadingLyrics ?? this.isLoadingLyrics,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      hasTimedLyrics: hasTimedLyrics ?? this.hasTimedLyrics,
      overlayStatus: overlayStatus ?? this.overlayStatus,
      lyricsErrorMessage: clearLyricsError
          ? null
          : lyricsErrorMessage ?? this.lyricsErrorMessage,
    );
  }
}

class DesktopLyricsController extends StateNotifier<DesktopLyricsState> {
  DesktopLyricsController({
    required DesktopLyricsOverlay overlay,
    required DesktopLyricsLoader loadLyrics,
    DesktopLyricsConfigurator? configure,
  })  : _overlay = overlay,
        _loadLyrics = loadLyrics,
        _configure = configure,
        super(const DesktopLyricsState());

  final DesktopLyricsOverlay _overlay;
  final DesktopLyricsLoader _loadLyrics;
  final DesktopLyricsConfigurator? _configure;

  PlaybackState? _playback;
  ParsedLyrics? _lyrics;
  String? _loadedTrackId;
  String? _lastDisplayedText;
  int _lyricsLoad = 0;
  bool _isDisposed = false;
  bool _hasUiListener = true;
  DesktopLyricsLineMode _lineMode =
      PlayerPreferences.defaultDesktopLyricsLineMode;
  Duration _lyricsOffset = Duration.zero;

  Future<void> updatePlayback(PlaybackState playback) async {
    _playback = playback;
    await _syncForPlayback();
  }

  void setUiListenerActive(bool isActive) {
    _hasUiListener = isActive;
  }

  Future<void> setLineMode(DesktopLyricsLineMode lineMode) async {
    if (_isDisposed || _lineMode == lineMode) {
      return;
    }
    _lineMode = lineMode;
    await _syncForPlayback();
  }

  Future<void> setLyricsOffset(Duration offset) async {
    if (_isDisposed || _lyricsOffset == offset) {
      return;
    }
    _lyricsOffset = offset;
    await _syncForPlayback();
  }

  Future<void> enable() async {
    if (_isDisposed) {
      return;
    }

    state = state.copyWith(
      isEnabled: true,
      clearLyricsError: true,
    );
    final isConfigured = await _configureOverlay(resetPosition: true);
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    if (!isConfigured) {
      state = state.copyWith(isEnabled: false);
      return;
    }

    final status = await _overlay.getStatus();
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    _setOverlayStatus(status);

    if (status.needsPermission) {
      await requestPermission();
      return;
    }
    if (!_canShow(status)) {
      state = state.copyWith(isEnabled: false);
      return;
    }

    await _syncForPlayback();
  }

  Future<void> requestPermission() async {
    if (_isDisposed || !state.isEnabled) {
      return;
    }

    final status = await _overlay.requestPermission();
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    _setOverlayStatus(status);

    if (_canShow(status)) {
      await _syncForPlayback();
    }
  }

  Future<void> refreshStatus() async {
    if (_isDisposed || !state.isEnabled) {
      return;
    }

    final status = await _overlay.getStatus();
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    _setOverlayStatus(status);
    if (_canShow(status)) {
      await _syncForPlayback();
    }
  }

  Future<void> applyDesktopLyricsStyle({
    required double backgroundOpacity,
    required int textColor,
    required double fontSize,
    required LyricsTextAlignment textAlignment,
  }) async {
    if (_isDisposed ||
        !backgroundOpacity.isFinite ||
        backgroundOpacity < 0 ||
        backgroundOpacity > 1 ||
        textColor < 0 ||
        textColor > 0xffffffff ||
        !fontSize.isFinite ||
        fontSize < 14 ||
        fontSize > 36) {
      return;
    }

    final status = await _overlay.configure(
      backgroundOpacity: backgroundOpacity,
      textColor: textColor,
      fontSize: fontSize,
      textAlignment: textAlignment,
      resetPosition: false,
    );
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    _setOverlayStatus(status);
  }

  Future<void> disable() async {
    await Future<void>.delayed(Duration.zero);
    if (_isDisposed || !_hasUiListener) {
      return;
    }

    _lyricsLoad++;
    _lyrics = null;
    _loadedTrackId = null;
    state = state.copyWith(
      isEnabled: false,
      isLoadingLyrics: false,
      hasLyrics: false,
      hasTimedLyrics: false,
      clearLyricsError: true,
    );
    await _hide(force: true);
  }

  Future<void> _syncForPlayback() async {
    if (_isDisposed || !state.isEnabled) {
      return;
    }

    final playback = _playback;
    final track = playback?.currentTrack;
    if (track == null ||
        playback!.status == PlaybackStatus.idle ||
        playback.status == PlaybackStatus.stopped ||
        playback.status == PlaybackStatus.error) {
      await _hide();
      return;
    }

    final status = state.overlayStatus;
    if (status == null || !_canShow(status)) {
      return;
    }

    if (_loadedTrackId != track.id) {
      await _loadLyricsForTrack(track.id);
      return;
    }

    final lyrics = _lyrics;
    if (lyrics == null || state.isLoadingLyrics) {
      return;
    }

    await _display(
      _textForPlayback(
        lyrics,
        lyricsTimelinePosition(playback.position, _lyricsOffset),
      ),
    );
  }

  String _textForPlayback(ParsedLyrics lyrics, Duration position) {
    if (!lyrics.hasTimestamps ||
        _lineMode == DesktopLyricsLineMode.singleLine) {
      return lyrics.textAt(position);
    }

    final activeLineIndex = lyrics.activeLineIndexAt(position);
    if (activeLineIndex == null) {
      return lyrics.textAt(position);
    }

    final currentTimestamp = lyrics.lines[activeLineIndex].timestamp;
    var nextLineIndex = activeLineIndex + 1;
    while (nextLineIndex < lyrics.lines.length &&
        lyrics.lines[nextLineIndex].timestamp == currentTimestamp) {
      nextLineIndex++;
    }
    final currentText = lyrics.textAt(position).trim();
    if (nextLineIndex >= lyrics.lines.length) {
      return currentText;
    }
    final nextText = lyrics.lines[nextLineIndex].text.trim();
    return nextText.isEmpty ? currentText : '$currentText\n$nextText';
  }

  Future<void> _loadLyricsForTrack(String trackId) async {
    final load = ++_lyricsLoad;
    _loadedTrackId = trackId;
    _lyrics = null;
    state = state.copyWith(
      isLoadingLyrics: true,
      hasLyrics: false,
      hasTimedLyrics: false,
      clearLyricsError: true,
    );
    await _hide();

    try {
      final lyrics = await loadDesktopLyricsAllowingNotFound(
        trackId: trackId,
        load: () => _loadLyrics(trackId),
      );
      if (!_isCurrentLoad(load, trackId)) {
        return;
      }

      final parsedLyrics = lyrics.parsed;
      _lyrics = parsedLyrics;
      state = state.copyWith(
        isLoadingLyrics: false,
        hasLyrics: parsedLyrics.lines.isNotEmpty,
        hasTimedLyrics: parsedLyrics.hasTimestamps,
      );
      if (parsedLyrics.lines.isEmpty) {
        await _hide();
        return;
      }

      await _syncForPlayback();
    } catch (error) {
      if (!_isCurrentLoad(load, trackId)) {
        return;
      }

      _lyrics = null;
      state = state.copyWith(
        isLoadingLyrics: false,
        hasLyrics: false,
        hasTimedLyrics: false,
        lyricsErrorMessage: error.toString(),
      );
      await _hide();
    }
  }

  Future<void> _display(String text) async {
    final trimmedText = text.trim();
    if (trimmedText.isEmpty) {
      await _hide();
      return;
    }
    if (_lastDisplayedText == trimmedText) {
      return;
    }

    final LyricsOverlayStatus status;
    if (_lastDisplayedText == null) {
      final isConfigured = await _configureOverlay(resetPosition: false);
      if (_isDisposed || !state.isEnabled || !isConfigured) {
        return;
      }
      status = await _overlay.show(trimmedText);
    } else {
      status = await _overlay.update(trimmedText);
    }
    if (_isDisposed || !state.isEnabled) {
      return;
    }
    _setOverlayStatus(status);
    if (status.isSuccess) {
      _lastDisplayedText = trimmedText;
    }
  }

  Future<void> _hide({bool force = false}) async {
    if (!force && _lastDisplayedText == null) {
      return;
    }

    _lastDisplayedText = null;
    final status = await _overlay.hide();
    if (_isDisposed) {
      return;
    }
    _setOverlayStatus(status);
  }

  Future<bool> _configureOverlay({required bool resetPosition}) async {
    final configure = _configure;
    if (configure == null) {
      return true;
    }

    final status = await configure(resetPosition: resetPosition);
    if (_isDisposed) {
      return false;
    }
    _setOverlayStatus(status);
    return status.isSuccess;
  }

  bool _isCurrentLoad(int load, String trackId) {
    return !_isDisposed &&
        state.isEnabled &&
        load == _lyricsLoad &&
        _loadedTrackId == trackId &&
        _playback?.currentTrack?.id == trackId;
  }

  bool _canShow(LyricsOverlayStatus status) {
    if (!status.isSuccess || status.needsPermission) {
      return false;
    }

    return switch (status.platform) {
      LyricsOverlayPlatform.windows => status.canDrawOverlays,
      LyricsOverlayPlatform.android =>
        status.canDrawOverlays && status.canPostNotifications,
      LyricsOverlayPlatform.unsupported => false,
    };
  }

  void _setOverlayStatus(LyricsOverlayStatus status) {
    state = state.copyWith(overlayStatus: status);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _lyricsLoad++;
    unawaited(_overlay.hide());
    super.dispose();
  }
}

Future<Lyrics> loadDesktopLyricsAllowingNotFound({
  required String trackId,
  required Future<Lyrics> Function() load,
}) async {
  try {
    return await load();
  } on ApiError catch (error) {
    if (error.statusCode != 404) {
      rethrow;
    }

    return Lyrics(
      trackId: trackId,
      path: null,
      encoding: null,
      content: '',
    );
  }
}
