import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/presentation/about_page.dart';
import '../../features/about/presentation/support_author_page.dart';
import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/login_page.dart';
import '../../features/collections/presentation/collections_page.dart';
import '../../features/collections/presentation/playlist_detail_page.dart';
import '../../features/lyrics/presentation/lyrics_page.dart';
import '../../features/management/presentation/management_page.dart';
import '../../features/navigation/presentation/player_navigation_scaffold.dart';
import '../../features/player/presentation/player_bar.dart';
import '../../features/player/presentation/player_page.dart';
import '../../features/settings/presentation/server_settings_page.dart';
import '../../features/tracks/domain/track.dart';
import '../../features/tracks/presentation/library_group_pages.dart';
import '../../features/tracks/presentation/track_details_page.dart';
import '../../features/tracks/presentation/tracks_page.dart';
import '../widgets/root_back_exit_guard.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _AuthRouterRefresh();
  ref.listen<AsyncValue<AuthState>>(authControllerProvider, (previous, next) {
    refresh.refresh();
  });

  final router = GoRouter(
    initialLocation: '/auth/loading',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final onAuthRoute = state.matchedLocation.startsWith('/auth');
      if (auth.isLoading) {
        return state.matchedLocation == '/auth/loading'
            ? null
            : '/auth/loading';
      }
      final authenticated = auth.valueOrNull?.isAuthenticated == true;
      if (!authenticated) {
        return state.matchedLocation == '/auth/login' ? null : '/auth/login';
      }
      if (onAuthRoute) {
        return '/tracks';
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/auth/loading',
        builder: (context, state) => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      GoRoute(
        path: '/auth/login',
        builder: (context, state) => const LoginPage(),
      ),
      ShellRoute(
        builder: (context, state, child) {
          final destination = _primaryDestinationFor(state.uri.path);
          return RootBackExitGuard(
            isRootUri: destination != null,
            child: destination == null
                ? Scaffold(
                    body: child,
                    bottomNavigationBar: const PlayerBar(),
                  )
                : PlayerNavigationScaffold(
                    destination: destination,
                    child: child,
                  ),
          );
        },
        routes: [
          GoRoute(
            path: '/',
            redirect: (context, state) => '/tracks',
          ),
          GoRoute(
            path: '/tracks',
            builder: (context, state) => TracksPage(
              initialSearchQuery: state.uri.queryParameters['q'],
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const ServerSettingsPage(),
          ),
          GoRoute(
            path: '/about',
            builder: (context, state) => const AboutPage(),
          ),
          GoRoute(
            path: '/support',
            builder: (context, state) => const SupportAuthorPage(),
          ),
          GoRoute(
            path: '/management',
            builder: (context, state) => const ManagementPage(),
          ),
          GoRoute(
            path: '/collections',
            builder: (context, state) => const CollectionsPage(),
            routes: [
              GoRoute(
                path: ':playlistId',
                builder: (context, state) => PlaylistDetailPage(
                  playlistId: state.pathParameters['playlistId']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/albums',
            builder: (context, state) => const AlbumsPage(),
            routes: [
              GoRoute(
                path: ':albumName',
                builder: (context, state) => AlbumDetailPage(
                  albumName: state.pathParameters['albumName']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/artists',
            builder: (context, state) => const ArtistsPage(),
            routes: [
              GoRoute(
                path: ':artistName',
                builder: (context, state) => ArtistDetailPage(
                  artistName: state.pathParameters['artistName']!,
                ),
              ),
            ],
          ),
          GoRoute(
            path: '/player',
            builder: (context, state) => const PlayerPage(),
            routes: [
              GoRoute(
                path: 'lyrics/:trackId',
                builder: (context, state) {
                  return LyricsPage(
                    trackId: state.pathParameters['trackId']!,
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/library-lyrics/:trackId',
            builder: (context, state) {
              return LyricsPage(
                trackId: state.pathParameters['trackId']!,
              );
            },
          ),
          GoRoute(
            path: '/tracks/:trackId/details',
            builder: (context, state) {
              final extra = state.extra;
              return TrackDetailsPage(
                trackId: state.pathParameters['trackId']!,
                track: extra is Track ? extra : null,
              );
            },
          ),
          GoRoute(
            path: '/tracks/:trackId/lyrics',
            redirect: (context, state) {
              final trackId = Uri.encodeComponent(
                state.pathParameters['trackId']!,
              );
              return '/player/lyrics/$trackId';
            },
          ),
        ],
      ),
    ],
  );
  ref.onDispose(() {
    refresh.dispose();
    router.dispose();
  });
  return router;
});

PlayerNavigationDestination? _primaryDestinationFor(String path) {
  return switch (path) {
    '/tracks' => PlayerNavigationDestination.tracks,
    _ => null,
  };
}

class _AuthRouterRefresh extends ChangeNotifier {
  void refresh() {
    notifyListeners();
  }
}
