import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../player/application/player_controller.dart';
import '../../preferences/player_preferences.dart';
import '../application/lyrics_offset_controller.dart';
import '../domain/lyrics.dart';
import '../domain/lyrics_offset.dart';

class TimedLyricsList extends ConsumerStatefulWidget {
  const TimedLyricsList({
    required this.trackId,
    required this.lyrics,
    super.key,
  });

  final String trackId;
  final ParsedLyrics lyrics;

  @override
  ConsumerState<TimedLyricsList> createState() => _TimedLyricsListState();
}

class _TimedLyricsListState extends ConsumerState<TimedLyricsList> {
  static const _maximumCenteringSearchSteps = 16;

  final ScrollController _scrollController = ScrollController();
  late List<GlobalKey> _lineKeys;
  late int? _activeLineIndex;
  int? _lastCenteredLineIndex;
  int? _scheduledCenteringLineIndex;
  int? _centeringSearchLineIndex;
  var _centeringSearchSteps = 0;
  var _lowerSearchOffset = 0.0;
  var _upperSearchOffset = 0.0;
  var _hasUpperSearchBound = false;

  @override
  void initState() {
    super.initState();
    _lineKeys = _createLineKeys(widget.lyrics.lines.length);
    _activeLineIndex = _activeLineIndexForCurrentPosition();
    _scheduleActiveLineCentering(animate: false);
  }

  @override
  void didUpdateWidget(covariant TimedLyricsList oldWidget) {
    super.didUpdateWidget(oldWidget);

    final linesChanged =
        !_hasSameLines(oldWidget.lyrics.lines, widget.lyrics.lines);
    final trackChanged = oldWidget.trackId != widget.trackId;
    if (linesChanged) {
      _lineKeys = _createLineKeys(widget.lyrics.lines.length);
    }
    if (linesChanged || trackChanged) {
      _lastCenteredLineIndex = null;
      _scheduledCenteringLineIndex = null;
      _resetCenteringSearch();
    }

    final activeLineIndex = _activeLineIndexForCurrentPosition();
    if (linesChanged || _activeLineIndex != activeLineIndex) {
      _activeLineIndex = activeLineIndex;
      _resetCenteringSearch();
      _scheduleActiveLineCentering(animate: !linesChanged);
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(lyricsOffsetProvider(widget.trackId));
    ref.listen<Duration>(
      playerControllerProvider.select((state) => state.position),
      (_, position) {
        final activeLineIndex = _activeLineIndexAt(position);
        if (activeLineIndex == _activeLineIndex) {
          return;
        }

        setState(() {
          _activeLineIndex = activeLineIndex;
          _resetCenteringSearch();
        });
        _scheduleActiveLineCentering(animate: true);
      },
    );

    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final lyricsFontSize = ref.watch(inAppLyricsFontSizeProvider);
    final verticalPadding = MediaQuery.sizeOf(context).height * .35;
    final activeLineIndex = _activeLineIndexForCurrentPosition();
    if (_activeLineIndex != activeLineIndex) {
      _activeLineIndex = activeLineIndex;
      _resetCenteringSearch();
      _scheduleActiveLineCentering(animate: true);
    }

    return ListView.builder(
      controller: _scrollController,
      padding: EdgeInsets.symmetric(
        horizontal: 24,
        vertical: verticalPadding,
      ),
      itemCount: widget.lyrics.lines.length,
      itemBuilder: (context, index) {
        final line = widget.lyrics.lines[index];
        final isActive = _activeLineIndex == index;
        final hasTimestamp = line.timestamp != null;
        final style =
            (isActive ? textTheme.titleLarge : textTheme.titleMedium)?.copyWith(
          color: isActive ? colorScheme.primary : colorScheme.onSurfaceVariant,
          fontSize: isActive ? lyricsFontSize * 1.12 : lyricsFontSize,
          fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
          height: 1.4,
        );

        return Semantics(
          button: hasTimestamp,
          selected: isActive,
          child: Padding(
            key: _lineKeys[index],
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: hasTimestamp
                    ? () {
                        ref.read(playerControllerProvider.notifier).seek(
                              playbackPositionForLyricsTimestamp(
                                line.timestamp!,
                                _lyricsOffset(),
                              ),
                            );
                      }
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    style: style ?? const TextStyle(),
                    child: Text(
                      line.text,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _scheduleActiveLineCentering({required bool animate}) {
    final activeLineIndex = _activeLineIndex;
    if (activeLineIndex == null ||
        activeLineIndex < 0 ||
        activeLineIndex >= _lineKeys.length ||
        _lastCenteredLineIndex == activeLineIndex ||
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
      if (_activeLineIndex != activeLineIndex) {
        return;
      }

      final lineContext = _lineKeys[activeLineIndex].currentContext;
      if (lineContext == null) {
        if (_advanceCenteringSearch(activeLineIndex)) {
          _scheduleActiveLineCentering(animate: animate);
        }
        return;
      }

      _resetCenteringSearch();
      final lineRenderObject = lineContext.findRenderObject();
      if (lineRenderObject == null) {
        return;
      }

      _lastCenteredLineIndex = activeLineIndex;
      _scrollController.position.ensureVisible(
        lineRenderObject,
        alignment: .5,
        duration: animate ? const Duration(milliseconds: 240) : Duration.zero,
        curve: Curves.easeOut,
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
    for (var index = 0; index < _lineKeys.length; index++) {
      if (_lineKeys[index].currentContext == null) {
        continue;
      }
      first ??= index;
      last = index;
    }
    return first == null || last == null ? null : (first, last);
  }

  double _min(double first, double second) => first < second ? first : second;

  double _max(double first, double second) => first > second ? first : second;

  List<GlobalKey> _createLineKeys(int length) {
    return List<GlobalKey>.generate(length, (_) => GlobalKey());
  }

  int? _activeLineIndexForCurrentPosition() {
    final position = ref.read(playerControllerProvider).position;
    return _activeLineIndexAt(position);
  }

  int? _activeLineIndexAt(Duration position) {
    return widget.lyrics.activeLineIndexAt(
      lyricsTimelinePosition(position, _lyricsOffset()),
    );
  }

  Duration _lyricsOffset() {
    return ref.read(lyricsOffsetProvider(widget.trackId)).valueOrNull ??
        Duration.zero;
  }

  bool _hasSameLines(List<LyricLine> first, List<LyricLine> second) {
    if (first.length != second.length) {
      return false;
    }

    for (var index = 0; index < first.length; index++) {
      if (first[index].text != second[index].text ||
          first[index].timestamp != second[index].timestamp) {
        return false;
      }
    }

    return true;
  }
}
