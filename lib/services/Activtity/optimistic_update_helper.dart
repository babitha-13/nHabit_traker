import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';

/// Helper class for executing operations with optimistic updates
/// Reduces boilerplate code for the common pattern:
/// 1. Create optimistic instance
/// 2. Generate operation ID
/// 3. Track operation
/// 4. Broadcast optimistically
/// 5. Perform backend update
/// 6. Reconcile
/// 7. Rollback on error
class OptimisticUpdateHelper {
  /// Execute an operation with optimistic update pattern
  ///
  /// [originalInstance] - The original instance before the update
  /// [createOptimisticInstance] - Function to create the optimistic instance
  /// [backendUpdate] - Async function that performs the backend update
  /// [operationType] - Type of operation ('complete', 'uncomplete', 'progress', etc.)
  ///
  /// Returns the updated instance after reconciliation
  static Future<ActivityInstanceRecord> executeWithOptimisticUpdate({
    required ActivityInstanceRecord originalInstance,
    required ActivityInstanceRecord Function() createOptimisticInstance,
    required Future<ActivityInstanceRecord> Function() backendUpdate,
    required String operationType,
  }) async {
    // 1. Create optimistic instance
    final optimisticInstance = createOptimisticInstance();

    // 2. Generate operation ID
    final operationId = OptimisticOperationTracker.generateOperationId();

    // 3. Track operation
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: originalInstance.reference.id,
      operationType: operationType,
      optimisticInstance: optimisticInstance,
      originalInstance: originalInstance,
    );

    // 4. Broadcast optimistically (IMMEDIATE)
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
      optimisticInstance,
      operationId,
    );

    try {
      // 5. Perform backend update
      final updatedInstance = await backendUpdate();

      // 6. Reconcile with actual data
      OptimisticOperationTracker.reconcileOperation(
        operationId,
        updatedInstance,
      );

      return updatedInstance;
    } catch (e) {
      // 7. Rollback on error
      OptimisticOperationTracker.rollbackOperation(operationId);
      rethrow;
    }
  }

  /// Execute an operation with optimistic update pattern (simplified version)
  /// This version doesn't return the updated instance, useful when you don't need it
  static Future<void> executeWithOptimisticUpdateVoid({
    required ActivityInstanceRecord originalInstance,
    required ActivityInstanceRecord Function() createOptimisticInstance,
    required Future<void> Function() backendUpdate,
    required String operationType,
  }) async {
    // 1. Create optimistic instance
    final optimisticInstance = createOptimisticInstance();

    // 2. Generate operation ID
    final operationId = OptimisticOperationTracker.generateOperationId();

    // 3. Track operation
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: originalInstance.reference.id,
      operationType: operationType,
      optimisticInstance: optimisticInstance,
      originalInstance: originalInstance,
    );

    // 4. Broadcast optimistically (IMMEDIATE)
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
      optimisticInstance,
      operationId,
    );

    try {
      // 5. Perform backend update
      await backendUpdate();

      // Note: For void version, we can't reconcile with actual instance
      // The caller should handle reconciliation if needed
      // or use the non-void version
    } catch (e) {
      // 7. Rollback on error
      OptimisticOperationTracker.rollbackOperation(operationId);
      rethrow;
    }
  }
}
