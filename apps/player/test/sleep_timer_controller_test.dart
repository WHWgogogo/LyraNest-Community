import 'package:flutter_test/flutter_test.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_controller.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_scheduler.dart';
import 'package:player/features/player/application/sleep_timer/sleep_timer_state.dart';

void main() {
  group('SleepTimerController', () {
    late DateTime now;
    late _FakeSleepTimerScheduler scheduler;
    late SleepTimerController controller;
    late String? currentTrackId;
    var pauseCalls = 0;

    setUp(() {
      now = DateTime(2026, 7, 20, 22);
      scheduler = _FakeSleepTimerScheduler(now);
      currentTrackId = 'current-track';
      pauseCalls = 0;
      controller = SleepTimerController(
        pausePlayback: () async {
          pauseCalls += 1;
        },
        currentTrackId: () => currentTrackId,
        now: () => scheduler.now,
        scheduler: scheduler,
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('starts for a duration and pauses exactly at the deadline', () async {
      controller.startFor(const Duration(minutes: 5));

      expect(controller.state.isCountingDown, isTrue);
      expect(controller.state.remaining, const Duration(minutes: 5));
      expect(scheduler.activeTaskCount, 2);

      scheduler.advance(const Duration(seconds: 1));
      expect(
          controller.state.remaining, const Duration(minutes: 4, seconds: 59));

      scheduler.advance(const Duration(minutes: 4, seconds: 59));
      await _flushMicrotasks();

      expect(pauseCalls, 1);
      expect(controller.state.isActive, isFalse);
      expect(scheduler.activeTaskCount, 0);
    });

    test('schedules for a custom end time using the absolute clock', () {
      final endAt = now.add(const Duration(hours: 1, minutes: 12));

      controller.startUntil(endAt);

      expect(controller.state.endAt, endAt);
      expect(controller.state.remaining, const Duration(hours: 1, minutes: 12));
    });

    test('waits for the active track before pausing when requested', () async {
      controller.startFor(
        const Duration(minutes: 1),
        stopMode: SleepTimerStopMode.afterCurrentTrack,
      );

      scheduler.advance(const Duration(minutes: 1));
      await _flushMicrotasks();

      expect(controller.state.isActive, isTrue);
      expect(controller.state.waitingForCurrentTrackEnd, isTrue);
      expect(controller.state.waitingTrackId, 'current-track');
      expect(pauseCalls, 0);
      expect(scheduler.activeTaskCount, 0);

      await controller.notifyCurrentTrackCompleted('different-track');
      expect(pauseCalls, 0);
      expect(controller.state.waitingForCurrentTrackEnd, isTrue);

      await controller.notifyCurrentTrackCompleted('current-track');
      expect(pauseCalls, 1);
      expect(controller.state.isActive, isFalse);

      await controller.notifyCurrentTrackCompleted('current-track');
      expect(pauseCalls, 1);
    });

    test('uses the dedicated post-track callback after the current track ends',
        () async {
      var postTrackPauseCalls = 0;
      controller.dispose();
      controller = SleepTimerController(
        pausePlayback: () async {
          pauseCalls += 1;
        },
        pauseAfterCurrentTrack: () async {
          postTrackPauseCalls += 1;
        },
        currentTrackId: () => currentTrackId,
        now: () => scheduler.now,
        scheduler: scheduler,
      );
      controller.startFor(
        const Duration(seconds: 10),
        stopMode: SleepTimerStopMode.afterCurrentTrack,
      );

      scheduler.advance(const Duration(seconds: 10));
      await controller.notifyCurrentTrackCompleted('current-track');

      expect(pauseCalls, 0);
      expect(postTrackPauseCalls, 1);
    });

    test('pauses at the deadline when no active track can be awaited',
        () async {
      currentTrackId = null;
      controller.startFor(
        const Duration(seconds: 10),
        stopMode: SleepTimerStopMode.afterCurrentTrack,
      );

      scheduler.advance(const Duration(seconds: 10));
      await _flushMicrotasks();

      expect(pauseCalls, 1);
      expect(controller.state.isActive, isFalse);
    });

    test('cancelling prevents the pending pause and releases timer tasks',
        () async {
      controller.startFor(const Duration(minutes: 30));
      controller.cancel();

      scheduler.advance(const Duration(hours: 1));
      await _flushMicrotasks();

      expect(pauseCalls, 0);
      expect(controller.state.isActive, isFalse);
      expect(scheduler.activeTaskCount, 0);
    });

    test('disposing releases timer tasks and ignores delayed callbacks',
        () async {
      controller.startFor(const Duration(minutes: 30));

      controller.dispose();
      scheduler.advance(const Duration(hours: 1));
      await _flushMicrotasks();

      expect(pauseCalls, 0);
      expect(scheduler.activeTaskCount, 0);
    });

    test('rejects non-future durations and end times', () {
      expect(
        () => controller.startFor(Duration.zero),
        throwsArgumentError,
      );
      expect(
        () => controller.startUntil(now),
        throwsArgumentError,
      );
    });
  });
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

class _FakeSleepTimerScheduler implements SleepTimerScheduler {
  _FakeSleepTimerScheduler(this.now);

  DateTime now;
  final List<_FakeSleepTimerTask> _tasks = [];

  int get activeTaskCount => _tasks.where((task) => task.isActive).length;

  @override
  SleepTimerTask schedule(Duration delay, void Function() callback) {
    return _addTask(delay: delay, callback: callback);
  }

  @override
  SleepTimerTask schedulePeriodic(Duration interval, void Function() callback) {
    return _addTask(
      delay: interval,
      interval: interval,
      callback: callback,
    );
  }

  void advance(Duration duration) {
    final target = now.add(duration);
    while (true) {
      final dueTasks = _tasks
          .where(
            (task) => task.isActive && !task.dueAt.isAfter(target),
          )
          .toList()
        ..sort((first, second) => first.dueAt.compareTo(second.dueAt));
      if (dueTasks.isEmpty) {
        now = target;
        return;
      }

      final task = dueTasks.first;
      now = task.dueAt;
      task.run();
    }
  }

  _FakeSleepTimerTask _addTask({
    required Duration delay,
    required void Function() callback,
    Duration? interval,
  }) {
    final task = _FakeSleepTimerTask(
      dueAt: now.add(delay),
      callback: callback,
      interval: interval,
    );
    _tasks.add(task);
    return task;
  }
}

class _FakeSleepTimerTask implements SleepTimerTask {
  _FakeSleepTimerTask({
    required this.dueAt,
    required this.callback,
    this.interval,
  });

  DateTime dueAt;
  final void Function() callback;
  final Duration? interval;
  var isActive = true;

  @override
  void cancel() {
    isActive = false;
  }

  void run() {
    if (!isActive) {
      return;
    }
    final repeatInterval = interval;
    if (repeatInterval == null) {
      isActive = false;
    } else {
      dueAt = dueAt.add(repeatInterval);
    }
    callback();
  }
}
