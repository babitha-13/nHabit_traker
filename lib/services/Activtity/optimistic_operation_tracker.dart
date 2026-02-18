import 'dart:async';
import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/diagnostics/calendar_optimistic_trace_logger.dart';

/// Tracks optimistic operations for reconciliation and rollback
class OptimisticOperationTracker {
  static final Map<String, OptimisticOperation> _pendingOperations = {};
  static final Random _random = Random();
  static const Duration _operationTimeout = Duration(seconds: 30);
  static const int _reconcileStalenessToleranceMs = 1200;
  static const Duration _cleanupInterval =
      Duration(seconds: 10); // Check every 10 seconds
  static Timer? _cleanupTimer;

  static int _versionMs(ActivityInstanceRecord instance) {
    final lastUpdatedMs = instance.lastUpdated?.millisecondsSinceEpoch;
    if (lastUpdatedMs != null && lastUpdatedMs > 0) {
      return lastUpdatedMs;
    }
    final createdMs = instance.createdTime?.millisecondsSinceEpoch;
    if (createdMs != null && createdMs > 0) {
      return createdMs;
    }
    return 0;
  }

  static bool _valuesEqual(dynamic a, dynamic b) {
    if (a is num && b is num) {
      return a.toDouble() == b.toDouble();
    }
    return a == b;
  }

  static String _timeLogSignature(ActivityInstanceRecord instance) {
    if (instance.timeLogSessions.isEmpty) {
      return '';
    }
    final segments = <String>[];
    for (final raw in instance.timeLogSessions) {
      final start = raw['startTime'];
      final end = raw['endTime'];
      final duration = raw['durationMilliseconds'];
      final startMs = start is DateTime ? start.millisecondsSinceEpoch : 0;
      final endMs = end is DateTime ? end.millisecondsSinceEpoch : 0;
      final durationMs = duration is num ? duration.toInt() : 0;
      segments.add('$startMs-$endMs-$durationMs');
    }
    return segments.join('|');
  }

  static bool _isSemanticProgressReconcileStale({
    required OptimisticOperation operation,
    required ActivityInstanceRecord actualInstance,
  }) {
    final original = operation.originalInstance;
    final optimistic = operation.optimisticInstance;

    final sessionsChanged =
        _timeLogSignature(original) != _timeLogSignature(optimistic);
    final totalLoggedChanged =
        original.totalTimeLogged != optimistic.totalTimeLogged;
    final accumulatedChanged =
        original.accumulatedTime != optimistic.accumulatedTime;
    final currentValueChanged =
        !_valuesEqual(original.currentValue, optimistic.currentValue);
    final statusChanged = original.status != optimistic.status;

    final hasTrackedChange = sessionsChanged ||
        totalLoggedChanged ||
        accumulatedChanged ||
        currentValueChanged ||
        statusChanged;
    if (!hasTrackedChange) {
      return false;
    }

    final matchesOptimistic = (!sessionsChanged ||
            _timeLogSignature(actualInstance) ==
                _timeLogSignature(optimistic)) &&
        (!totalLoggedChanged ||
            actualInstance.totalTimeLogged == optimistic.totalTimeLogged) &&
        (!accumulatedChanged ||
            actualInstance.accumulatedTime == optimistic.accumulatedTime) &&
        (!currentValueChanged ||
            _valuesEqual(
                actualInstance.currentValue, optimistic.currentValue)) &&
        (!statusChanged || actualInstance.status == optimistic.status);
    if (matchesOptimistic) {
      return false;
    }

    final optimisticMs = _versionMs(optimistic) > 0
        ? _versionMs(optimistic)
        : operation.timestamp.millisecondsSinceEpoch;
    final actualMs = _versionMs(actualInstance);
    if (actualMs <= 0) {
      return true;
    }
    return actualMs <= optimisticMs + _reconcileStalenessToleranceMs;
  }

  static String? _staleReconcileReason({
    required OptimisticOperation operation,
    required ActivityInstanceRecord actualInstance,
  }) {
    final optimisticMs = _versionMs(operation.optimisticInstance) > 0
        ? _versionMs(operation.optimisticInstance)
        : operation.timestamp.millisecondsSinceEpoch;
    final actualMs = _versionMs(actualInstance);
    if (actualMs <= 0) {
      if (_versionMs(operation.optimisticInstance) > 0) {
        return 'missing_actual_version';
      }
      final semanticStale = _isSemanticProgressReconcileStale(
        operation: operation,
        actualInstance: actualInstance,
      );
      if (semanticStale) {
        return 'semantic_stale_no_versions';
      }
      return null;
    }
    if (actualMs + _reconcileStalenessToleranceMs < optimisticMs) {
      return 'actual_older_than_optimistic';
    }
    final semanticStale = _isSemanticProgressReconcileStale(
      operation: operation,
      actualInstance: actualInstance,
    );
    if (semanticStale) {
      return 'semantic_stale';
    }
    return null;
  }

  static Map<String, Object?> _reconcileDebugFields({
    required OptimisticOperation operation,
    required ActivityInstanceRecord actualInstance,
  }) {
    final optimistic = operation.optimisticInstance;
    final original = operation.originalInstance;
    final optimisticMs = _versionMs(optimistic) > 0
        ? _versionMs(optimistic)
        : operation.timestamp.millisecondsSinceEpoch;
    final actualMs = _versionMs(actualInstance);
    return <String, Object?>{
      'opType': operation.operationType,
      'pendingCount': _pendingOperations.length,
      'optimisticMs': optimisticMs,
      'actualMs': actualMs,
      'originalStatus': original.status,
      'optimisticStatus': optimistic.status,
      'actualStatus': actualInstance.status,
      'originalSessions': original.timeLogSessions.length,
      'optimisticSessions': optimistic.timeLogSessions.length,
      'actualSessions': actualInstance.timeLogSessions.length,
      'originalTotalLogged': original.totalTimeLogged,
      'optimisticTotalLogged': optimistic.totalTimeLogged,
      'actualTotalLogged': actualInstance.totalTimeLogged,
      'originalAccumulated': original.accumulatedTime,
      'optimisticAccumulated': optimistic.accumulatedTime,
      'actualAccumulated': actualInstance.accumulatedTime,
      'originalCurrentValue': original.currentValue,
      'optimisticCurrentValue': optimistic.currentValue,
      'actualCurrentValue': actualInstance.currentValue,
    };
  }

  /// Generate unique operation ID
  static String generateOperationId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
  }

  /// Cancel pending operation for an instance (used when new conflicting operation starts)
  static void cancelPendingOperationForInstance(String instanceId) {
    final operation = getPendingOperation(instanceId);
    if (operation != null) {
      CalendarOptimisticTraceLogger.log(
        'cancel_pending_for_instance',
        source: 'optimistic_tracker',
        operationId: operation.operationId,
        instanceId: instanceId,
        instance: operation.optimisticInstance,
        extras: <String, Object?>{
          'reason': 'new_operation_for_instance',
          'opType': operation.operationType,
        },
      );
      rollbackOperation(operation.operationId);
    }
  }

  /// Check if operation types conflict
  static bool _areOperationsConflicting(String type1, String type2) {
    final conflictingPairs = [
      ['complete', 'uncomplete'],
      ['complete', 'skip'],
      ['uncomplete', 'complete'],
      ['skip', 'complete'],
      ['create', 'create'], // Duplicate creation operations conflict
    ];
    return conflictingPairs.any((pair) =>
        (pair[0] == type1 && pair[1] == type2) ||
        (pair[0] == type2 && pair[1] == type1));
  }

  /// Check if there's a pending creation operation for the same template
  /// This prevents duplicate optimistic creations of the same instance
  static OptimisticOperation? getPendingCreationForTemplate(String templateId) {
    for (final operation in _pendingOperations.values) {
      if (operation.operationType == 'create' &&
          operation.optimisticInstance.templateId == templateId) {
        return operation;
      }
    }
    return null;
  }

  /// Clean up operations that are older than timeout
  static void cleanupStaleOperations() {
    final now = DateTime.now();
    final staleOperationIds = <String>[];

    _pendingOperations.forEach((operationId, operation) {
      if (now.difference(operation.timestamp) > _operationTimeout) {
        staleOperationIds.add(operationId);
      }
    });

    for (final operationId in staleOperationIds) {
      // Rollback stale operations
      final operation = _pendingOperations[operationId];
      if (operation != null) {
        CalendarOptimisticTraceLogger.log(
          'stale_operation_timeout',
          source: 'optimistic_tracker',
          operationId: operationId,
          instanceId: operation.instanceId,
          instance: operation.optimisticInstance,
          extras: <String, Object?>{
            'ageMs': now.difference(operation.timestamp).inMilliseconds,
            'timeoutMs': _operationTimeout.inMilliseconds,
            'opType': operation.operationType,
          },
        );
      }
      rollbackOperation(operationId);
    }
  }

  /// Start periodic cleanup timer to proactively clean up stale operations
  /// This prevents memory leaks when operations don't complete or reconcile
  static void startPeriodicCleanup() {
    // Cancel existing timer if any
    _cleanupTimer?.cancel();

    // Start new periodic timer
    _cleanupTimer = Timer.periodic(_cleanupInterval, (_) {
      cleanupStaleOperations();
    });
  }

  /// Stop periodic cleanup timer
  static void stopPeriodicCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// Track an optimistic operation
  static void trackOperation(
    String operationId, {
    required String instanceId,
    required String
        operationType, // 'complete', 'uncomplete', 'progress', 'skip', 'reschedule', 'snooze', 'unsnooze', 'create'
    required ActivityInstanceRecord optimisticInstance,
    required ActivityInstanceRecord originalInstance,
  }) {
    // Clean up stale operations before tracking new one
    cleanupStaleOperations();

    // For creation operations, check for duplicate creations of same template
    if (operationType == 'create') {
      final existingCreation =
          getPendingCreationForTemplate(optimisticInstance.templateId);
      if (existingCreation != null) {
        // Cancel previous creation operation to prevent duplicates
        CalendarOptimisticTraceLogger.log(
          'track_replaces_existing_create',
          source: 'optimistic_tracker',
          operationId: existingCreation.operationId,
          instanceId: existingCreation.instanceId,
          instance: existingCreation.optimisticInstance,
          extras: <String, Object?>{
            'newOp': operationId,
            'templateId': optimisticInstance.templateId,
          },
        );
        rollbackOperation(existingCreation.operationId);
      }
    } else {
      // For other operations, check for existing operation on same instance
      final existingOperation = getPendingOperation(instanceId);
      if (existingOperation != null) {
        // If operations conflict, cancel old operation
        if (_areOperationsConflicting(
            existingOperation.operationType, operationType)) {
          CalendarOptimisticTraceLogger.log(
            'track_conflict_replaces_existing',
            source: 'optimistic_tracker',
            operationId: existingOperation.operationId,
            instanceId: existingOperation.instanceId,
            instance: existingOperation.optimisticInstance,
            extras: <String, Object?>{
              'existingType': existingOperation.operationType,
              'incomingType': operationType,
              'newOp': operationId,
            },
          );
          rollbackOperation(existingOperation.operationId);
        }
        // If compatible (e.g., progress updates), allow both but old one will be superseded
      }
    }

    _pendingOperations[operationId] = OptimisticOperation(
      operationId: operationId,
      instanceId: instanceId,
      operationType: operationType,
      optimisticInstance: optimisticInstance,
      originalInstance: originalInstance,
      timestamp: DateTime.now(),
    );
    CalendarOptimisticTraceLogger.log(
      'track',
      source: 'optimistic_tracker',
      operationId: operationId,
      instanceId: instanceId,
      instance: optimisticInstance,
      extras: <String, Object?>{
        'opType': operationType,
        'pendingCount': _pendingOperations.length,
        'originalStatus': originalInstance.status,
      },
    );
  }

  /// Reconcile operation with actual backend data
  static void reconcileOperation(
    String operationId,
    ActivityInstanceRecord actualInstance,
  ) {
    final operation = _pendingOperations.remove(operationId);
    if (operation == null) {
      CalendarOptimisticTraceLogger.log(
        'reconcile_update_missing_operation',
        source: 'optimistic_tracker',
        operationId: operationId,
        instance: actualInstance,
      );
      return;
    }
    final staleReason = _staleReconcileReason(
      operation: operation,
      actualInstance: actualInstance,
    );
    if (staleReason != null) {
      // Backend write succeeded, but read payload is older than optimistic.
      // Keep optimistic UI and rely on subsequent refresh/event to converge.
      CalendarOptimisticTraceLogger.log(
        'reconcile_update_ignored_stale',
        source: 'optimistic_tracker',
        operationId: operationId,
        instanceId: operation.instanceId,
        instance: actualInstance,
        extras: <String, Object?>{
          'reason': staleReason,
          ..._reconcileDebugFields(
            operation: operation,
            actualInstance: actualInstance,
          ),
        },
      );
      return;
    }
    CalendarOptimisticTraceLogger.log(
      'reconcile_update_apply',
      source: 'optimistic_tracker',
      operationId: operationId,
      instanceId: operation.instanceId,
      instance: actualInstance,
      extras: <String, Object?>{
        ..._reconcileDebugFields(
          operation: operation,
          actualInstance: actualInstance,
        ),
      },
    );
    InstanceEvents.broadcastInstanceUpdatedReconciled(
      actualInstance,
      operationId,
    );
  }

  /// Reconcile instance creation with actual backend data
  static void reconcileInstanceCreation(
    String operationId,
    ActivityInstanceRecord actualInstance,
  ) {
    final operation = _pendingOperations.remove(operationId);
    if (operation == null) {
      CalendarOptimisticTraceLogger.log(
        'reconcile_create_missing_operation',
        source: 'optimistic_tracker',
        operationId: operationId,
        instance: actualInstance,
      );
      return;
    }
    final staleReason = _staleReconcileReason(
      operation: operation,
      actualInstance: actualInstance,
    );
    if (staleReason != null) {
      CalendarOptimisticTraceLogger.log(
        'reconcile_create_ignored_stale',
        source: 'optimistic_tracker',
        operationId: operationId,
        instanceId: operation.instanceId,
        instance: actualInstance,
        extras: <String, Object?>{
          'reason': staleReason,
          ..._reconcileDebugFields(
            operation: operation,
            actualInstance: actualInstance,
          ),
        },
      );
      return;
    }
    CalendarOptimisticTraceLogger.log(
      'reconcile_create_apply',
      source: 'optimistic_tracker',
      operationId: operationId,
      instanceId: operation.instanceId,
      instance: actualInstance,
      extras: <String, Object?>{
        ..._reconcileDebugFields(
          operation: operation,
          actualInstance: actualInstance,
        ),
      },
    );
    InstanceEvents.broadcastInstanceCreatedReconciled(
      actualInstance,
      operationId,
    );
  }

  /// Mark operation as successful without forcing a reconciled payload broadcast.
  static void completeOperationWithoutReconcile(String operationId) {
    final removed = _pendingOperations.remove(operationId);
    CalendarOptimisticTraceLogger.log(
      'complete_without_reconcile',
      source: 'optimistic_tracker',
      operationId: operationId,
      instanceId: removed?.instanceId,
      instance: removed?.optimisticInstance,
      extras: <String, Object?>{
        'removed': removed != null,
        'pendingCount': _pendingOperations.length,
        'opType': removed?.operationType ?? '-',
      },
    );
  }

  /// Rollback an optimistic operation
  static void rollbackOperation(String operationId) {
    final operation = _pendingOperations.remove(operationId);
    if (operation != null) {
      CalendarOptimisticTraceLogger.log(
        'rollback',
        source: 'optimistic_tracker',
        operationId: operationId,
        instanceId: operation.instanceId,
        instance: operation.optimisticInstance,
        extras: <String, Object?>{
          'opType': operation.operationType,
          'pendingCount': _pendingOperations.length,
        },
      );
      // Broadcast rollback event with original instance for restoration
      // Include optimistic instance for creation rollbacks (to identify temp instances)
      NotificationCenter.post('instanceUpdateRollback', {
        'operationId': operationId,
        'instanceId': operation.instanceId,
        'operationType': operation.operationType,
        'originalInstance': operation.originalInstance,
        'optimisticInstance':
            operation.optimisticInstance, // Help identify temp instances
      });
    }
  }

  /// Get pending operation for an instance
  static OptimisticOperation? getPendingOperation(String instanceId) {
    for (final operation in _pendingOperations.values) {
      if (operation.instanceId == instanceId) {
        return operation;
      }
    }
    return null;
  }

  /// Check if there's a pending operation for an instance
  static bool hasPendingOperation(String instanceId) {
    return getPendingOperation(instanceId) != null;
  }

  /// Clear all pending operations (for testing or cleanup)
  static void clearAll() {
    _pendingOperations.clear();
  }

  /// Get all pending operations (for debugging)
  static List<OptimisticOperation> getAllPendingOperations() {
    return _pendingOperations.values.toList();
  }

  static int pendingCount() {
    return _pendingOperations.length;
  }
}

/// Represents an optimistic operation
class OptimisticOperation {
  final String operationId;
  final String instanceId;
  final String operationType;
  final ActivityInstanceRecord optimisticInstance;
  final ActivityInstanceRecord originalInstance;
  final DateTime timestamp;

  OptimisticOperation({
    required this.operationId,
    required this.instanceId,
    required this.operationType,
    required this.optimisticInstance,
    required this.originalInstance,
    required this.timestamp,
  });
}
