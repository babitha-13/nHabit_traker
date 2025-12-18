import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
      // Always show timer habits, or respect templateShowInFloatingTimer for others
      final shouldShow = inst.templateShowInFloatingTimer ||
          (inst.templateTrackingType == 'time' &&
              inst.templateCategoryType == 'habit');

      // Convert target from minutes to milliseconds for comparison
      final targetInMs = inst.templateTarget != null && inst.templateTarget! > 0
          ? inst.templateTarget! * 60 * 1000
          : null;

      return inst.templateTrackingType == 'time' &&
          inst.isTimerActive &&
          shouldShow &&
          (targetInMs == null || inst.accumulatedTime < targetInMs);
    }).toList();
  }

  /// Check if there are any active timers
  bool get hasActiveTimers => activeTimers.isNotEmpty;

  /// Start tracking an instance timer
  void startInstance(ActivityInstanceRecord instance) {
    // Debug logging to identify why timer isn't being added
    if (instance.templateTrackingType != 'time') {
      debugPrint(
          'TimerManager: Not adding instance ${instance.reference.id} - not a time-tracking type (type: ${instance.templateTrackingType})');
      return;
    }
    if (!instance.isTimerActive) {
      debugPrint(
          'TimerManager: Not adding instance ${instance.reference.id} - timer not active');
      return;
    }
    // Always show timer habits in floating timer (Option A from plan)
    // Remove the templateShowInFloatingTimer check for timer habits
    // But keep it for other types if needed in the future
    final shouldShow = instance.templateShowInFloatingTimer ||
        (instance.templateTrackingType == 'time' &&
            instance.templateCategoryType == 'habit');

    if (!shouldShow) {
      debugPrint(
          'TimerManager: Not adding instance ${instance.reference.id} - templateShowInFloatingTimer is false');
      debugPrint(
          '  Instance: ${instance.templateName}, hasFlag: ${instance.hasTemplateShowInFloatingTimer()}, value: ${instance.templateShowInFloatingTimer}');
      return;
    }

    _activeTimers[instance.reference.id] = instance;
    _hiddenTimers.remove(instance.reference.id);
    _startUpdateTimer();
    notifyListeners();
    debugPrint(
        'TimerManager: Added instance ${instance.reference.id} (${instance.templateName})');
  }

  /// Stop tracking an instance timer
  void stopInstance(ActivityInstanceRecord instance) {
    debugPrint(
        'TimerManager: Stopping instance ${instance.reference.id} (${instance.templateName})');
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
    debugPrint(
        'TimerManager: updateInstance called for ${instance.reference.id} (${instance.templateName}), isActive: ${instance.isTimerActive}, inActiveTimers: ${_activeTimers.containsKey(instance.reference.id)}, inHiddenTimers: ${_hiddenTimers.contains(instance.reference.id)}');

    // Always remove from hiddenTimers if instance is active (handles restart case)
    if (instance.isTimerActive && instance.templateTrackingType == 'time') {
      _hiddenTimers.remove(instance.reference.id);
    }

    if (_activeTimers.containsKey(instance.reference.id)) {
      // Instance is already being tracked
      // Only remove if timer is completed or not a time-tracking instance
      // Keep paused timers in the map so they can be resumed
      final isNotTimeType = instance.templateTrackingType != 'time';
      final hasTarget =
          instance.templateTarget != null && instance.templateTarget != 0;
      // Convert target from minutes to milliseconds for comparison
      final targetInMs =
          hasTarget ? instance.templateTarget! * 60 * 1000 : null;
      final metTarget = hasTarget &&
          targetInMs != null &&
          instance.accumulatedTime >= targetInMs;

      debugPrint(
          'TimerManager: Checking stop conditions for ${instance.reference.id}:');
      debugPrint(
          '  isNotTimeType: $isNotTimeType (type: ${instance.templateTrackingType})');
      debugPrint(
          '  hasTarget: $hasTarget (target: ${instance.templateTarget} minutes = ${targetInMs}ms)');
      debugPrint(
          '  metTarget: $metTarget (accumulated: ${instance.accumulatedTime}ms)');

      if (isNotTimeType || metTarget) {
        debugPrint(
            'TimerManager: Calling stopInstance() because: ${isNotTimeType ? "not time type" : "target met"}');
        stopInstance(instance);
      } else {
        // Update the instance (even if paused - it will be filtered out by activeTimers getter)
        // Ensure it's removed from hiddenTimers (already done above, but keep for clarity)
        _hiddenTimers.remove(instance.reference.id);
        _activeTimers[instance.reference.id] = instance;
        notifyListeners();
        debugPrint(
            'TimerManager: Updated instance ${instance.reference.id} in activeTimers');
      }
    } else if (instance.templateTrackingType == 'time' &&
        instance.isTimerActive) {
      // Instance is not in map but is active - add it (e.g., when resuming/restarting)
      // hiddenTimers removal already handled above
      debugPrint(
          'TimerManager: Adding instance ${instance.reference.id} via updateInstance (restart case)');
      startInstance(instance);
    }
  }

  /// Load all active timers from Firestore (for initialization)
  Future<void> loadActiveTimers({String? userId}) async {
    try {
      final uid = userId ?? FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('TimerManager: Cannot load active timers - no user ID');
        return;
      }

      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('isTimerActive', isEqualTo: true)
          .where('templateTrackingType', isEqualTo: 'time');

      final result = await query.get();
      int addedCount = 0;
      for (final doc in result.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        // Always show timer habits, or respect templateShowInFloatingTimer for others
        final shouldShow = instance.templateShowInFloatingTimer ||
            (instance.templateTrackingType == 'time' &&
                instance.templateCategoryType == 'habit');

        if (shouldShow) {
          _activeTimers[instance.reference.id] = instance;
          _hiddenTimers.remove(instance.reference.id);
          addedCount++;
        }
      }

      if (_activeTimers.isNotEmpty) {
        _startUpdateTimer();
      }
      debugPrint(
          'TimerManager: Loaded $addedCount active timers from Firestore');
      notifyListeners();
    } catch (e) {
      debugPrint('TimerManager: Error loading active timers: $e');
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
        // Only keep if still active and should show in floating timer
        final shouldShow = updatedInstance.templateShowInFloatingTimer ||
            (updatedInstance.templateTrackingType == 'time' &&
                updatedInstance.templateCategoryType == 'habit');

        if (updatedInstance.isTimerActive &&
            updatedInstance.templateTrackingType == 'time' &&
            shouldShow) {
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
