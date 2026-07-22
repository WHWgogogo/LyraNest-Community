String formatPlaybackTime(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  final seconds = totalSeconds % 60;
  final paddedSeconds = seconds.toString().padLeft(2, '0');

  if (hours == 0) {
    return '$minutes:$paddedSeconds';
  }

  final paddedMinutes = minutes.toString().padLeft(2, '0');
  return '$hours:$paddedMinutes:$paddedSeconds';
}
