import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/l10n.dart';
import '../application/sleep_timer/sleep_timer_provider.dart';
import '../application/sleep_timer/sleep_timer_state.dart';

typedef SleepTimerStateChanged = void Function(SleepTimerState state);

class SleepTimerButton extends ConsumerWidget {
  const SleepTimerButton({
    this.onTimerChanged,
    this.iconSize,
    this.color,
    super.key,
  });

  final SleepTimerStateChanged? onTimerChanged;
  final double? iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sleepTimerControllerProvider);
    final l10n = context.l10n;

    return IconButton(
      key: const ValueKey('sleep-timer-button'),
      tooltip: state.isActive
          ? l10n.sleepTimerActiveTooltip
          : l10n.sleepTimerTooltip,
      onPressed: () {
        unawaited(
          showSleepTimerSheet(
            context,
            onTimerChanged: onTimerChanged,
          ),
        );
      },
      iconSize: iconSize,
      color: color,
      icon: Icon(
        state.isActive ? Icons.timer_rounded : Icons.bedtime_outlined,
      ),
    );
  }
}

Future<void> showSleepTimerSheet(
  BuildContext context, {
  SleepTimerStateChanged? onTimerChanged,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      return _SleepTimerSheet(onTimerChanged: onTimerChanged);
    },
  );
}

class _SleepTimerSheet extends ConsumerStatefulWidget {
  const _SleepTimerSheet({this.onTimerChanged});

  final SleepTimerStateChanged? onTimerChanged;

  @override
  ConsumerState<_SleepTimerSheet> createState() => _SleepTimerSheetState();
}

class _SleepTimerSheetState extends ConsumerState<_SleepTimerSheet> {
  late final TextEditingController _durationController;
  var _inputMode = _SleepTimerInputMode.duration;
  var _stopMode = SleepTimerStopMode.immediately;
  TimeOfDay? _endTime;

  @override
  void initState() {
    super.initState();
    _durationController = TextEditingController(text: '30');
  }

  @override
  void dispose() {
    _durationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(sleepTimerControllerProvider);
    final l10n = context.l10n;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          MediaQuery.viewInsetsOf(context).bottom + 20,
        ),
        child: state.isActive
            ? _ActiveSleepTimer(
                state: state,
                onCancel: _cancel,
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.sleepTimerTitle,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      children: [
                        ChoiceChip(
                          key: const ValueKey('sleep-timer-duration-mode'),
                          label: Text(l10n.sleepTimerDuration),
                          selected: _inputMode == _SleepTimerInputMode.duration,
                          onSelected: (_) {
                            setState(
                              () => _inputMode = _SleepTimerInputMode.duration,
                            );
                          },
                        ),
                        ChoiceChip(
                          key: const ValueKey('sleep-timer-end-time-mode'),
                          label: Text(l10n.sleepTimerEndTime),
                          selected: _inputMode == _SleepTimerInputMode.endTime,
                          onSelected: (_) {
                            setState(
                              () => _inputMode = _SleepTimerInputMode.endTime,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_inputMode == _SleepTimerInputMode.duration)
                      TextField(
                        key: const ValueKey('sleep-timer-duration-input'),
                        controller: _durationController,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly
                        ],
                        decoration: InputDecoration(
                          labelText: l10n.sleepTimerDurationMinutes,
                          suffixText: l10n.sleepTimerMinutes,
                          border: const OutlineInputBorder(),
                        ),
                      )
                    else
                      _EndTimePicker(
                        endTime: _endTime,
                        onPressed: _selectEndTime,
                      ),
                    const SizedBox(height: 16),
                    Text(
                      l10n.sleepTimerWhenFinished,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    RadioGroup<SleepTimerStopMode>(
                      groupValue: _stopMode,
                      onChanged: _setStopMode,
                      child: Column(
                        children: [
                          RadioListTile<SleepTimerStopMode>(
                            contentPadding: EdgeInsets.zero,
                            value: SleepTimerStopMode.immediately,
                            title: Text(l10n.sleepTimerPauseImmediately),
                          ),
                          RadioListTile<SleepTimerStopMode>(
                            contentPadding: EdgeInsets.zero,
                            value: SleepTimerStopMode.afterCurrentTrack,
                            title: Text(l10n.sleepTimerPauseAfterCurrentTrack),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        key: const ValueKey('sleep-timer-start'),
                        onPressed: _start,
                        child: Text(l10n.sleepTimerStart),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  void _setStopMode(SleepTimerStopMode? value) {
    if (value == null) {
      return;
    }
    setState(() => _stopMode = value);
  }

  Future<void> _selectEndTime() async {
    final initialTime = _endTime ??
        TimeOfDay.fromDateTime(
          DateTime.now().add(const Duration(minutes: 30)),
        );
    final selected = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (!mounted || selected == null) {
      return;
    }
    setState(() => _endTime = selected);
  }

  void _start() {
    final controller = ref.read(sleepTimerControllerProvider.notifier);
    try {
      if (_inputMode == _SleepTimerInputMode.duration) {
        final minutes = int.tryParse(_durationController.text);
        if (minutes == null || minutes <= 0) {
          _showDurationError();
          return;
        }
        controller.startFor(
          Duration(minutes: minutes),
          stopMode: _stopMode,
        );
      } else {
        final endTime = _endTime;
        if (endTime == null) {
          _showEndTimeError();
          return;
        }
        controller.startUntil(
          _nextEndAt(endTime),
          stopMode: _stopMode,
        );
      }
    } on ArgumentError {
      _showDurationError();
      return;
    }

    final state = ref.read(sleepTimerControllerProvider);
    widget.onTimerChanged?.call(state);
    Navigator.of(context).pop();
  }

  void _cancel() {
    final controller = ref.read(sleepTimerControllerProvider.notifier);
    controller.cancel();
    widget.onTimerChanged?.call(ref.read(sleepTimerControllerProvider));
  }

  DateTime _nextEndAt(TimeOfDay endTime) {
    final now = DateTime.now();
    var endAt = DateTime(
      now.year,
      now.month,
      now.day,
      endTime.hour,
      endTime.minute,
    );
    if (!endAt.isAfter(now)) {
      endAt = endAt.add(const Duration(days: 1));
    }
    return endAt;
  }

  void _showDurationError() {
    _showError(context.l10n.sleepTimerInvalidDuration);
  }

  void _showEndTimeError() {
    _showError(context.l10n.sleepTimerSelectEndTime);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _EndTimePicker extends StatelessWidget {
  const _EndTimePicker({
    required this.endTime,
    required this.onPressed,
  });

  final TimeOfDay? endTime;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selectedTime = endTime;
    return OutlinedButton.icon(
      key: const ValueKey('sleep-timer-end-time-picker'),
      onPressed: onPressed,
      icon: const Icon(Icons.schedule_rounded),
      label: Text(
        selectedTime == null
            ? l10n.sleepTimerSelectEndTime
            : MaterialLocalizations.of(context).formatTimeOfDay(selectedTime),
      ),
    );
  }
}

class _ActiveSleepTimer extends StatelessWidget {
  const _ActiveSleepTimer({
    required this.state,
    required this.onCancel,
  });

  final SleepTimerState state;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final message = state.waitingForCurrentTrackEnd
        ? l10n.sleepTimerWaitingForCurrentTrack
        : l10n.sleepTimerRemaining(
            formatSleepTimerRemaining(state.remaining),
          );

    return Column(
      key: const ValueKey('sleep-timer-active'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.sleepTimerTitle,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 16),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.timer_rounded),
          title: Text(message),
          subtitle: Text(
            state.stopMode == SleepTimerStopMode.immediately
                ? l10n.sleepTimerPauseImmediately
                : l10n.sleepTimerPauseAfterCurrentTrack,
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            key: const ValueKey('sleep-timer-cancel'),
            onPressed: onCancel,
            child: Text(l10n.sleepTimerCancel),
          ),
        ),
      ],
    );
  }
}

enum _SleepTimerInputMode {
  duration,
  endTime,
}

String formatSleepTimerRemaining(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final hours = totalSeconds ~/ Duration.secondsPerHour;
  final minutes =
      (totalSeconds % Duration.secondsPerHour) ~/ Duration.secondsPerMinute;
  final seconds = totalSeconds % Duration.secondsPerMinute;
  final paddedMinutes = minutes.toString().padLeft(2, '0');
  final paddedSeconds = seconds.toString().padLeft(2, '0');

  return hours == 0
      ? '$minutes:$paddedSeconds'
      : '$hours:$paddedMinutes:$paddedSeconds';
}
