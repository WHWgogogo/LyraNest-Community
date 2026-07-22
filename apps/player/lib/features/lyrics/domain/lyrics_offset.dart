const lyricsOffsetStep = Duration(milliseconds: 500);

/// Positive offsets make the lyrics appear earlier than the audio.
Duration lyricsTimelinePosition(Duration playbackPosition, Duration offset) {
  final position = playbackPosition + offset;
  return position.isNegative ? Duration.zero : position;
}

Duration playbackPositionForLyricsTimestamp(
  Duration lyricsTimestamp,
  Duration offset,
) {
  return lyricsTimelinePosition(lyricsTimestamp, -offset);
}
