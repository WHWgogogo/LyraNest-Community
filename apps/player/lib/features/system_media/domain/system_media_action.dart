enum SystemMediaAction {
  playbackMode,
  previous,
  play,
  pause,
  next,
  desktopLyrics;

  static SystemMediaAction? fromEvent(Object? event) {
    if (event is! Map<Object?, Object?>) {
      return null;
    }
    final action = event['action'];
    if (action is! String) {
      return null;
    }
    return switch (action) {
      'playbackMode' => SystemMediaAction.playbackMode,
      'previous' => SystemMediaAction.previous,
      'play' => SystemMediaAction.play,
      'pause' => SystemMediaAction.pause,
      'next' => SystemMediaAction.next,
      'desktopLyrics' => SystemMediaAction.desktopLyrics,
      _ => null,
    };
  }
}
