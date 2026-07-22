import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/scrape/domain/scrape_models.dart';

void main() {
  test('ScrapeSearchResult normalizes confidence and field differences', () {
    final result = ScrapeSearchResult.fromJson('fallback-track', {
      'track_id': 'track-1',
      'candidates': [
        {
          'candidate_id': 'candidate-1',
          'provider': 'MusicBrainz',
          'confidence': 92,
          'metadata': {
            'title': 'Matched Song',
            'genres': ['Rock', 'Pop'],
          },
          'differences': [
            {
              'field': 'title',
              'current': 'Old Song',
              'candidate': 'Matched Song',
              'changed': true,
            },
          ],
        },
      ],
    });

    final candidate = result.candidates.single;
    expect(result.trackId, 'track-1');
    expect(candidate.id, 'candidate-1');
    expect(candidate.confidence, 0.92);
    expect(candidate.metadata[ScrapeField.genre], 'Rock, Pop');
    expect(candidate.differences.single.field, ScrapeField.title);
  });

  test('ScrapeApplyResult reads applied fields and updated track', () {
    final result = ScrapeApplyResult.fromJson(
      {
        'track': {
          'id': 'track-1',
          'title': 'Matched Song',
          'genres': ['Rock'],
          'duration_ms': 181000,
        },
        'provider': 'MusicBrainz',
        'applied_fields': ['title', 'genre'],
        'applied_at': '2026-07-18T12:05:00Z',
      },
      trackId: 'track-1',
      provider: 'fallback',
      requestedFields: const [ScrapeField.title],
    );

    expect(result.provider, 'MusicBrainz');
    expect(result.appliedFields, [ScrapeField.title, ScrapeField.genre]);
    expect(result.track.durationSeconds, 181);
    expect(result.track.genres, ['Rock']);
  });

  test('ScrapeSearchQuery serializes manual fields and an optional limit', () {
    const query = ScrapeSearchQuery(
      title: '  Matched Song  ',
      artist: 'Matched Artist',
      album: 'Matched Album',
      limit: 8,
    );

    expect(query.toJson(), {
      'title': 'Matched Song',
      'artist': 'Matched Artist',
      'album': 'Matched Album',
      'limit': 8,
    });
    expect(
      const ScrapeSearchQuery(title: ' ', limit: 0).toJson(),
      isEmpty,
    );
  });
}
