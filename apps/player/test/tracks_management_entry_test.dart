import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/tracks/data/tracks_api.dart';
import 'package:player/features/tracks/domain/track.dart';
import 'package:player/features/tracks/domain/track_list.dart';
import 'package:player/features/navigation/presentation/player_navigation_scaffold.dart';
import 'package:player/features/tracks/presentation/tracks_page.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  testWidgets('shows management and per-track scrape entries', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tracksProvider.overrideWith((ref) async {
            return const TrackList(
              tracks: [
                Track(
                  id: 'track-1',
                  title: 'Song',
                  genres: ['Rock'],
                ),
              ],
              total: 1,
            );
          }),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlayerNavigationScaffold(
            destination: PlayerNavigationDestination.tracks,
            playerBar: SizedBox.shrink(),
            child: TracksPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Manage music library'), findsOneWidget);
    expect(find.byTooltip('Download management'), findsOneWidget);
    expect(find.byTooltip('Match metadata'), findsNothing);
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    expect(find.text('Match metadata'), findsOneWidget);
    expect(find.textContaining('Rock'), findsOneWidget);
  });
}
