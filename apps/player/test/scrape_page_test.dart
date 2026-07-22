import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/scrape/data/scrape_api.dart';
import 'package:player/features/scrape/domain/scrape_models.dart';
import 'package:player/features/scrape/presentation/scrape_page.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('allows selecting fields and applies a candidate',
      (tester) async {
    final api = _FakeScrapeApi();
    var trackLoads = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scrapeApiProvider.overrideWithValue(api),
          tracksProvider.overrideWith((ref) async {
            trackLoads += 1;
            return const TrackList(tracks: [], total: 0);
          }),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('92% confidence'), findsOneWidget);
    expect(find.text('Rock'), findsAtLeastNWidgets(1));

    final mobileScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
      description: 'mobile scrape page vertical scrollable',
    );
    final artistTile = find.widgetWithText(CheckboxListTile, 'Artist');
    await tester.scrollUntilVisible(
      artistTile,
      300,
      scrollable: mobileScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(artistTile);

    final genreTile = find.widgetWithText(CheckboxListTile, 'Genre');
    await tester.scrollUntilVisible(
      genreTile,
      300,
      scrollable: mobileScrollable,
    );
    await tester.pumpAndSettle();

    expect(find.text('Alternative'), findsAtLeastNWidgets(1));

    await tester.tap(genreTile);

    final applyButton =
        find.widgetWithText(FilledButton, 'Apply selected fields');
    await tester.ensureVisible(applyButton);
    await tester.pumpAndSettle();
    await tester.tap(applyButton);
    await tester.pumpAndSettle();

    expect(api.appliedFields, [ScrapeField.title]);
    expect(trackLoads, 1);
    expect(
      find.text('Applied 1 fields from MusicBrainz.'),
      findsAtLeastNWidgets(1),
    );
  });

  testWidgets('searches again with edited title, artist, and album',
      (tester) async {
    final api = _FakeScrapeApi();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scrapeApiProvider.overrideWithValue(api),
          tracksProvider.overrideWith(
            (ref) async => const TrackList(tracks: [], total: 0),
          ),
        ],
        child: const _TestApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('scrape-search-title')),
      'Manual title',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scrape-search-artist')),
      'Manual artist',
    );
    await tester.enterText(
      find.byKey(const ValueKey('scrape-search-album')),
      'Manual album',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Search again'));
    await tester.pumpAndSettle();

    expect(
      api.searchQueries.last.toJson(),
      {
        'title': 'Manual title',
        'artist': 'Manual artist',
        'album': 'Manual album',
      },
    );
    expect(find.text('Active search'), findsOneWidget);
    expect(find.text('Title: Manual title'), findsOneWidget);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const ScrapePage(
        trackId: 'track-1',
        track: Track(
          id: 'track-1',
          title: 'Old Song',
          artist: 'Old Artist',
          genres: ['Rock'],
        ),
      ),
    );
  }
}

class _FakeScrapeApi implements ScrapeApi {
  List<ScrapeField>? appliedFields;
  final List<ScrapeSearchQuery> searchQueries = [];

  @override
  Future<ScrapeSearchResult> search(
    String trackId, {
    ScrapeSearchQuery query = const ScrapeSearchQuery(),
  }) async {
    searchQueries.add(query);
    return const ScrapeSearchResult(
      trackId: 'track-1',
      candidates: [
        ScrapeCandidate(
          id: 'candidate-1',
          provider: 'MusicBrainz',
          confidence: 0.92,
          metadata: {
            ScrapeField.title: 'Matched Song',
            ScrapeField.artist: 'Matched Artist',
            ScrapeField.genre: 'Alternative',
          },
          differences: [
            ScrapeFieldDifference(
              field: ScrapeField.title,
              current: 'Old Song',
              candidate: 'Matched Song',
              changed: true,
            ),
            ScrapeFieldDifference(
              field: ScrapeField.artist,
              current: 'Old Artist',
              candidate: 'Matched Artist',
              changed: true,
            ),
            ScrapeFieldDifference(
              field: ScrapeField.genre,
              current: 'Rock',
              candidate: 'Alternative',
              changed: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<ScrapeApplyResult> apply({
    required String trackId,
    required String candidateId,
    required String provider,
    required List<ScrapeField> fields,
  }) async {
    appliedFields = fields;
    return ScrapeApplyResult(
      track: const Track(id: 'track-1', title: 'Matched Song'),
      provider: provider,
      appliedFields: fields,
      appliedAt: DateTime.utc(2026, 7, 18, 12),
    );
  }
}
