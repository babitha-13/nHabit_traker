import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Centralized instance event management
/// Provides constants and helper methods for broadcasting instance changes
class InstanceEvents {
  // Event constants
  static const String instanceCreated = 'instanceCreated';
  static const String instanceUpdated = 'instanceUpdated';
  static const String instanceDeleted = 'instanceDeleted';
  static const String progressRecalculated = 'progressRecalculated';
  static const int _defaultOptimisticSessionMs = 10 * 60 * 1000;

  /// Broadcast when a new instance is created
  static void broadcastInstanceCreated(ActivityInstanceRecord instance) {
    NotificationCenter.post(instanceCreated, instance);
  }

  /// Broadcast when an instance is updated (completed, uncompleted, etc.)
  static void broadcastInstanceUpdated(ActivityInstanceRecord instance) {
    NotificationCenter.post(instanceUpdated, instance);
  }

  /// Broadcast when an instance is deleted
  static void broadcastInstanceDeleted(ActivityInstanceRecord instance) {
    NotificationCenter.post(instanceDeleted, instance);
  }

  /// Broadcast when progress needs to be recalculated
  static void broadcastProgressRecalculated() {
    NotificationCenter.post(progressRecalculated, null);
  }

  // ==================== OPTIMISTIC BROADCAST METHODS ====================

  /// Broadcast optimistic instance update (before backend)
  static void broadcastInstanceUpdatedOptimistic(
    ActivityInstanceRecord optimisticInstance,
    String operationId, // Unique ID for this operation
  ) {
    NotificationCenter.post(instanceUpdated, {
      'instance': optimisticInstance,
      'isOptimistic': true,
      'operationId': operationId,
    });
  }

  /// Broadcast reconciled instance update (after backend)
  static void broadcastInstanceUpdatedReconciled(
    ActivityInstanceRecord actualInstance,
    String operationId,
  ) {
    NotificationCenter.post(instanceUpdated, {
      'instance': actualInstance,
      'isOptimistic': false,
      'operationId': operationId,
    });
  }

  /// Broadcast optimistic instance creation (before backend)
  static void broadcastInstanceCreatedOptimistic(
    ActivityInstanceRecord optimisticInstance,
    String operationId,
  ) {
    NotificationCenter.post(instanceCreated, {
      'instance': optimisticInstance,
      'isOptimistic': true,
      'operationId': operationId,
    });
  }

  /// Broadcast reconciled instance creation (after backend)
  static void broadcastInstanceCreatedReconciled(
    ActivityInstanceRecord actualInstance,
    String operationId,
  ) {
    NotificationCenter.post(instanceCreated, {
      'instance': actualInstance,
      'isOptimistic': false,
      'operationId': operationId,
    });
  }

  // ==================== OPTIMISTIC INSTANCE BUILDERS ====================

  /// Create optimistic instance for completion
  static ActivityInstanceRecord createOptimisticCompletedInstance(
    ActivityInstanceRecord original, {
    dynamic finalValue,
    int? finalAccumulatedTime,
    DateTime? completedAt,
    List<Map<String, dynamic>>? timeLogSessions,
    int? totalTimeLogged,
    String? templateCategoryColorHex,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = completedAt ?? DateTime.now();

    updatedData['status'] = 'completed';
    updatedData['completedAt'] = now;
    updatedData['lastUpdated'] = now;

    // Update progress values if provided
    if (finalValue != null) {
      updatedData['currentValue'] = finalValue;
    }
    if (finalAccumulatedTime != null) {
      updatedData['accumulatedTime'] = finalAccumulatedTime;
    }

    // Include time log sessions if provided (for calendar rendering)
    if (timeLogSessions != null) {
      updatedData['timeLogSessions'] = timeLogSessions;
    }
    if (totalTimeLogged != null) {
      updatedData['totalTimeLogged'] = totalTimeLogged;
    }
    final existingCategoryColor =
        (updatedData['templateCategoryColor'] as String?)?.trim() ?? '';
    if (existingCategoryColor.isEmpty &&
        templateCategoryColorHex != null &&
        templateCategoryColorHex.trim().isNotEmpty) {
      updatedData['templateCategoryColor'] = templateCategoryColorHex.trim();
    }

    if (!_hasSessions(updatedData['timeLogSessions'])) {
      final durationMs = _inferOptimisticCompletionDurationMs(
        original,
        finalAccumulatedTime: finalAccumulatedTime,
        totalTimeLogged: totalTimeLogged,
      );
      final sessionEnd = now;
      final sessionStart =
          sessionEnd.subtract(Duration(milliseconds: durationMs));
      updatedData['timeLogSessions'] = [
        {
          'startTime': sessionStart,
          'endTime': sessionEnd,
          'durationMilliseconds': durationMs,
        }
      ];
      updatedData['totalTimeLogged'] = totalTimeLogged ?? durationMs;

      if (original.templateTrackingType == 'time') {
        updatedData['accumulatedTime'] = finalAccumulatedTime ?? durationMs;
        if (finalValue == null) {
          updatedData['currentValue'] = durationMs;
        }
      }
    }

    // Clear skipped status if present
    updatedData['skippedAt'] = null;

    // Mark as optimistic (add metadata flag for tracking)
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  static bool _hasSessions(dynamic sessions) {
    return sessions is List && sessions.isNotEmpty;
  }

  static int _inferOptimisticCompletionDurationMs(
    ActivityInstanceRecord original, {
    int? finalAccumulatedTime,
    int? totalTimeLogged,
  }) {
    int inferredMs = _defaultOptimisticSessionMs;

    if (finalAccumulatedTime != null && finalAccumulatedTime > 0) {
      inferredMs = finalAccumulatedTime;
    } else if (totalTimeLogged != null && totalTimeLogged > 0) {
      inferredMs = totalTimeLogged;
    } else if (original.accumulatedTime > 0) {
      inferredMs = original.accumulatedTime;
    } else if (original.totalTimeLogged > 0) {
      inferredMs = original.totalTimeLogged;
    } else if ((original.templateTimeEstimateMinutes ?? 0) > 0) {
      inferredMs = original.templateTimeEstimateMinutes! * 60000;
    } else if (original.templateTrackingType == 'time') {
      final target = original.templateTarget;
      final targetMinutes = (target is num)
          ? target.toDouble()
          : (target is String ? double.tryParse(target) ?? 0.0 : 0.0);
      if (targetMinutes > 0) {
        inferredMs = (targetMinutes * 60000).round();
      }
    }

    if (inferredMs < 60000) {
      inferredMs = 60000;
    }
    return inferredMs;
  }

  /// Create optimistic instance for uncompletion
  static ActivityInstanceRecord createOptimisticUncompletedInstance(
    ActivityInstanceRecord original, {
    bool deleteLogs = false,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    updatedData['status'] = 'pending';
    updatedData['completedAt'] = null;
    updatedData['skippedAt'] = null;
    updatedData['lastUpdated'] = now;

    // Reset counter to 0 for binary habits when uncompleting
    if (original.templateTrackingType == 'binary') {
      updatedData['currentValue'] = 0;
    }
    // For quantitative/time-based, preserve currentValue/accumulatedTime
    // (user might want to keep partial progress)

    if (deleteLogs) {
      updatedData['timeLogSessions'] = [];
      updatedData['totalTimeLogged'] = 0;
      updatedData['accumulatedTime'] = 0;
      updatedData['currentValue'] = 0;
    }

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for progress update
  static ActivityInstanceRecord createOptimisticProgressInstance(
    ActivityInstanceRecord original, {
    dynamic currentValue,
    int? accumulatedTime,
    bool? isTimerActive,
    DateTime? timerStartTime,
    List<Map<String, dynamic>>? timeLogSessions,
    int? totalTimeLogged,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    updatedData['lastUpdated'] = now;

    // Update progress values if provided
    if (currentValue != null) {
      updatedData['currentValue'] = currentValue;
    }
    if (accumulatedTime != null) {
      updatedData['accumulatedTime'] = accumulatedTime;
    }
    if (isTimerActive != null) {
      updatedData['isTimerActive'] = isTimerActive;
    }
    if (timerStartTime != null) {
      updatedData['timerStartTime'] = timerStartTime;
    }
    if (timeLogSessions != null) {
      updatedData['timeLogSessions'] = timeLogSessions;
    }
    if (totalTimeLogged != null) {
      updatedData['totalTimeLogged'] = totalTimeLogged;
    }

    // Check if target is met and should auto-complete
    // This logic matches the backend behavior
    final target = original.templateTarget;
    final trackingType = original.templateTrackingType;

    if (trackingType == 'quantitative' &&
        currentValue != null &&
        target != null) {
      final current = (currentValue is num)
          ? currentValue.toDouble()
          : (currentValue is String)
              ? double.tryParse(currentValue) ?? 0.0
              : 0.0;
      final targetValue = (target is num)
          ? target.toDouble()
          : (target is String)
              ? double.tryParse(target) ?? 0.0
              : 0.0;

      if (targetValue > 0 &&
          current >= targetValue &&
          original.status != 'completed') {
        updatedData['status'] = 'completed';
        updatedData['completedAt'] = now;
      }
    } else if (trackingType == 'time' &&
        accumulatedTime != null &&
        target != null) {
      final targetMs = ((target is num
                  ? target.toDouble()
                  : (target is String ? double.tryParse(target) ?? 0.0 : 0.0)) *
              60000)
          .toInt();

      if (targetMs > 0 &&
          accumulatedTime >= targetMs &&
          original.status != 'completed') {
        updatedData['status'] = 'completed';
        updatedData['completedAt'] = now;
      }
    }

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for skip
  static ActivityInstanceRecord createOptimisticSkippedInstance(
    ActivityInstanceRecord original, {
    String? notes,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateTime.now();

    updatedData['status'] = 'skipped';
    updatedData['skippedAt'] = now;
    updatedData['lastUpdated'] = now;

    if (notes != null) {
      updatedData['notes'] = notes;
    }

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for reschedule
  static ActivityInstanceRecord createOptimisticRescheduledInstance(
    ActivityInstanceRecord original, {
    required DateTime newDueDate,
    String? newDueTime,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    updatedData['dueDate'] = newDueDate;
    if (newDueTime != null) {
      updatedData['dueTime'] = newDueTime;
    }
    // If originalDueDate is not set, set it to the current dueDate (before change)
    // This preserves the anchor for recurrence calculations
    if (updatedData['originalDueDate'] == null) {
      updatedData['originalDueDate'] = original.dueDate;
    }
    updatedData['lastUpdated'] = now;

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for snooze
  static ActivityInstanceRecord createOptimisticSnoozedInstance(
    ActivityInstanceRecord original, {
    required DateTime snoozedUntil,
  }) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    updatedData['snoozedUntil'] = snoozedUntil;
    updatedData['lastUpdated'] = now;

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for unsnooze
  static ActivityInstanceRecord createOptimisticUnsnoozedInstance(
    ActivityInstanceRecord original,
  ) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    updatedData['snoozedUntil'] = null;
    updatedData['lastUpdated'] = now;

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }

  /// Create optimistic instance for general property updates (name, dueTime, dueDate, etc.)
  static ActivityInstanceRecord createOptimisticPropertyUpdateInstance(
    ActivityInstanceRecord original,
    Map<String, dynamic> propertyUpdates,
  ) {
    final updatedData = Map<String, dynamic>.from(original.snapshotData);
    final now = DateService.currentDate;

    // Apply all property updates
    updatedData.addAll(propertyUpdates);
    updatedData['lastUpdated'] = now;

    // Mark as optimistic
    updatedData['_optimistic'] = true;

    return ActivityInstanceRecord.getDocumentFromData(
      updatedData,
      original.reference,
    );
  }
}
