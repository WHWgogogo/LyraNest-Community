import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/presentation/track_batch_actions.dart';

void main() {
  test('runs track operations sequentially and aggregates outcomes', () async {
    const tracks = [
      Track(id: 'first', title: 'First'),
      Track(id: 'second', title: 'Second'),
      Track(id: 'third', title: 'Third'),
    ];
    final calls = <String>[];
    var inFlight = 0;
    var maximumInFlight = 0;

    final result = await runTrackBatchSequentially(tracks, (track) async {
      calls.add(track.id);
      inFlight++;
      maximumInFlight = maximumInFlight < inFlight ? inFlight : maximumInFlight;
      try {
        await Future<void>.delayed(Duration.zero);
        if (track.id == 'third') {
          throw StateError('download failed');
        }
        return track.id == 'first';
      } finally {
        inFlight--;
      }
    });

    expect(calls, ['first', 'second', 'third']);
    expect(maximumInFlight, 1);
    expect(result.attempted, 3);
    expect(result.succeeded, 1);
    expect(result.skipped, 1);
    expect(result.failed, 1);
  });
}
