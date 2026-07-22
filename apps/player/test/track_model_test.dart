import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/lyrics/domain/lyrics.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';

void main() {
  test('Track.fromJson accepts common API field variants', () {
    final track = Track.fromJson({
      'id': 7,
      'title': 'Song',
      'artist': 'Artist',
      'genres': ['Rock', 'Alternative'],
      'duration': '215',
      'url': 'https://example.test/song.mp3',
    });

    expect(track.id, '7');
    expect(track.title, 'Song');
    expect(track.artist, 'Artist');
    expect(track.genres, ['Rock', 'Alternative']);
    expect(track.durationSeconds, 215);
    expect(track.streamUrl, 'https://example.test/song.mp3');
  });

  test('Track.fromJson reads snake case seconds and millisecond duration', () {
    final secondsTrack = Track.fromJson({
      'id': 'seconds',
      'title': 'Seconds',
      'duration_seconds': 125,
    });
    final millisecondsTrack = Track.fromJson({
      'id': 'milliseconds',
      'title': 'Milliseconds',
      'duration_ms': 125999,
      'genre': 'Jazz',
    });

    expect(secondsTrack.durationSeconds, 125);
    expect(millisecondsTrack.durationSeconds, 125);
    expect(millisecondsTrack.genres, ['Jazz']);
  });

  test('TrackList.fromJson reads tracks and total', () {
    final trackList = TrackList.fromJson({
      'tracks': [
        {'id': 'track-1', 'title': 'Song'},
      ],
      'total': 1,
    });

    expect(trackList.total, 1);
    expect(trackList.tracks.single.id, 'track-1');
  });

  test('Lyrics.fromJson reads backend payload fields', () {
    final lyrics = Lyrics.fromJson('fallback-id', {
      'track_id': 'track-1',
      'path': '/music/song.lrc',
      'encoding': 'utf-8',
      'content': 'line 1\nline 2',
    });

    expect(lyrics.trackId, 'track-1');
    expect(lyrics.path, '/music/song.lrc');
    expect(lyrics.encoding, 'utf-8');
    expect(lyrics.content, contains('line 2'));
  });
}
