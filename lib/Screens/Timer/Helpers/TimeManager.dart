import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';

/// Global timer manager that tracks active timers across the app
class TimerManager extends ChangeNotifier {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, ActivityInstanceRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};
  Timer? _updateTimer;

  /// Check if an instance is an active timer session (time type or binary with time logging)
  bool _isTimerSession(ActivityInstanceRecord instance) {
    // Time-tracking instances
    if (instance.templateTrackingType == 'time') {
      return true;
    }
    // Binary timer sessions (created from timer page)
    if (instance.templateTrackingType == 'binary' &&
        (instance.isTimeLogging || instance.currentSessionStartTime != null)) {
      return true;
    }
    return false;
  }

  /// Get list of active timers (excluding hidden ones)
  List<ActivityInstanceRecord> get activeTimers {
    return _activeTimers.values
        .where((inst) => !_hiddenTimers.contains(inst.reference.id))
        .where((inst) {
      // Check if this is a timer session (time type or binary with time logging)
      if (!_isTimerSession(inst)) {
        return false;
      }

      // Always show timer habits, or respect templateShowInFloatingTimer for others
      final shouldShow = inst.templateShowInFloatingTimer ||
          (inst.templateTrackingType == 'time' &&
              inst.templateCategoryType == 'habit');

      if (!shouldShow) {
        return false;
      }

      // For binary timer sessions, check if time logging is active
      if (inst.templateTrackingType == 'binary') {
        return inst.isTimeLogging || inst.currentSessionStartTime != null;
      }

      // For time-tracking instances, check if timer is active and target not met
      final targetInMs = inst.templateTarget != null && inst.templateTarget! > 0
          ? inst.templateTarget! * 60 * 1000
          : null;

      return inst.isTimerActive &&
          (targetInMs == null || inst.accumulatedTime < targetInMs);
    }).toList();
  }

  /// Check if there are any active timers
  bool get hasActiveTimers => activeTimers.isNotEmpty;

  /// Start tracking an instance timer
  void startInstance(ActivityInstanceRecord instance) {
    // Check if this is a timer session
    if (!_isTimerSession(instance)) {
      debugPrint(
          'TimerManager: Not adding instance ${instance.reference.id} - not a timer session (type: ${instance.templateTrackingType}, isTimeLogging: ${instance.isTimeLogging})');
      return;
    }

    // For binary timer sessions, check if time logging is active
    if (instance.templateTrackingType == 'binary') {
      if (!instance.isTimeLogging && instance.currentSessionStartTime == null) {
        debugPrint(
            'TimerManager: Not adding instance ${instance.reference.id} - binary timer not actively logging');
        return;
      }
    } else {
      // For time-tracking instances, check if timer is active
      if (!instance.isTimerActive) {
        debugPrint(
            'TimerManager: Not adding instance ${instance.reference.id} - timer not active');
        return;
      }
    }

    // Always show timer habits in floating timer, or respect templateShowInFloatingTimer
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
        'TimerManager: updateInstance called for ${instance.reference.id} (${instance.templateName}), isActive: ${instance.isTimerActive}, isTimeLogging: ${instance.isTimeLogging}, inActiveTimers: ${_activeTimers.containsKey(instance.reference.id)}, inHiddenTimers: ${_hiddenTimers.contains(instance.reference.id)}');

    // Always remove from hiddenTimers if instance is an active timer session
    if (_isTimerSession(instance)) {
      if (instance.templateTrackingType == 'binary') {
        if (instance.isTimeLogging ||
            instance.currentSessionStartTime != null) {
          _hiddenTimers.remove(instance.reference.id);
        }
      } else if (instance.isTimerActive) {
        _hiddenTimers.remove(instance.reference.id);
      }
    }

    if (_activeTimers.containsKey(instance.reference.id)) {
      // Instance is already being tracked
      // Only remove if timer session is no longer active
      final isNotTimerSession = !_isTimerSession(instance);

      // For binary timer sessions, check if time logging stopped
      bool timerSessionStopped = false;
      if (instance.templateTrackingType == 'binary') {
        timerSessionStopped =
            !instance.isTimeLogging && instance.currentSessionStartTime == null;
      } else {
        // For time-tracking instances, check if target met
        final hasTarget =
            instance.templateTarget != null && instance.templateTarget != 0;
        final targetInMs =
            hasTarget ? instance.templateTarget! * 60 * 1000 : null;
        timerSessionStopped = hasTarget &&
            targetInMs != null &&
            instance.accumulatedTime >= targetInMs;
      }

      debugPrint(
          'TimerManager: Checking stop conditions for ${instance.reference.id}:');
      debugPrint('  isNotTimerSession: $isNotTimerSession');
      debugPrint('  timerSessionStopped: $timerSessionStopped');

      if (isNotTimerSession || timerSessionStopped) {
        debugPrint(
            'TimerManager: Calling stopInstance() because: ${isNotTimerSession ? "not a timer session" : "session stopped"}');
        stopInstance(instance);
      } else {
        // Update the instance (even if paused - it will be filtered out by activeTimers getter)
        _hiddenTimers.remove(instance.reference.id);
        _activeTimers[instance.reference.id] = instance;
        notifyListeners();
        debugPrint(
            'TimerManager: Updated instance ${instance.reference.id} in activeTimers');
      }
    } else if (_isTimerSession(instance)) {
      // Instance is not in map but is an active timer session - add it
      if (instance.templateTrackingType == 'binary') {
        if (instance.isTimeLogging ||
            instance.currentSessionStartTime != null) {
          debugPrint(
              'TimerManager: Adding instance ${instance.reference.id} via updateInstance (binary timer session)');
          startInstance(instance);
        }
      } else if (instance.isTimerActive) {
        debugPrint(
            'TimerManager: Adding instance ${instance.reference.id} via updateInstance (time timer restart)');
        startInstance(instance);
      }
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

      // Load time-tracking instances with active timers
      final timeQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('isTimerActive', isEqualTo: true)
          .where('templateTrackingType', isEqualTo: 'time');

      // Load binary timer sessions (with time logging active)
      final binaryQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('isTimeLogging', isEqualTo: true)
          .where('templateTrackingType', isEqualTo: 'binary');

      final timeResult = await timeQuery.get();
      final binaryResult = await binaryQuery.get();

      int addedCount = 0;

      // Process time-tracking instances
      for (final doc in timeResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        final shouldShow = instance.templateShowInFloatingTimer ||
            (instance.templateTrackingType == 'time' &&
                instance.templateCategoryType == 'habit');

        if (shouldShow) {
          _activeTimers[instance.reference.id] = instance;
          _hiddenTimers.remove(instance.reference.id);
          addedCount++;
        }
      }

      // Process binary timer sessions
      for (final doc in binaryResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (instance.templateShowInFloatingTimer) {
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

        // Check if still a timer session and should show
        if (_isTimerSession(updatedInstance)) {
          final shouldShow = updatedInstance.templateShowInFloatingTimer ||
              (updatedInstance.templateTrackingType == 'time' &&
                  updatedInstance.templateCategoryType == 'habit');

          if (shouldShow) {
            // For binary timer sessions, check if still logging
            if (updatedInstance.templateTrackingType == 'binary') {
              if (updatedInstance.isTimeLogging ||
                  updatedInstance.currentSessionStartTime != null) {
                _activeTimers[instanceId] = updatedInstance;
              } else {
                _activeTimers.remove(instanceId);
              }
            } else if (updatedInstance.isTimerActive) {
              _activeTimers[instanceId] = updatedInstance;
            } else {
              _activeTimers.remove(instanceId);
            }
          } else {
            _activeTimers.remove(instanceId);
          }
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
