import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../lyrics/application/lyrics_offset_controller.dart';
import '../../lyrics/data/lyrics_api.dart';
import '../../lyrics/domain/lyrics.dart';
import '../../lyrics/domain/lyrics_offset.dart';
import '../../preferences/player_preferences.dart';
import '../application/player_controller.dart';

class NowPlayingLyrics extends ConsumerWidget {
  const NowPlayingLyrics({
    required this.trackId,
    required this.textAlign,
    required this.activeColor,
    required this.inactiveColor,
    this.activeStyle,
    this.inactiveStyle,
    this.expanded = false,
    super.key,
  });

  final String trackId;
  final TextAlign textAlign;
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyrics = ref.watch(lyricsProvider(trackId));
    final lyricsOffset =
        ref.watch(lyricsOffsetProvider(trackId)).valueOrNull ?? Duration.zero;
    final lyricsFontSize = ref.watch(inAppLyricsFontSizeProvider);
    final placeholderStyle = activeStyle?.copyWith(color: activeColor) ??
        TextStyle(
          color: activeColor,
          fontSize: lyricsFontSize + 4,
          fontWeight: FontWeight.w700,
          height: 1.35,
        );

    return lyrics.when(
      data: (value) => _LyricsBody(
        key: ValueKey((trackId, value.content)),
        lyrics: value.parsed,
        textAlign: textAlign,
        activeColor: activeColor,
        inactiveColor: inactiveColor,
        activeStyle: activeStyle,
        inactiveStyle: inactiveStyle,
        expanded: expanded,
        lyricsOffset: lyricsOffset,
      ),
      loading: () => _LyricsPlaceholder(
        textAlign: textAlign,
        style: placeholderStyle,
      ),
      error: (error, stackTrace) => _LyricsPlaceholder(
        textAlign: textAlign,
        style: placeholderStyle,
      ),
    );
  }
}

class _LyricsBody extends ConsumerStatefulWidget {
  const _LyricsBody({
    required this.lyrics,
    required this.textAlign,
    required this.activeColor,
    required this.inactiveColor,
    required this.activeStyle,
    required this.inactiveStyle,
    required this.expanded,
    required this.lyricsOffset,
    super.key,
  });

  final ParsedLyrics lyrics;
  final TextAlign textAlign;
  final Color activeColor;
  final Color inactiveColor;
  final TextStyle? activeStyle;
  final TextStyle? inactiveStyle;
  final bool expanded;
  final Duration lyricsOffset;

  @override
  ConsumerState<_LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends ConsumerState<_LyricsBody> {
  static const _maximumCenteringSearchSteps = 16;

  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _lineKeys = <int, GlobalKey>{};
  int? _lastCenteredLineIndex;
  int? _scheduledCenteringLineIndex;
  int? _centeringSearchLineIndex;
  var _centeringSearchSteps = 0;
  var _lowerSearchOffset = 0.0;
  var _upperSearchOffset = 0.0;
  var _hasUpperSearchBound = false;

  @override
  void didUpdateWidget(covariant _LyricsBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.lyrics != widget.lyrics) {
      _lineKeys.clear();
      _lastCenteredLineIndex = null;
      _scheduledCenteringLineIndex = null;
      _resetCenteringSearch();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(
      playerControllerProvider.select((state) => state.position),
    );
    final activeLineIndex = _activeLineIndex(position);
    final lyricsFontSize = ref.watch(inAppLyricsFontSizeProvider);
    final activeStyle = widget.activeStyle?.copyWith(
          color: widget.activeColor,
          fontSize: lyricsFontSize + 4,
        ) ??
        TextStyle(
          color: widget.activeColor,
          fontSize: lyricsFontSize + 4,
          fontWeight: FontWeight.w700,
          height: 1.35,
        );
    final inactiveStyle = widget.inactiveStyle?.copyWith(
          color: widget.inactiveColor,
          fontSize: lyricsFontSize,
        ) ??
        TextStyle(
          color: widget.inactiveColor,
          fontSize: lyricsFontSize,
          height: 1.35,
        );

    if (widget.lyrics.lines.isEmpty) {
      return _LyricsPlaceholder(
        textAlign: widget.textAlign,
        style: activeStyle,
      );
    }

    if (!widget.expanded) {
      return _CompactLyrics(
        lyrics: widget.lyrics,
        activeLineIndex: activeLineIndex,
        textAlign: widget.textAlign,
        activeStyle: activeStyle,
        inactiveStyle: inactiveStyle,
        onSeek: _seekToLine,
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final activeLineHeight = (activeStyle.fontSize ?? lyricsFontSize) *
            (activeStyle.height ?? 1.35);
        _scheduleActiveLineCentering(activeLineIndex);
        final verticalPadding = constraints.maxHeight.isFinite
            ? math
                .max(0.0, (constraints.maxHeight - activeLineHeight) / 2)
                .toDouble()
            : 0.0;

        return Semantics(
          liveRegion: true,
          label: widget.lyrics.lines[activeLineIndex].text,
          child: ListView.builder(
            key: const ValueKey('now-playing-lyrics-list'),
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(vertical: verticalPadding),
            itemCount: widget.lyrics.lines.length,
            itemBuilder: (context, index) {
              final line = widget.lyrics.lines[index];
              final isActive = index == activeLineIndex;
              return KeyedSubtree(
                key: _lineKey(index),
                child: _LyricLineButton(
                  key: ValueKey(('expanded-lyric', index, isActive)),
                  line: line,
                  selected: isActive,
                  textAlign: widget.textAlign,
                  style: isActive ? activeStyle : inactiveStyle,
                  onTap:
                      line.timestamp == null ? null : () => _seekToLine(line),
                ),
              );
            },
          ),
        );
      },
    );
  }

  int _activeLineIndex(Duration position) {
    return widget.lyrics.hasTimestamps
        ? widget.lyrics.activeLineIndexAt(
              lyricsTimelinePosition(position, widget.lyricsOffset),
            ) ??
            0
        : 0;
  }

  void _seekToLine(LyricLine line) {
    final timestamp = line.timestamp;
    if (timestamp == null) {
      return;
    }
    unawaited(
      ref.read(playerControllerProvider.notifier).seek(
            playbackPositionForLyricsTimestamp(
              timestamp,
              widget.lyricsOffset,
            ),
          ),
    );
  }

  void _scheduleActiveLineCentering(int activeLineIndex) {
    if (_lastCenteredLineIndex == activeLineIndex ||
        _scheduledCenteringLineIndex == activeLineIndex) {
      return;
    }

    _prepareCenteringSearch(activeLineIndex);
    _scheduledCenteringLineIndex = activeLineIndex;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _scheduledCenteringLineIndex = null;
      if (!_scrollController.hasClients) {
        _scheduleActiveLineCentering(activeLineIndex);
        return;
      }

      final currentActiveLineIndex = _activeLineIndex(
        ref.read(playerControllerProvider).position,
      );
      if (currentActiveLineIndex != activeLineIndex) {
        return;
      }

      final lineContext = _lineKey(activeLineIndex).currentContext;
      if (lineContext == null) {
        if (_advanceCenteringSearch(activeLineIndex)) {
          _scheduleActiveLineCentering(activeLineIndex);
        }
        return;
      }

      _resetCenteringSearch();
      final lineRenderObject = lineContext.findRenderObject();
      if (lineRenderObject == null) {
        return;
      }

      _lastCenteredLineIndex = activeLineIndex;
      unawaited(
        _scrollController.position.ensureVisible(
          lineRenderObject,
          alignment: .5,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _prepareCenteringSearch(int lineIndex) {
    if (_centeringSearchLineIndex == lineIndex) {
      return;
    }

    _centeringSearchLineIndex = lineIndex;
    _centeringSearchSteps = 0;
    _lowerSearchOffset = 0;
    _upperSearchOffset = 0;
    _hasUpperSearchBound = false;
  }

  void _resetCenteringSearch() {
    _centeringSearchLineIndex = null;
    _centeringSearchSteps = 0;
    _lowerSearchOffset = 0;
    _upperSearchOffset = 0;
    _hasUpperSearchBound = false;
  }

  bool _advanceCenteringSearch(int lineIndex) {
    if (!_scrollController.hasClients ||
        _centeringSearchSteps >= _maximumCenteringSearchSteps) {
      return false;
    }

    final position = _scrollController.position;
    final mountedRange = _mountedLineRange();
    if (mountedRange == null) {
      return false;
    }

    final maxScrollExtent = position.maxScrollExtent;
    if (!_hasUpperSearchBound) {
      _upperSearchOffset = maxScrollExtent;
    }
    _lowerSearchOffset =
        _lowerSearchOffset.clamp(0.0, maxScrollExtent).toDouble();
    _upperSearchOffset = _upperSearchOffset
        .clamp(_lowerSearchOffset, maxScrollExtent)
        .toDouble();

    if (lineIndex > mountedRange.$2) {
      _lowerSearchOffset = _max(_lowerSearchOffset, position.pixels);
    } else if (lineIndex < mountedRange.$1) {
      _upperSearchOffset = _min(_upperSearchOffset, position.pixels);
      _hasUpperSearchBound = true;
    } else {
      return false;
    }

    var nextOffset = (_lowerSearchOffset + _upperSearchOffset) / 2;
    if ((nextOffset - position.pixels).abs() < 1) {
      if (lineIndex > mountedRange.$2 && position.pixels < maxScrollExtent) {
        nextOffset = maxScrollExtent;
      } else if (lineIndex < mountedRange.$1 && position.pixels > 0) {
        nextOffset = 0;
      } else {
        return false;
      }
    }

    _centeringSearchSteps += 1;
    _scrollController.jumpTo(nextOffset);
    return true;
  }

  (int, int)? _mountedLineRange() {
    int? first;
    int? last;
    for (final entry in _lineKeys.entries) {
      if (entry.value.currentContext == null) {
        continue;
      }
      first = first == null ? entry.key : _minIndex(first, entry.key);
      last = last == null ? entry.key : _maxIndex(last, entry.key);
    }
    return first == null || last == null ? null : (first, last);
  }

  int _minIndex(int first, int second) => first < second ? first : second;

  int _maxIndex(int first, int second) => first > second ? first : second;

  double _min(double first, double second) => first < second ? first : second;

  double _max(double first, double second) => first > second ? first : second;

  GlobalKey _lineKey(int index) {
    return _lineKeys.putIfAbsent(index, GlobalKey.new);
  }
}

class _CompactLyrics extends StatelessWidget {
  const _CompactLyrics({
    required this.lyrics,
    required this.activeLineIndex,
    required this.textAlign,
    required this.activeStyle,
    required this.inactiveStyle,
    required this.onSeek,
  });

  final ParsedLyrics lyrics;
  final int activeLineIndex;
  final TextAlign textAlign;
  final TextStyle activeStyle;
  final TextStyle inactiveStyle;
  final ValueChanged<LyricLine> onSeek;

  @override
  Widget build(BuildContext context) {
    final current = lyrics.lines[activeLineIndex];
    final previewLines = List<LyricLine?>.generate(3, (index) {
      final lineIndex = activeLineIndex + index - 1;
      if (lineIndex < 0) {
        return null;
      }
      return lineIndex < lyrics.lines.length ? lyrics.lines[lineIndex] : null;
    });

    return Semantics(
      liveRegion: true,
      label: current.text,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var index = 0; index < previewLines.length; index++) ...[
            _AnimatedLyricLine(
              key: ValueKey(('compact-lyric', index)),
              line: previewLines[index],
              selected: index == 1,
              textAlign: index == 1 ? TextAlign.center : textAlign,
              style: index == 1 ? activeStyle : inactiveStyle,
              onTap: previewLines[index]?.timestamp == null
                  ? null
                  : () => onSeek(previewLines[index]!),
            ),
            if (index < previewLines.length - 1) const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _AnimatedLyricLine extends StatelessWidget {
  const _AnimatedLyricLine({
    required this.line,
    required this.selected,
    required this.textAlign,
    required this.style,
    required this.onTap,
    super.key,
  });

  final LyricLine? line;
  final bool selected;
  final TextAlign textAlign;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = line?.text ?? '';
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .12),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: _LyricLineButton(
        key: ValueKey((text, selected)),
        line: line,
        selected: selected,
        textAlign: textAlign,
        style: style,
        onTap: onTap,
      ),
    );
  }
}

class _LyricLineButton extends StatelessWidget {
  const _LyricLineButton({
    required this.line,
    required this.selected,
    required this.textAlign,
    required this.style,
    required this.onTap,
    super.key,
  });

  final LyricLine? line;
  final bool selected;
  final TextAlign textAlign;
  final TextStyle style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = line?.text ?? '';
    return Semantics(
      button: onTap != null,
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Align(
            alignment: _alignment(textAlign),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                style: style,
                textAlign: textAlign,
                child: Text(
                  text.isEmpty ? ' ' : text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsPlaceholder extends StatelessWidget {
  const _LyricsPlaceholder({
    required this.textAlign,
    required this.style,
  });

  final TextAlign textAlign;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: _alignment(textAlign),
      child: Text('—', textAlign: textAlign, style: style),
    );
  }
}

Alignment _alignment(TextAlign textAlign) {
  return switch (textAlign) {
    TextAlign.left ||
    TextAlign.start ||
    TextAlign.justify =>
      Alignment.centerLeft,
    TextAlign.right || TextAlign.end => Alignment.centerRight,
    _ => Alignment.center,
  };
}
