import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';

/// Tracks optimistic operations for reconciliation and rollback
class OptimisticOperationTracker {
  static final Map<String, OptimisticOperation> _pendingOperations = {};
  static final Random _random = Random();

  /// Generate unique operation ID
  static String generateOperationId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
  }

  /// Track an optimistic operation
  static void trackOperation(
    String operationId, {
    required String instanceId,
    required String operationType, // 'complete', 'uncomplete', 'progress', 'skip', 'reschedule', 'snooze', 'unsnooze'
    required ActivityInstanceRecord optimisticInstance,
  }) {
    _pendingOperations[operationId] = OptimisticOperation(
      operationId: operationId,
      instanceId: instanceId,
      operationType: operationType,
      optimisticInstance: optimisticInstance,
      timestamp: DateTime.now(),
    );
  }

  /// Reconcile operation with actual backend data
  static void reconcileOperation(
    String operationId,
    ActivityInstanceRecord actualInstance,
  ) {
    final operation = _pendingOperations.remove(operationId);
    if (operation != null) {
      InstanceEvents.broadcastInstanceUpdatedReconciled(
        actualInstance,
        operationId,
      );
    }
  }

  /// Reconcile instance creation with actual backend data
  static void reconcileInstanceCreation(
    String operationId,
    ActivityInstanceRecord actualInstance,
  ) {
    final operation = _pendingOperations.remove(operationId);
    if (operation != null) {
      InstanceEvents.broadcastInstanceCreatedReconciled(
        actualInstance,
        operationId,
      );
    }
  }

  /// Rollback an optimistic operation
  static void rollbackOperation(String operationId) {
    final operation = _pendingOperations.remove(operationId);
    if (operation != null) {
      // Broadcast rollback event
      NotificationCenter.post('instanceUpdateRollback', {
        'operationId': operationId,
        'instanceId': operation.instanceId,
        'operationType': operation.operationType,
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
}

/// Represents an optimistic operation
class OptimisticOperation {
  final String operationId;
  final String instanceId;
  final String operationType;
  final ActivityInstanceRecord optimisticInstance;
  final DateTime timestamp;

  OptimisticOperation({
    required this.operationId,
    required this.instanceId,
    required this.operationType,
    required this.optimisticInstance,
    required this.timestamp,
  });
}

