import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/routing/app_router.dart';
import 'features/auth/application/auth_controller.dart';
import 'features/lyrics/data/lyrics_api.dart';
import 'features/system_media/presentation/system_media_host.dart';
import 'l10n/l10n.dart';

class PlayerApp extends ConsumerWidget {
  const PlayerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<bool>(
      authControllerProvider.select(
        (state) => state.valueOrNull?.isOfflineAuthenticated ?? false,
      ),
      (wasOffline, isOffline) {
        if (wasOffline == true && !isOffline) {
          ref.invalidate(lyricsProvider);
        }
      },
    );
    final router = ref.watch(routerProvider);
    final authenticated =
        ref.watch(authControllerProvider).valueOrNull?.isAuthenticated == true;

    final app = MaterialApp.router(
      onGenerateTitle: (context) => context.l10n.appTitle,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF9A7DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF090B13),
        splashFactory: InkSparkle.splashFactory,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: const Color(0xFF171A29),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(26),
          ),
        ),
        sliderTheme: const SliderThemeData(
          trackHeight: 3,
          thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
          overlayShape: RoundSliderOverlayShape(overlayRadius: 16),
        ),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(
            foregroundColor: Colors.white.withValues(alpha: .88),
          ),
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.dark,
      routerConfig: router,
    );
    return authenticated ? SystemMediaHost(child: app) : app;
  }
}
