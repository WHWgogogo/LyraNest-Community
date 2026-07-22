import '../domain/track.dart';

enum TrackSortField {
  title,
  artist,
  album,
}

enum TrackSortDirection {
  ascending,
  descending,
}

List<Track> sortTracks(
  Iterable<Track> tracks,
  TrackSortField field, [
  TrackSortDirection direction = TrackSortDirection.ascending,
]) {
  final indexedTracks = tracks.indexed.toList(growable: false)
    ..sort((left, right) {
      final leftValue = _valueFor(left.$2, field);
      final rightValue = _valueFor(right.$2, field);
      final comparison = _compareValues(leftValue, rightValue);
      if (comparison != 0) {
        final hasLeftValue = leftValue?.trim().isNotEmpty == true;
        final hasRightValue = rightValue?.trim().isNotEmpty == true;
        if (!hasLeftValue || !hasRightValue) {
          return comparison;
        }
        return direction == TrackSortDirection.ascending
            ? comparison
            : -comparison;
      }
      return left.$1.compareTo(right.$1);
    });

  return List.unmodifiable(
    indexedTracks.map((indexedTrack) => indexedTrack.$2),
  );
}

String? _valueFor(Track track, TrackSortField field) {
  return switch (field) {
    TrackSortField.title => track.title,
    TrackSortField.artist => track.artist,
    TrackSortField.album => track.album,
  };
}

int _compareValues(String? first, String? second) {
  final normalizedFirst = first?.trim() ?? '';
  final normalizedSecond = second?.trim() ?? '';
  final firstIsEmpty = normalizedFirst.isEmpty;
  final secondIsEmpty = normalizedSecond.isEmpty;

  if (firstIsEmpty || secondIsEmpty) {
    if (firstIsEmpty && secondIsEmpty) {
      return 0;
    }
    return firstIsEmpty ? 1 : -1;
  }

  return normalizedFirst
      .toLowerCase()
      .compareTo(normalizedSecond.toLowerCase());
}
