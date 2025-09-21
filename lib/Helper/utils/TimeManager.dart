import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';

class TimerManager {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, HabitRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};

  List<HabitRecord> get activeTimers =>
      _activeTimers.values
          .where((h) => !_hiddenTimers.contains(h.reference.id))
          .toList();

  void start(HabitRecord habit) {
    _activeTimers[habit.reference.id] = habit;
    _hiddenTimers.remove(habit.reference.id);
  }

  void stop(HabitRecord habit) {
    _activeTimers.remove(habit.reference.id);
    _hiddenTimers.add(habit.reference.id);
  }
}
