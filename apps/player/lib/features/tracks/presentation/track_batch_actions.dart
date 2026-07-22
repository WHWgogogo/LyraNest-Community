import '../domain/track.dart';

class TrackBatchResult {
  const TrackBatchResult({
    required this.attempted,
    required this.succeeded,
    required this.skipped,
    required this.failed,
  });

  final int attempted;
  final int succeeded;
  final int skipped;
  final int failed;
}

typedef TrackBatchOperation = Future<bool> Function(Track track);

Future<TrackBatchResult> runTrackBatchSequentially(
  Iterable<Track> tracks,
  TrackBatchOperation operation,
) async {
  var succeeded = 0;
  var skipped = 0;
  var failed = 0;
  var attempted = 0;

  for (final track in tracks) {
    attempted++;
    try {
      if (await operation(track)) {
        succeeded++;
      } else {
        skipped++;
      }
    } catch (_) {
      failed++;
    }
  }

  return TrackBatchResult(
    attempted: attempted,
    succeeded: succeeded,
    skipped: skipped,
    failed: failed,
  );
}
