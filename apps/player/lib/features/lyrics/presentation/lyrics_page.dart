import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../features/preferences/player_preferences.dart';
import '../../../l10n/l10n.dart';
import '../application/lyrics_offset_controller.dart';
import '../data/lyrics_api.dart';
import '../domain/lyrics.dart';
import '../domain/lyrics_offset.dart';
import 'timed_lyrics_list.dart';

class LyricsPage extends ConsumerWidget {
  const LyricsPage({
    required this.trackId,
    super.key,
  });

  final String trackId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final lyrics = ref.watch(lyricsProvider(trackId));
    final textAlign = ref.watch(inAppLyricsTextAlignProvider);
    final lyricsOffset = ref.watch(lyricsOffsetProvider(trackId));

    return Scaffold(
      appBar: AppBar(title: Text(l10n.lyricsTitle)),
      body: Column(
        children: [
          _LyricsOffsetControls(
            offset: lyricsOffset.valueOrNull ?? Duration.zero,
            enabled: lyricsOffset.hasValue,
            onChanged: (offset) {
              unawaited(
                ref
                    .read(lyricsOffsetProvider(trackId).notifier)
                    .setOffset(offset),
              );
            },
          ),
          const Divider(height: 1),
          Expanded(
            child: AsyncValueView<Lyrics>(
              value: lyrics,
              data: (value) {
                final parsed = value.parsed;
                final displayText = parsed.displayText;
                if (displayText.isEmpty) {
                  return EmptyState(
                    title: l10n.noLyricsTitle,
                    message: l10n.noLyricsMessage,
                    icon: Icons.lyrics_outlined,
                  );
                }

                if (!parsed.hasTimestamps) {
                  return _UntimedLyricsView(
                    text: displayText,
                    textAlign: textAlign,
                  );
                }

                return TimedLyricsList(
                  trackId: trackId,
                  lyrics: parsed,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LyricsOffsetControls extends StatelessWidget {
  const _LyricsOffsetControls({
    required this.offset,
    required this.enabled,
    required this.onChanged,
  });

  final Duration offset;
  final bool enabled;
  final ValueChanged<Duration> onChanged;

  @override
  Widget build(BuildContext context) {
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    final title = isChinese ? '歌词偏移' : 'Lyrics timing';
    final hint =
        isChinese ? '正数表示歌词提前显示。' : 'Positive values show lyrics earlier.';
    final decreaseTooltip =
        isChinese ? '歌词延后 0.5 秒' : 'Delay lyrics by 0.5 seconds';
    final increaseTooltip =
        isChinese ? '歌词提前 0.5 秒' : 'Show lyrics 0.5 seconds earlier';

    return Semantics(
      label: '$title. $hint',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 2),
            Text(hint, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  key: const ValueKey('decrease-lyrics-offset'),
                  tooltip: decreaseTooltip,
                  onPressed: enabled
                      ? () => onChanged(offset - lyricsOffsetStep)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    _offsetLabel(offset, isChinese: isChinese),
                    key: const ValueKey('lyrics-offset-value'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                IconButton(
                  key: const ValueKey('increase-lyrics-offset'),
                  tooltip: increaseTooltip,
                  onPressed: enabled
                      ? () => onChanged(offset + lyricsOffsetStep)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _offsetLabel(Duration value, {required bool isChinese}) {
    final seconds = value.inMilliseconds.abs() / Duration.millisecondsPerSecond;
    final formatted = seconds.toStringAsFixed(1);
    if (value == Duration.zero) {
      return isChinese ? '0.0 秒 · 同步' : '0.0 s · in sync';
    }
    if (value.isNegative) {
      return isChinese
          ? '-$formatted 秒 · 歌词延后'
          : '-$formatted s · lyrics delayed';
    }
    return isChinese
        ? '+$formatted 秒 · 歌词提前'
        : '+$formatted s · lyrics earlier';
  }
}

class _UntimedLyricsView extends StatelessWidget {
  const _UntimedLyricsView({
    required this.text,
    required this.textAlign,
  });

  final String text;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    final message = isChinese
        ? '这首歌词没有时间轴，暂不支持随播放进度滚动或点击跳转。'
        : 'These lyrics have no time markers, so playback sync and seeking are unavailable.';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(
            Icons.format_align_left,
            size: 48,
            color: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 32),
          SelectableText(
            text,
            textAlign: textAlign,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  height: 1.7,
                ),
          ),
        ],
      ),
    );
  }
}
