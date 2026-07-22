import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_controller.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_provider.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_scheduler.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_state.dart';
import 'package:player/features/player/presentation/sleep_timer_controls.dart';
import 'package:player/l10n/l10n.dart';

void main() {
  test('formats sleep timer remaining time', () {
    expect(
      formatSleepTimerRemaining(const Duration(minutes: 3, seconds: 7)),
      '3:07',
    );
    expect(
      formatSleepTimerRemaining(
        const Duration(hours: 1, minutes: 3, seconds: 7),
      ),
      '1:03:07',
    );
  });

  testWidgets('starts a custom duration from the reusable button',
      (tester) async {
    final scheduler = _NoopSleepTimerScheduler();
    final controller = SleepTimerController(
      pausePlayback: () {},
      currentTrackId: () => 'track-1',
      now: () => DateTime(2026, 7, 20, 22),
      scheduler: scheduler,
    );
    final changedStates = <SleepTimerState>[];

    await _pumpControls(
      tester,
      controller: controller,
      onTimerChanged: changedStates.add,
    );

    await tester.tap(find.byKey(const ValueKey('sleep-timer-button')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('sleep-timer-duration-input')),
      '45',
    );
    await tester.tap(find.byKey(const ValueKey('sleep-timer-start')));
    await tester.pumpAndSettle();

    expect(controller.state.remaining, const Duration(minutes: 45));
    expect(controller.state.stopMode, SleepTimerStopMode.immediately);
    expect(changedStates, hasLength(1));
    expect(changedStates.single.isCountingDown, isTrue);
  });

  testWidgets('shows the remaining time and cancels an active timer',
      (tester) async {
    final scheduler = _NoopSleepTimerScheduler();
    final controller = SleepTimerController(
      pausePlayback: () {},
      currentTrackId: () => 'track-1',
      now: () => DateTime(2026, 7, 20, 22),
      scheduler: scheduler,
    )..startFor(const Duration(minutes: 30));
    final changedStates = <SleepTimerState>[];

    await _pumpControls(
      tester,
      controller: controller,
      onTimerChanged: changedStates.add,
    );

    await tester.tap(find.byKey(const ValueKey('sleep-timer-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('sleep-timer-active')), findsOneWidget);
    expect(find.text('30:00 remaining'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('sleep-timer-cancel')));
    await tester.pump();

    expect(controller.state.isActive, isFalse);
    expect(changedStates, hasLength(1));
    expect(changedStates.single.isActive, isFalse);
  });
}

Future<void> _pumpControls(
  WidgetTester tester, {
  required SleepTimerController controller,
  required SleepTimerStateChanged onTimerChanged,
}) {
  return tester.pumpWidget(
    ProviderScope(
      overrides: [
        sleepTimerControllerProvider.overrideWith((ref) => controller),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SleepTimerButton(onTimerChanged: onTimerChanged),
          ),
        ),
      ),
    ),
  );
}

class _NoopSleepTimerScheduler implements SleepTimerScheduler {
  final List<_NoopSleepTimerTask> tasks = [];

  @override
  SleepTimerTask schedule(Duration delay, void Function() callback) {
    return _addTask();
  }

  @override
  SleepTimerTask schedulePeriodic(Duration interval, void Function() callback) {
    return _addTask();
  }

  SleepTimerTask _addTask() {
    final task = _NoopSleepTimerTask();
    tasks.add(task);
    return task;
  }
}

class _NoopSleepTimerTask implements SleepTimerTask {
  @override
  void cancel() {}
}
