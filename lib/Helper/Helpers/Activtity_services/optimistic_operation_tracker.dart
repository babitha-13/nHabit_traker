import 'dart:math';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';

/// Tracks optimistic operations for reconciliation and rollback
class OptimisticOperationTracker {
  static final Map<String, OptimisticOperation> _pendingOperations = {};
  static final Random _random = Random();
  static const Duration _operationTimeout = Duration(seconds: 30);

  /// Generate unique operation ID
  static String generateOperationId() {
    return '${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
  }

  /// Cancel pending operation for an instance (used when new conflicting operation starts)
  static void cancelPendingOperationForInstance(String instanceId) {
    final operation = getPendingOperation(instanceId);
    if (operation != null) {
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
    ];
    return conflictingPairs.any((pair) =>
        (pair[0] == type1 && pair[1] == type2) ||
        (pair[0] == type2 && pair[1] == type1));
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
      rollbackOperation(operationId);
    }
  }

  /// Track an optimistic operation
  static void trackOperation(
    String operationId, {
    required String instanceId,
    required String
        operationType, // 'complete', 'uncomplete', 'progress', 'skip', 'reschedule', 'snooze', 'unsnooze'
    required ActivityInstanceRecord optimisticInstance,
    required ActivityInstanceRecord originalInstance,
  }) {
    // Clean up stale operations before tracking new one
    cleanupStaleOperations();

    // Check for existing operation on same instance
    final existingOperation = getPendingOperation(instanceId);
    if (existingOperation != null) {
      // If operations conflict, cancel old operation
      if (_areOperationsConflicting(
          existingOperation.operationType, operationType)) {
        rollbackOperation(existingOperation.operationId);
      }
      // If compatible (e.g., progress updates), allow both but old one will be superseded
    }

    _pendingOperations[operationId] = OptimisticOperation(
      operationId: operationId,
      instanceId: instanceId,
      operationType: operationType,
      optimisticInstance: optimisticInstance,
      originalInstance: originalInstance,
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
      // Broadcast rollback event with original instance for restoration
      NotificationCenter.post('instanceUpdateRollback', {
        'operationId': operationId,
        'instanceId': operation.instanceId,
        'operationType': operation.operationType,
        'originalInstance': operation.originalInstance,
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
