import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';

/// Global timer manager that tracks active timers across the app
class TimerManager extends ChangeNotifier {
  static final TimerManager _instance = TimerManager._internal();
  factory TimerManager() => _instance;
  TimerManager._internal();

  final Map<String, ActivityInstanceRecord> _activeTimers = {};
  final Set<String> _hiddenTimers = {};
  Timer? _updateTimer;

  bool _isSessionLogging(ActivityInstanceRecord instance) {
    return instance.isTimeLogging || instance.currentSessionStartTime != null;
  }

  /// Check if an instance is an active timer session (time type or binary with time logging)
  bool _isTimerSession(ActivityInstanceRecord instance) {
    final trackingType = instance.templateTrackingType;
    // Time tracking can run through legacy timer fields or session fields.
    if (trackingType == 'time') {
      return instance.isTimerActive || _isSessionLogging(instance);
    }
    // Session-based timer logging for swipe/start timer flows.
    if ((trackingType == 'binary' || trackingType == 'quantitative') &&
        _isSessionLogging(instance)) {
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

      // Session-based timers for binary/quantitative tracking.
      if (inst.templateTrackingType == 'binary' ||
          inst.templateTrackingType == 'quantitative') {
        return _isSessionLogging(inst);
      }

      // For time-tracking instances, check active state and target not met.
      final isRunning = inst.isTimerActive || _isSessionLogging(inst);
      final targetInMs = inst.templateTarget != null && inst.templateTarget! > 0
          ? inst.templateTarget! * 60 * 1000
          : null;

      return isRunning && (targetInMs == null || inst.accumulatedTime < targetInMs);
    }).toList();
  }

  /// Check if there are any active timers
  bool get hasActiveTimers => activeTimers.isNotEmpty;

  /// Start tracking an instance timer
  void startInstance(ActivityInstanceRecord instance) {
    // Check if this is a timer session
    if (!_isTimerSession(instance)) {
      debugPrint(
          'TimerManager: Not adding instance ${instance.reference.id} - not an active timer session (type: ${instance.templateTrackingType}, isTimerActive: ${instance.isTimerActive}, isTimeLogging: ${instance.isTimeLogging})');
      return;
    }

    // For session-based timers, logging must be active.
    if (instance.templateTrackingType == 'binary' ||
        instance.templateTrackingType == 'quantitative') {
      if (!_isSessionLogging(instance)) {
        debugPrint(
            'TimerManager: Not adding instance ${instance.reference.id} - session is not actively logging');
        return;
      }
    } else {
      // For time-tracking instances, support legacy active flag and session logging.
      if (!instance.isTimerActive && !_isSessionLogging(instance)) {
        debugPrint(
            'TimerManager: Not adding instance ${instance.reference.id} - time timer not active');
        return;
      }
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
      if (instance.templateTrackingType == 'binary' ||
          instance.templateTrackingType == 'quantitative') {
        if (_isSessionLogging(instance)) {
          _hiddenTimers.remove(instance.reference.id);
        }
      } else if (instance.isTimerActive || _isSessionLogging(instance)) {
        _hiddenTimers.remove(instance.reference.id);
      }
    }

    if (_activeTimers.containsKey(instance.reference.id)) {
      // Instance is already being tracked
      // Only remove if timer session is no longer active
      final isNotTimerSession = !_isTimerSession(instance);

      // For binary timer sessions, check if time logging stopped
      bool timerSessionStopped = false;
      if (instance.templateTrackingType == 'binary' ||
          instance.templateTrackingType == 'quantitative') {
        timerSessionStopped = !_isSessionLogging(instance);
      } else {
        // For time-tracking instances, check if timer is no longer active
        final isRunning = instance.isTimerActive || _isSessionLogging(instance);
        final hasTarget =
            instance.templateTarget != null && instance.templateTarget != 0;
        final targetInMs =
            hasTarget ? instance.templateTarget! * 60 * 1000 : null;
        final targetReached =
            hasTarget && targetInMs != null && instance.accumulatedTime >= targetInMs;
        timerSessionStopped = !isRunning || targetReached;
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
      if (instance.templateTrackingType == 'binary' ||
          instance.templateTrackingType == 'quantitative') {
        if (_isSessionLogging(instance)) {
          debugPrint(
              'TimerManager: Adding instance ${instance.reference.id} via updateInstance (session timer)');
          startInstance(instance);
        }
      } else if (instance.isTimerActive || _isSessionLogging(instance)) {
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

      // Load all active session-based timers (binary/time/quantitative).
      final sessionQuery = ActivityInstanceRecord.collectionForUser(uid)
          .where('isTimeLogging', isEqualTo: true);

      final timeResult = await timeQuery.get();
      final sessionResult = await sessionQuery.get();

      // Process time-tracking instances
      for (final doc in timeResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (_isTimerSession(instance)) {
          _activeTimers[instance.reference.id] = instance;
          _hiddenTimers.remove(instance.reference.id);
        }
      }

      // Process session-based timers
      for (final doc in sessionResult.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);
        if (_isTimerSession(instance)) {
          _activeTimers[instance.reference.id] = instance;
          _hiddenTimers.remove(instance.reference.id);
        }
      }

      if (_activeTimers.isNotEmpty) {
        _startUpdateTimer();
      }
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
          if (updatedInstance.templateTrackingType == 'binary' ||
              updatedInstance.templateTrackingType == 'quantitative') {
            if (_isSessionLogging(updatedInstance)) {
              _activeTimers[instanceId] = updatedInstance;
            } else {
              _activeTimers.remove(instanceId);
            }
          } else if (updatedInstance.isTimerActive ||
              _isSessionLogging(updatedInstance)) {
            _activeTimers[instanceId] = updatedInstance;
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
