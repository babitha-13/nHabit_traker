import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';

/// Global timer manager that tracks active timers across the app
class TimerManager extends ChangeNotifier {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, ActivityInstanceRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};
  Timer? _updateTimer;

  /// Get list of active timers (excluding hidden ones)
  List<ActivityInstanceRecord> get activeTimers {
    return _activeTimers.values
        .where((inst) => !_hiddenTimers.contains(inst.reference.id))
        .where((inst) {
      // Only include time-tracking instances that are actually active
      return inst.templateTrackingType == 'time' &&
          inst.isTimerActive &&
          (inst.templateTarget == null ||
              inst.templateTarget == 0 ||
              inst.accumulatedTime < inst.templateTarget!);
    }).toList();
  }

  /// Check if there are any active timers
  bool get hasActiveTimers => activeTimers.isNotEmpty;

  /// Start tracking an instance timer
  void startInstance(ActivityInstanceRecord instance) {
    if (instance.templateTrackingType != 'time') return;
    
    _activeTimers[instance.reference.id] = instance;
    _hiddenTimers.remove(instance.reference.id);
    _startUpdateTimer();
    notifyListeners();
  }

  /// Stop tracking an instance timer
  void stopInstance(ActivityInstanceRecord instance) {
    _activeTimers.remove(instance.reference.id);
    _hiddenTimers.add(instance.reference.id);
    if (_activeTimers.isEmpty) {
      _updateTimer?.cancel();
      _updateTimer = null;
    }
    notifyListeners();
  }

  /// Update an instance in the active timers map
  void updateInstance(ActivityInstanceRecord instance) {
    if (_activeTimers.containsKey(instance.reference.id)) {
      _activeTimers[instance.reference.id] = instance;
      notifyListeners();
    }
  }

  /// Refresh all active timers from Firestore
  Future<void> refreshActiveTimers() async {
    final instanceIds = _activeTimers.keys.toList();
    for (final instanceId in instanceIds) {
      try {
        final updatedInstance =
            await ActivityInstanceService.getUpdatedInstance(
          instanceId: instanceId,
        );
        // Only keep if still active
        if (updatedInstance.isTimerActive &&
            updatedInstance.templateTrackingType == 'time') {
          _activeTimers[instanceId] = updatedInstance;
        } else {
          _activeTimers.remove(instanceId);
        }
      } catch (e) {
        // Remove if we can't fetch it
        _activeTimers.remove(instanceId);
      }
    }
    if (_activeTimers.isEmpty) {
      _updateTimer?.cancel();
      _updateTimer = null;
    }
    notifyListeners();
  }

  /// Start periodic update timer to refresh UI
  void _startUpdateTimer() {
    if (_updateTimer != null) return; // Already running
    
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      // Notify listeners every second for UI updates
      notifyListeners();
    });
  }

  /// Clear all timers (for cleanup)
  void clear() {
    _activeTimers.clear();
    _hiddenTimers.clear();
    _updateTimer?.cancel();
    _updateTimer = null;
    notifyListeners();
  }
}
