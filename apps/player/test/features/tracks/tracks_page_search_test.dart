import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/collections/application/collections_controller.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/features/tracks/presentation/tracks_page.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('filters the library from the route search query',
      (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tracksProvider.overrideWith(
            (ref) async => const TrackList(
              total: 2,
              tracks: [
                Track(id: 'midnight', title: 'Midnight City', artist: 'M83'),
                Track(id: 'other', title: 'Other Song', artist: 'Artist'),
              ],
            ),
          ),
          favoriteTrackIdsProvider.overrideWithValue(const <String>{}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: TracksPage(initialSearchQuery: 'midnight'),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Midnight City'), findsOneWidget);
    expect(find.text('Other Song'), findsNothing);
  });
}
