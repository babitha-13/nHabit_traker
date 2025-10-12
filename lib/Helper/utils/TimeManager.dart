import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class TimerManager {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, ActivityInstanceRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};

  List<ActivityInstanceRecord> get activeTimers => _activeTimers.values
      .where((inst) => !_hiddenTimers.contains(inst.reference.id))
      .toList();

  void startInstance(ActivityInstanceRecord instance) {
    _activeTimers[instance.reference.id] = instance;
    _hiddenTimers.remove(instance.reference.id);
  }

  void stopInstance(ActivityInstanceRecord instance) {
    _activeTimers.remove(instance.reference.id);
    _hiddenTimers.add(instance.reference.id);
  }
}
