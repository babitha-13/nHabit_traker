import 'dart:async';

/// Simple debouncer to coalesce rapid events (e.g. slider drags) into one action.
///
/// Usage:
/// ```dart
/// final debouncer = Debouncer(const Duration(milliseconds: 400));
/// debouncer.run(() async { await save(); });
/// ```
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(FutureOr<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, () => action());
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() => cancel();
}


