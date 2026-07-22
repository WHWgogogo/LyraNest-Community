import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/presentation/track_sorting.dart';

void main() {
  const tracks = [
    Track(id: 'first-alpha', title: 'Alpha', artist: 'Zed', album: 'Gamma'),
    Track(id: 'second-alpha', title: 'alpha', artist: 'Ada', album: 'Beta'),
    Track(id: 'beta', title: 'Beta', artist: 'Bia', album: 'Alpha'),
    Track(id: 'empty', title: ' ', artist: ' ', album: null),
  ];

  test('sorts titles stably and puts empty values last', () {
    expect(
      sortTracks(tracks, TrackSortField.title).map((track) => track.id),
      ['first-alpha', 'second-alpha', 'beta', 'empty'],
    );
  });

  test('sorts artist and album fields with empty values last', () {
    expect(
      sortTracks(tracks, TrackSortField.artist).map((track) => track.id),
      ['second-alpha', 'beta', 'first-alpha', 'empty'],
    );
    expect(
      sortTracks(tracks, TrackSortField.album).map((track) => track.id),
      ['beta', 'second-alpha', 'first-alpha', 'empty'],
    );
  });

  test('sorts descending while preserving stable ties', () {
    expect(
      sortTracks(
        tracks,
        TrackSortField.title,
        TrackSortDirection.descending,
      ).map((track) => track.id),
      ['beta', 'first-alpha', 'second-alpha', 'empty'],
    );
  });
}
