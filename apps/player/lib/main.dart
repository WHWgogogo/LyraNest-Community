import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/network/api_client.dart';
import 'features/lyrics/data/lyrics_api.dart';
import 'features/player/application/lyrics_not_found_fallback.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  runApp(
    ProviderScope(
      overrides: [
        lyricsApiProvider.overrideWith(
          (ref) => LyricsNotFoundFallbackApi(ref.watch(dioProvider)),
        ),
      ],
      child: const PlayerApp(),
    ),
  );
}
