import 'package:flutter/foundation.dart';

@immutable
class Lyrics {
  const Lyrics({
    required this.trackId,
    required this.path,
    required this.encoding,
    required this.content,
  });

  final String trackId;
  final String? path;
  final String? encoding;
  final String content;

  String get text => content;

  ParsedLyrics get parsed => ParsedLyrics.parse(content);

  factory Lyrics.fromJson(String trackId, Object? json) {
    final map = json is Map<String, dynamic> ? json : const <String, dynamic>{};
    final responseTrackId = map['track_id']?.toString() ?? trackId;
    final content = switch (json) {
      {'content': final String content} => content,
      _ => '',
    };

    return Lyrics(
      trackId: responseTrackId,
      path: map['path'] as String?,
      encoding: map['encoding'] as String?,
      content: content,
    );
  }
}

@immutable
class LyricLine {
  const LyricLine({
    required this.text,
    this.timestamp,
  });

  final String text;
  final Duration? timestamp;
}

@immutable
class ParsedLyrics {
  const ParsedLyrics._(this.lines);

  factory ParsedLyrics.parse(String content) {
    final offset = _parseOffset(content);
    final entries = <_LyricEntry>[];
    var order = 0;

    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final timestamps = _timestampPattern
          .allMatches(rawLine)
          .map((match) => _timestampFromMatch(match, offset))
          .toList(growable: false);
      final text = rawLine
          .replaceAll(_timestampPattern, '')
          .replaceFirst(_metadataPattern, '')
          .trim();

      if (text.isEmpty) {
        continue;
      }

      if (timestamps.isEmpty) {
        entries.add(_LyricEntry(LyricLine(text: text), order++));
        continue;
      }

      for (final timestamp in timestamps) {
        entries.add(
          _LyricEntry(
            LyricLine(text: text, timestamp: timestamp),
            order++,
          ),
        );
      }
    }

    entries.sort((first, second) {
      final firstTimestamp = first.line.timestamp;
      final secondTimestamp = second.line.timestamp;
      if (firstTimestamp == null && secondTimestamp == null) {
        return first.order.compareTo(second.order);
      }
      if (firstTimestamp == null) {
        return 1;
      }
      if (secondTimestamp == null) {
        return -1;
      }

      final timestampComparison = firstTimestamp.compareTo(secondTimestamp);
      return timestampComparison != 0
          ? timestampComparison
          : first.order.compareTo(second.order);
    });

    return ParsedLyrics._(
      List.unmodifiable(entries.map((entry) => entry.line)),
    );
  }

  final List<LyricLine> lines;

  bool get hasTimestamps => lines.any((line) => line.timestamp != null);

  String get displayText => lines.map((line) => line.text).join('\n');

  int? activeLineIndexAt(Duration position) {
    int? activeLineIndex;

    for (var index = 0; index < lines.length; index++) {
      final timestamp = lines[index].timestamp;
      if (timestamp == null) {
        continue;
      }

      activeLineIndex ??= index;
      if (timestamp.compareTo(position) > 0) {
        break;
      }
      activeLineIndex = index;
    }

    if (activeLineIndex == null) {
      return null;
    }

    var firstActiveLineIndex = activeLineIndex;
    final activeTimestamp = lines[firstActiveLineIndex].timestamp;
    while (firstActiveLineIndex > 0 &&
        lines[firstActiveLineIndex - 1].timestamp == activeTimestamp) {
      firstActiveLineIndex--;
    }

    return firstActiveLineIndex;
  }

  String textAt(Duration position) {
    final timedLines =
        lines.where((line) => line.timestamp != null).toList(growable: false);
    if (timedLines.isEmpty) {
      return displayText;
    }

    var selectedIndex = 0;
    for (var index = 1; index < timedLines.length; index++) {
      if (timedLines[index].timestamp!.compareTo(position) > 0) {
        break;
      }
      selectedIndex = index;
    }

    final timestamp = timedLines[selectedIndex].timestamp!;
    var firstIndex = selectedIndex;
    while (
        firstIndex > 0 && timedLines[firstIndex - 1].timestamp == timestamp) {
      firstIndex--;
    }

    var lastIndex = selectedIndex;
    while (lastIndex + 1 < timedLines.length &&
        timedLines[lastIndex + 1].timestamp == timestamp) {
      lastIndex++;
    }

    return timedLines
        .sublist(firstIndex, lastIndex + 1)
        .map((line) => line.text)
        .join('\n');
  }
}

class _LyricEntry {
  const _LyricEntry(this.line, this.order);

  final LyricLine line;
  final int order;
}

final RegExp _timestampPattern = RegExp(
  r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
);
final RegExp _metadataPattern = RegExp(
  r'^\s*\[(?:al|ar|by|offset|re|ti|ve):[^\]]*\]\s*',
  caseSensitive: false,
);
final RegExp _offsetPattern = RegExp(
  r'^\s*\[offset:([+-]?\d+)\]',
  caseSensitive: false,
  multiLine: true,
);

Duration _timestampFromMatch(RegExpMatch match, int offsetMilliseconds) {
  final minutes = int.parse(match.group(1)!);
  final seconds = int.parse(match.group(2)!);
  final fraction = match.group(3);
  final normalizedFraction = fraction?.substring(
    0,
    fraction.length > 3 ? 3 : fraction.length,
  );
  final milliseconds = normalizedFraction == null
      ? 0
      : int.parse(normalizedFraction) *
          _fractionMultiplier(normalizedFraction.length);
  final totalMilliseconds =
      minutes * Duration.millisecondsPerMinute + seconds * 1000 + milliseconds;

  final adjustedMilliseconds = totalMilliseconds + offsetMilliseconds;
  return Duration(
    milliseconds: adjustedMilliseconds < 0 ? 0 : adjustedMilliseconds,
  );
}

int _fractionMultiplier(int length) {
  return switch (length) {
    1 => 100,
    2 => 10,
    _ => 1,
  };
}

int _parseOffset(String content) {
  final value = _offsetPattern.firstMatch(content)?.group(1);
  return value == null ? 0 : int.tryParse(value) ?? 0;
}
