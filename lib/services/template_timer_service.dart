/// Singleton that tracks active timers for time-type templates.
/// Persists across tab navigation so the timer keeps running in the background.
class TemplateTimerService {
  TemplateTimerService._();
  static final TemplateTimerService instance = TemplateTimerService._();

  final Map<String, DateTime> _startTimes = {};

  bool isRunning(String templateId) => _startTimes.containsKey(templateId);

  bool get hasAnyRunning => _startTimes.isNotEmpty;

  Set<String> get runningTemplateIds => Set.unmodifiable(_startTimes.keys);

  void start(String templateId) {
    _startTimes[templateId] = DateTime.now();
  }

  /// Returns the start time and removes the timer. Returns null if not running.
  DateTime? stop(String templateId) {
    return _startTimes.remove(templateId);
  }

  Duration elapsed(String templateId) {
    final start = _startTimes[templateId];
    if (start == null) return Duration.zero;
    return DateTime.now().difference(start);
  }

  String elapsedDisplay(String templateId) {
    final d = elapsed(templateId);
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return d.inHours > 0 ? '${d.inHours}:$m:$s' : '$m:$s';
  }
}
