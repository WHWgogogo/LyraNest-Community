import 'package:flutter/widgets.dart';

import '../../desktop_lyrics/domain/desktop_lyrics_overlay.dart';
import '../../desktop_lyrics/domain/overlay_status.dart';

enum LyricsAlignment {
  left,
  center,
  right,
  split;

  bool get supportsInAppLyrics => this != LyricsAlignment.split;

  TextAlign get textAlign {
    return switch (this) {
      LyricsAlignment.left => TextAlign.left,
      LyricsAlignment.center => TextAlign.center,
      LyricsAlignment.right => TextAlign.right,
      LyricsAlignment.split => TextAlign.left,
    };
  }

  LyricsTextAlignment get desktopLyricsTextAlignment {
    return switch (this) {
      LyricsAlignment.left => LyricsTextAlignment.left,
      LyricsAlignment.center => LyricsTextAlignment.center,
      LyricsAlignment.right => LyricsTextAlignment.right,
      LyricsAlignment.split => LyricsTextAlignment.split,
    };
  }

  static LyricsAlignment? fromName(String? name) {
    for (final alignment in values) {
      if (alignment.name == name) {
        return alignment;
      }
    }
    return null;
  }

  static LyricsAlignment fromTextAlign(TextAlign alignment) {
    return switch (alignment) {
      TextAlign.left || TextAlign.start => LyricsAlignment.left,
      TextAlign.right || TextAlign.end => LyricsAlignment.right,
      _ => LyricsAlignment.center,
    };
  }
}

enum DesktopLyricsLineMode {
  singleLine,
  doubleLine;

  static DesktopLyricsLineMode? fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) {
        return mode;
      }
    }
    return null;
  }
}

@immutable
class PlayerPreferences {
  const PlayerPreferences({
    this.desktopLyricsBackgroundOpacity = defaultDesktopLyricsBackgroundOpacity,
    this.lyricsColorArgb = defaultLyricsColorArgb,
    this.inAppLyricsFontSize = defaultInAppLyricsFontSize,
    this.desktopLyricsFontSize = defaultDesktopLyricsFontSize,
    this.desktopLyricsAlignment = defaultDesktopLyricsAlignment,
    this.inAppLyricsAlignment = defaultInAppLyricsAlignment,
    this.desktopLyricsLineMode = defaultDesktopLyricsLineMode,
    this.resetPositionOnOpen = defaultResetPositionOnOpen,
  })  : assert(inAppLyricsAlignment != LyricsAlignment.split),
        assert(
          desktopLyricsBackgroundOpacity >= 0 &&
              desktopLyricsBackgroundOpacity <= 1,
        ),
        assert(lyricsColorArgb >= 0 && lyricsColorArgb <= 0xffffffff),
        assert(
          inAppLyricsFontSize >= minInAppLyricsFontSize &&
              inAppLyricsFontSize <= maxInAppLyricsFontSize,
        ),
        assert(
          desktopLyricsFontSize >= minDesktopLyricsFontSize &&
              desktopLyricsFontSize <= maxDesktopLyricsFontSize,
        );

  static const double defaultDesktopLyricsBackgroundOpacity = 0.35;
  static const int defaultLyricsColorArgb = 0xffffffff;
  static const double minInAppLyricsFontSize = 14;
  static const double maxInAppLyricsFontSize = 36;
  static const double inAppLyricsFontSizeStep = 2;
  static const double defaultInAppLyricsFontSize = 22;
  static const double minDesktopLyricsFontSize = 14;
  static const double maxDesktopLyricsFontSize = 36;
  static const double desktopLyricsFontSizeStep = 2;
  static const double defaultDesktopLyricsFontSize = 22;
  static const LyricsAlignment defaultDesktopLyricsAlignment =
      LyricsAlignment.center;
  static const LyricsAlignment defaultInAppLyricsAlignment =
      LyricsAlignment.center;
  static const DesktopLyricsLineMode defaultDesktopLyricsLineMode =
      DesktopLyricsLineMode.singleLine;
  static const bool defaultResetPositionOnOpen = false;

  final double desktopLyricsBackgroundOpacity;
  final int lyricsColorArgb;
  final double inAppLyricsFontSize;
  final double desktopLyricsFontSize;
  final LyricsAlignment desktopLyricsAlignment;
  final LyricsAlignment inAppLyricsAlignment;
  final DesktopLyricsLineMode desktopLyricsLineMode;
  final bool resetPositionOnOpen;

  double get backgroundOpacity => desktopLyricsBackgroundOpacity;
  int get desktopLyricsColorArgb => lyricsColorArgb;
  bool get resetDesktopLyricsPositionOnOpen => resetPositionOnOpen;
  TextAlign get desktopLyricsTextAlign => desktopLyricsAlignment.textAlign;
  TextAlign get inAppLyricsTextAlign => inAppLyricsAlignment.textAlign;

  static bool isValidInAppLyricsFontSize(double value) {
    return _isValidLyricsFontSize(
      value,
      min: minInAppLyricsFontSize,
      max: maxInAppLyricsFontSize,
      step: inAppLyricsFontSizeStep,
    );
  }

  static bool isValidDesktopLyricsFontSize(double value) {
    return _isValidLyricsFontSize(
      value,
      min: minDesktopLyricsFontSize,
      max: maxDesktopLyricsFontSize,
      step: desktopLyricsFontSizeStep,
    );
  }

  static bool _isValidLyricsFontSize(
    double value, {
    required double min,
    required double max,
    required double step,
  }) {
    if (!value.isFinite || value < min || value > max) {
      return false;
    }
    final stepCount = (value - min) / step;
    return (stepCount - stepCount.round()).abs() < .000001;
  }

  PlayerPreferences copyWith({
    double? desktopLyricsBackgroundOpacity,
    int? lyricsColorArgb,
    double? inAppLyricsFontSize,
    double? desktopLyricsFontSize,
    LyricsAlignment? desktopLyricsAlignment,
    LyricsAlignment? inAppLyricsAlignment,
    DesktopLyricsLineMode? desktopLyricsLineMode,
    bool? resetPositionOnOpen,
  }) {
    return PlayerPreferences(
      desktopLyricsBackgroundOpacity:
          desktopLyricsBackgroundOpacity ?? this.desktopLyricsBackgroundOpacity,
      lyricsColorArgb: lyricsColorArgb ?? this.lyricsColorArgb,
      inAppLyricsFontSize: inAppLyricsFontSize ?? this.inAppLyricsFontSize,
      desktopLyricsFontSize:
          desktopLyricsFontSize ?? this.desktopLyricsFontSize,
      desktopLyricsAlignment:
          desktopLyricsAlignment ?? this.desktopLyricsAlignment,
      inAppLyricsAlignment: inAppLyricsAlignment ?? this.inAppLyricsAlignment,
      desktopLyricsLineMode:
          desktopLyricsLineMode ?? this.desktopLyricsLineMode,
      resetPositionOnOpen: resetPositionOnOpen ?? this.resetPositionOnOpen,
    );
  }

  Future<LyricsOverlayStatus> configureDesktopLyrics(
    DesktopLyricsOverlay overlay,
  ) {
    return overlay.configure(
      backgroundOpacity: desktopLyricsBackgroundOpacity,
      textColor: lyricsColorArgb,
      fontSize: desktopLyricsFontSize,
      textAlignment: desktopLyricsAlignment.desktopLyricsTextAlignment,
      resetPosition: resetPositionOnOpen,
    );
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is PlayerPreferences &&
            other.desktopLyricsBackgroundOpacity ==
                desktopLyricsBackgroundOpacity &&
            other.lyricsColorArgb == lyricsColorArgb &&
            other.inAppLyricsFontSize == inAppLyricsFontSize &&
            other.desktopLyricsFontSize == desktopLyricsFontSize &&
            other.desktopLyricsAlignment == desktopLyricsAlignment &&
            other.inAppLyricsAlignment == inAppLyricsAlignment &&
            other.desktopLyricsLineMode == desktopLyricsLineMode &&
            other.resetPositionOnOpen == resetPositionOnOpen;
  }

  @override
  int get hashCode => Object.hash(
        desktopLyricsBackgroundOpacity,
        lyricsColorArgb,
        inAppLyricsFontSize,
        desktopLyricsFontSize,
        desktopLyricsAlignment,
        inAppLyricsAlignment,
        desktopLyricsLineMode,
        resetPositionOnOpen,
      );
}
