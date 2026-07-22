import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences/player_preferences.dart';

typedef PreferenceUpdate<T> = Future<bool> Function(T value);

class LyricsSettingsSection extends ConsumerStatefulWidget {
  const LyricsSettingsSection({
    required this.backgroundOpacity,
    required this.lyricsColorArgb,
    required this.desktopLyricsAlignment,
    required this.inAppLyricsAlignment,
    required this.desktopLyricsLineMode,
    required this.resetPositionOnOpen,
    required this.onBackgroundOpacityChanged,
    required this.onLyricsColorArgbChanged,
    required this.onDesktopLyricsAlignmentChanged,
    required this.onInAppLyricsAlignmentChanged,
    required this.onDesktopLyricsLineModeChanged,
    required this.onResetPositionOnOpenChanged,
    super.key,
  });

  final double backgroundOpacity;
  final int lyricsColorArgb;
  final LyricsAlignment desktopLyricsAlignment;
  final LyricsAlignment inAppLyricsAlignment;
  final DesktopLyricsLineMode desktopLyricsLineMode;
  final bool resetPositionOnOpen;
  final PreferenceUpdate<double> onBackgroundOpacityChanged;
  final PreferenceUpdate<int> onLyricsColorArgbChanged;
  final PreferenceUpdate<LyricsAlignment> onDesktopLyricsAlignmentChanged;
  final PreferenceUpdate<LyricsAlignment> onInAppLyricsAlignmentChanged;
  final PreferenceUpdate<DesktopLyricsLineMode> onDesktopLyricsLineModeChanged;
  final PreferenceUpdate<bool> onResetPositionOnOpenChanged;

  @override
  ConsumerState<LyricsSettingsSection> createState() =>
      _LyricsSettingsSectionState();
}

class _LyricsSettingsSectionState extends ConsumerState<LyricsSettingsSection> {
  late final TextEditingController _argbController;
  late double _backgroundOpacity;
  late int _lyricsColorArgb;
  String? _argbError;

  @override
  void initState() {
    super.initState();
    _argbController = TextEditingController(
      text: _formatArgb(widget.lyricsColorArgb),
    );
    _backgroundOpacity = widget.backgroundOpacity;
    _lyricsColorArgb = widget.lyricsColorArgb;
  }

  @override
  void didUpdateWidget(covariant LyricsSettingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backgroundOpacity != widget.backgroundOpacity) {
      _backgroundOpacity = widget.backgroundOpacity;
    }
    if (oldWidget.lyricsColorArgb != widget.lyricsColorArgb) {
      _lyricsColorArgb = widget.lyricsColorArgb;
      final formattedArgb = _formatArgb(widget.lyricsColorArgb);
      if (_argbController.text != formattedArgb) {
        _argbController.value = TextEditingValue(
          text: formattedArgb,
          selection: TextSelection.collapsed(offset: formattedArgb.length),
        );
      }
      _argbError = null;
    }
  }

  @override
  void dispose() {
    _argbController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final copy = _LyricsSettingsCopy.of(context);
    final color = Color(_lyricsColorArgb);
    final inAppLyricsFontSize = ref.watch(inAppLyricsFontSizeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              copy.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Text(copy.backgroundOpacity),
            Slider(
              key: const ValueKey('desktop-lyrics-background-opacity'),
              value: _backgroundOpacity.clamp(0.0, 1.0).toDouble(),
              divisions: 20,
              label: '${(_backgroundOpacity * 100).round()}%',
              onChanged: (value) {
                setState(() {
                  _backgroundOpacity = value;
                });
                unawaited(widget.onBackgroundOpacityChanged(value));
              },
            ),
            const SizedBox(height: 8),
            Text(copy.lyricsColor),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _colorPresets)
                  _ColorPresetButton(
                    color: preset,
                    selected: preset.toARGB32() == color.toARGB32(),
                    onPressed: () {
                      _setLyricsColorArgb(preset.toARGB32());
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _argbController,
              autocorrect: false,
              enableSuggestions: false,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: copy.argbLabel,
                hintText: '#FFFFFFFF',
                errorText: _argbError,
                border: const OutlineInputBorder(),
                prefixIcon: Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              onSubmitted: _applyArgb,
            ),
            const SizedBox(height: 24),
            _LyricsFontSizeStepper(
              fontSize: inAppLyricsFontSize,
              label: copy.inAppLyricsFontSize,
              decreaseKey: const ValueKey('decrease-in-app-lyrics-font-size'),
              valueKey: const ValueKey('in-app-lyrics-font-size-value'),
              increaseKey: const ValueKey('increase-in-app-lyrics-font-size'),
              onDecrement:
                  inAppLyricsFontSize > PlayerPreferences.minInAppLyricsFontSize
                      ? () => _setInAppLyricsFontSize(
                            inAppLyricsFontSize -
                                PlayerPreferences.inAppLyricsFontSizeStep,
                          )
                      : null,
              onIncrement:
                  inAppLyricsFontSize < PlayerPreferences.maxInAppLyricsFontSize
                      ? () => _setInAppLyricsFontSize(
                            inAppLyricsFontSize +
                                PlayerPreferences.inAppLyricsFontSizeStep,
                          )
                      : null,
            ),
            const SizedBox(height: 24),
            _LyricsAlignmentSelector(
              label: copy.inAppAlignment,
              value: widget.inAppLyricsAlignment,
              onChanged: (value) {
                unawaited(widget.onInAppLyricsAlignmentChanged(value));
              },
              alignments: const [
                LyricsAlignment.left,
                LyricsAlignment.center,
                LyricsAlignment.right,
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(copy.resetPositionOnOpen),
              subtitle: Text(copy.resetPositionOnOpenHint),
              value: widget.resetPositionOnOpen,
              onChanged: (value) {
                unawaited(widget.onResetPositionOnOpenChanged(value));
              },
            ),
          ],
        ),
      ),
    );
  }

  void _applyArgb(String value) {
    _commitArgb(value);
  }

  bool _commitArgb(String value) {
    final color = _tryParseArgb(value);
    if (color == null) {
      setState(() {
        _argbError = _LyricsSettingsCopy.of(context).invalidArgb;
      });
      return false;
    }

    _setLyricsColorArgb(color);
    return true;
  }

  void _setLyricsColorArgb(int value) {
    final formattedArgb = _formatArgb(value);
    if (_argbController.text != formattedArgb) {
      _argbController.value = TextEditingValue(
        text: formattedArgb,
        selection: TextSelection.collapsed(offset: formattedArgb.length),
      );
    }
    if (_lyricsColorArgb == value) {
      setState(() {
        _argbError = null;
      });
      return;
    }

    setState(() {
      _lyricsColorArgb = value;
      _argbError = null;
    });
    unawaited(widget.onLyricsColorArgbChanged(value));
  }

  Future<void> _setInAppLyricsFontSize(double value) {
    return ref
        .read(playerPreferencesControllerProvider.notifier)
        .setInAppLyricsFontSize(value);
  }
}

class _LyricsFontSizeStepper extends StatelessWidget {
  const _LyricsFontSizeStepper({
    required this.fontSize,
    required this.label,
    required this.decreaseKey,
    required this.valueKey,
    required this.increaseKey,
    required this.onDecrement,
    required this.onIncrement,
  });

  final double fontSize;
  final String label;
  final Key decreaseKey;
  final Key valueKey;
  final Key increaseKey;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: decreaseKey,
              tooltip: 'Decrease lyrics font size',
              onPressed: onDecrement,
              icon: const Icon(Icons.remove),
            ),
            SizedBox(
              width: 64,
              child: Text(
                fontSize.toStringAsFixed(0),
                key: valueKey,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            IconButton(
              key: increaseKey,
              tooltip: 'Increase lyrics font size',
              onPressed: onIncrement,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ],
    );
  }
}

class _ColorPresetButton extends StatelessWidget {
  const _ColorPresetButton({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _LyricsAlignmentSelector extends StatelessWidget {
  const _LyricsAlignmentSelector({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.alignments,
  });

  final String label;
  final LyricsAlignment value;
  final ValueChanged<LyricsAlignment> onChanged;
  final List<LyricsAlignment> alignments;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label),
        const SizedBox(height: 8),
        SegmentedButton<LyricsAlignment>(
          segments: [
            for (final alignment in alignments)
              ButtonSegment(
                value: alignment,
                icon: Icon(
                  switch (alignment) {
                    LyricsAlignment.left => Icons.format_align_left,
                    LyricsAlignment.center => Icons.format_align_center,
                    LyricsAlignment.right => Icons.format_align_right,
                    LyricsAlignment.split => Icons.format_align_justify,
                  },
                ),
                tooltip: _alignmentTooltip(context, alignment),
              ),
          ],
          selected: {value},
          onSelectionChanged: (selection) {
            onChanged(selection.first);
          },
        ),
      ],
    );
  }

  String _alignmentTooltip(BuildContext context, LyricsAlignment alignment) {
    final isChinese = Localizations.localeOf(context).languageCode == 'zh';
    return switch (alignment) {
      LyricsAlignment.left => isChinese ? '歌词左对齐' : 'Align lyrics left',
      LyricsAlignment.center => isChinese ? '歌词居中对齐' : 'Center lyrics',
      LyricsAlignment.right => isChinese ? '歌词右对齐' : 'Align lyrics right',
      LyricsAlignment.split =>
        isChinese ? '歌词左右分栏对齐' : 'Split lyrics alignment',
    };
  }
}

int? _tryParseArgb(String value) {
  final normalized = value.trim().replaceFirst(RegExp('^#'), '');
  if (!RegExp(r'^[0-9a-fA-F]{8}$').hasMatch(normalized)) {
    return null;
  }
  return int.tryParse(normalized, radix: 16);
}

String _formatArgb(int value) {
  return '#${value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
}

const _colorPresets = <Color>[
  Color(0xFFFFFFFF),
  Color(0xFF80DEEA),
  Color(0xFFFFD166),
  Color(0xFFFF8A80),
  Color(0xFFB39DDB),
];

class _LyricsSettingsCopy {
  const _LyricsSettingsCopy._({
    required this.title,
    required this.backgroundOpacity,
    required this.lyricsColor,
    required this.argbLabel,
    required this.invalidArgb,
    required this.inAppLyricsFontSize,
    required this.desktopLyricsFontSize,
    required this.desktopAlignment,
    required this.inAppAlignment,
    required this.desktopLineMode,
    required this.singleLine,
    required this.doubleLine,
    required this.resetPositionOnOpen,
    required this.resetPositionOnOpenHint,
  });

  final String title;
  final String backgroundOpacity;
  final String lyricsColor;
  final String argbLabel;
  final String invalidArgb;
  final String inAppLyricsFontSize;
  final String desktopLyricsFontSize;
  final String desktopAlignment;
  final String inAppAlignment;
  final String desktopLineMode;
  final String singleLine;
  final String doubleLine;
  final String resetPositionOnOpen;
  final String resetPositionOnOpenHint;

  static _LyricsSettingsCopy of(BuildContext context) {
    return Localizations.localeOf(context).languageCode == 'zh'
        ? const _LyricsSettingsCopy._(
            title: '歌词设置',
            backgroundOpacity: '桌面歌词背景透明度',
            lyricsColor: '歌词颜色',
            argbLabel: 'ARGB 颜色',
            invalidArgb: '请输入 8 位 ARGB 颜色值，例如 #FFFFFFFF。',
            inAppLyricsFontSize: '应用内歌词字号',
            desktopLyricsFontSize: '桌面歌词字号',
            desktopAlignment: '桌面歌词对齐',
            inAppAlignment: '软件内歌词对齐',
            desktopLineMode: '桌面歌词行数',
            singleLine: '单行',
            doubleLine: '双行',
            resetPositionOnOpen: '打开时重置桌面歌词位置',
            resetPositionOnOpenHint: '每次显示时恢复到默认位置。',
          )
        : const _LyricsSettingsCopy._(
            title: 'Lyrics settings',
            backgroundOpacity: 'Desktop lyrics background opacity',
            lyricsColor: 'Lyrics color',
            argbLabel: 'ARGB color',
            invalidArgb: 'Enter an 8-digit ARGB value, for example #FFFFFFFF.',
            inAppLyricsFontSize: 'In-app lyrics font size',
            desktopLyricsFontSize: 'Desktop lyrics font size',
            desktopAlignment: 'Desktop lyrics alignment',
            inAppAlignment: 'In-app lyrics alignment',
            desktopLineMode: 'Desktop lyrics lines',
            singleLine: 'Single line',
            doubleLine: 'Double line',
            resetPositionOnOpen: 'Reset desktop lyrics position on open',
            resetPositionOnOpenHint:
                'Restore the default position whenever lyrics are shown.',
          );
  }
}
