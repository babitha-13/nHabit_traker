import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';

class TimerManager {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, ActivityRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};

  List<ActivityRecord> get activeTimers => _activeTimers.values
      .where((h) => !_hiddenTimers.contains(h.reference.id))
      .toList();

  void start(ActivityRecord habit) {
    _activeTimers[habit.reference.id] = habit;
    _hiddenTimers.remove(habit.reference.id);
  }

  void stop(ActivityRecord habit) {
    _activeTimers.remove(habit.reference.id);
    _hiddenTimers.add(habit.reference.id);
  }
}
