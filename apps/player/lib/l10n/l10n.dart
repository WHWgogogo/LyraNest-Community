import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../core/network/api_error.dart';
import '../features/desktop_lyrics/domain/overlay_capability.dart';
import '../features/tracks/domain/track.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

Future<AppLocalizations> loadSystemAppLocalizations() {
  return AppLocalizations.delegate.load(_resolveSystemLocale());
}

Locale _resolveSystemLocale() {
  for (final preferredLocale in ui.PlatformDispatcher.instance.locales) {
    for (final supportedLocale in AppLocalizations.supportedLocales) {
      if (preferredLocale.languageCode == supportedLocale.languageCode) {
        return supportedLocale;
      }
    }
  }

  return AppLocalizations.supportedLocales.first;
}

Future<String> localizedLyricsOverlayCapabilityNotes(
  LyricsOverlayPlatform platform,
) async {
  final localizations = await loadSystemAppLocalizations();
  return switch (platform) {
    LyricsOverlayPlatform.windows =>
      localizations.desktopLyricsWindowsDescription,
    LyricsOverlayPlatform.android =>
      localizations.desktopLyricsAndroidDescription,
    LyricsOverlayPlatform.unsupported =>
      localizations.desktopLyricsUnsupportedDescription,
  };
}

Future<String> localizedLyricsOverlayNotImplementedMessage(
  LyricsOverlayPlatform platform,
) async {
  final localizations = await loadSystemAppLocalizations();
  return switch (platform) {
    LyricsOverlayPlatform.windows =>
      localizations.windowsLyricsOverlayNotImplemented,
    LyricsOverlayPlatform.android =>
      localizations.androidLyricsOverlayNotImplemented,
    LyricsOverlayPlatform.unsupported =>
      localizations.unsupportedLyricsOverlayNotImplemented,
  };
}

extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);
}

extension ApiErrorL10n on ApiError {
  String localizedMessage(AppLocalizations l10n) {
    final displayMessage = message == ApiError.networkRequestFailedMessage
        ? l10n.networkRequestFailed
        : message;

    final code = statusCode;
    if (code == null) {
      return displayMessage;
    }

    return l10n.networkErrorWithStatusCode(displayMessage, code);
  }
}

extension LyricsOverlayCapabilityL10n on LyricsOverlayCapability {
  String localizedNotes(AppLocalizations l10n) {
    return switch (platform) {
      LyricsOverlayPlatform.windows => l10n.desktopLyricsWindowsDescription,
      LyricsOverlayPlatform.android => l10n.desktopLyricsAndroidDescription,
      LyricsOverlayPlatform.unsupported =>
        l10n.desktopLyricsUnsupportedDescription,
    };
  }
}

extension TrackL10n on Track {
  String localizedTitle(AppLocalizations l10n) {
    final trimmedTitle = title.trim();
    if (trimmedTitle.isEmpty || trimmedTitle == Track.untitledTitle) {
      return l10n.untitledTrack;
    }
    return title;
  }

  String localizedArtist(AppLocalizations l10n) {
    final value = artist?.trim();
    if (value == null || value.isEmpty) {
      return l10n.unknownArtist;
    }
    return artist!;
  }
}
