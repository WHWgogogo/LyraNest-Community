import 'dart:async';

abstract interface class SleepTimerTask {
  void cancel();
}

abstract interface class SleepTimerScheduler {
  SleepTimerTask schedule(Duration delay, void Function() callback);

  SleepTimerTask schedulePeriodic(Duration interval, void Function() callback);
}

class SystemSleepTimerScheduler implements SleepTimerScheduler {
  const SystemSleepTimerScheduler();

  @override
  SleepTimerTask schedule(Duration delay, void Function() callback) {
    return _SystemSleepTimerTask(Timer(delay, callback));
  }

  @override
  SleepTimerTask schedulePeriodic(
    Duration interval,
    void Function() callback,
  ) {
    return _SystemSleepTimerTask(Timer.periodic(interval, (_) => callback()));
  }
}

class _SystemSleepTimerTask implements SleepTimerTask {
  const _SystemSleepTimerTask(this._timer);

  final Timer _timer;

  @override
  void cancel() {
    _timer.cancel();
  }
}
