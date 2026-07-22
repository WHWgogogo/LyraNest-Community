import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/management/domain/library_scan_result.dart';
import 'package:player/features/management/domain/library_status.dart';

void main() {
  test('LibraryStatus reads backend snake case fields', () {
    final status = LibraryStatus.fromJson({
      'directory': r'C:\Music',
      'track_count': '3',
      'scanning': true,
      'last_scanned_at': '2026-07-18T12:00:00Z',
      'last_error': '  ',
    });

    expect(status.directory, r'C:\Music');
    expect(status.trackCount, 3);
    expect(status.scanning, isTrue);
    expect(status.lastScannedAt, DateTime.utc(2026, 7, 18, 12));
    expect(status.lastError, isNull);
  });

  test('LibraryScanResult reads tracks, total, and scan time', () {
    final result = LibraryScanResult.fromJson({
      'tracks': [
        {
          'id': 'track-1',
          'title': 'Song',
          'duration_ms': 90500,
          'genres': ['Pop'],
        },
      ],
      'total': 1,
      'scanned_at': '2026-07-18T12:01:00Z',
    });

    expect(result.total, 1);
    expect(result.scannedAt, DateTime.utc(2026, 7, 18, 12, 1));
    expect(result.tracks.single.durationSeconds, 90);
    expect(result.tracks.single.genres, ['Pop']);
  });
}
