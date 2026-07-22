import '../../player/domain/playback_state.dart';

class SystemMediaState {
  const SystemMediaState({
    required this.title,
    required this.artist,
    required this.album,
    required this.artworkUrl,
    required this.status,
    required this.isLoading,
    required this.positionMs,
    required this.durationMs,
    required this.canSkipPrevious,
    required this.canSkipNext,
    this.playbackMode = 'sequential',
    this.desktopLyricsEnabled = false,
  });

  factory SystemMediaState.fromPlayback(
    PlaybackState playback, {
    required String? artworkUrl,
  }) {
    final track = playback.currentTrack!;
    return SystemMediaState(
      title: track.title.trim().isEmpty ? 'Untitled track' : track.title.trim(),
      artist: _nonEmpty(track.artist),
      album: _nonEmpty(track.album),
      artworkUrl: _nonEmpty(artworkUrl),
      status: playback.status.name,
      isLoading: playback.isLoading,
      positionMs: playback.position.inMilliseconds,
      durationMs: playback.duration.inMilliseconds,
      canSkipPrevious: playback.canSkipPrevious,
      canSkipNext: playback.canSkipNext,
      playbackMode: playback.playbackMode.name,
    );
  }

  final String title;
  final String? artist;
  final String? album;
  final String? artworkUrl;
  final String status;
  final bool isLoading;
  final int positionMs;
  final int durationMs;
  final bool canSkipPrevious;
  final bool canSkipNext;
  final String playbackMode;
  final bool desktopLyricsEnabled;

  SystemMediaState copyWith({
    bool? desktopLyricsEnabled,
  }) {
    return SystemMediaState(
      title: title,
      artist: artist,
      album: album,
      artworkUrl: artworkUrl,
      status: status,
      isLoading: isLoading,
      positionMs: positionMs,
      durationMs: durationMs,
      canSkipPrevious: canSkipPrevious,
      canSkipNext: canSkipNext,
      playbackMode: playbackMode,
      desktopLyricsEnabled: desktopLyricsEnabled ?? this.desktopLyricsEnabled,
    );
  }

  Map<String, Object?> toChannelArguments() {
    return {
      'title': title,
      'artist': artist,
      'album': album,
      'artworkUrl': artworkUrl,
      'status': status,
      'isLoading': isLoading,
      'positionMs': positionMs,
      'durationMs': durationMs,
      'canSkipPrevious': canSkipPrevious,
      'canSkipNext': canSkipNext,
      'playbackMode': playbackMode,
      'desktopLyricsEnabled': desktopLyricsEnabled,
    };
  }

  bool matchesPresentation(SystemMediaState other) {
    return title == other.title &&
        artist == other.artist &&
        album == other.album &&
        artworkUrl == other.artworkUrl &&
        status == other.status &&
        isLoading == other.isLoading &&
        durationMs == other.durationMs &&
        canSkipPrevious == other.canSkipPrevious &&
        canSkipNext == other.canSkipNext &&
        playbackMode == other.playbackMode &&
        desktopLyricsEnabled == other.desktopLyricsEnabled;
  }
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
