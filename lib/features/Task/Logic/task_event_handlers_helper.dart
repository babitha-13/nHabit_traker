import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';

class TaskEventHandlersHelper {
  static void handleInstanceCreated({
    required dynamic param,
    required String? categoryName,
    required List<ActivityInstanceRecord> taskInstances,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
    required Function() onCacheInvalidate,
  }) {
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;

    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      instance = param;
    } else {
      return;
    }

    if (instance.templateCategoryType == 'task') {
      final matchesCategory =
          categoryName == null || instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances =
            List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations =
            Map<String, String>.from(optimisticOperations);

        if (isOptimistic) {
          updatedInstances.add(instance);
          if (operationId != null) {
            updatedOperations[operationId] = instance.reference.id;
          }
        } else {
          if (operationId != null &&
              updatedOperations.containsKey(operationId)) {
            final optimisticId = updatedOperations[operationId];
            final index = updatedInstances.indexWhere(
              (inst) => inst.reference.id == optimisticId,
            );
            if (index != -1) {
              updatedInstances[index] = instance;
            } else {
              updatedInstances.add(instance);
            }
            updatedOperations.remove(operationId);
          } else {
            final exists = updatedInstances.any(
              (inst) => inst.reference.id == instance.reference.id,
            );
            if (!exists) {
              updatedInstances.add(instance);
            }
          }
        }

        onTaskInstancesUpdate(updatedInstances);
        onOptimisticOperationsUpdate(updatedOperations);
        onCacheInvalidate();
      }
    }
  }

  static void handleInstanceUpdated({
    required dynamic param,
    required String? categoryName,
    required List<ActivityInstanceRecord> taskInstances,
    required Set<String> reorderingInstanceIds,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
    required Function() onCacheInvalidate,
  }) {
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;

    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      instance = param;
    } else {
      return;
    }

    if (reorderingInstanceIds.contains(instance.reference.id)) {
      return;
    }

    if (instance.templateCategoryType == 'task') {
      final matchesCategory =
          categoryName == null || instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances =
            List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations =
            Map<String, String>.from(optimisticOperations);

        final index = updatedInstances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);

        if (index != -1) {
          // Ignore stale non-optimistic updates that are older than the currently held instance.
          // This prevents temporary flicker from out-of-order events (e.g., pending -> completed -> pending -> completed).
          if (!isOptimistic) {
            final existing = updatedInstances[index];
            final incomingLastUpdated = instance.lastUpdated;
            final existingLastUpdated = existing.lastUpdated;
            if (incomingLastUpdated != null &&
                existingLastUpdated != null &&
                incomingLastUpdated.isBefore(existingLastUpdated)) {
              return;
            }
          }

          if (isOptimistic) {
            updatedInstances[index] = instance;
            if (operationId != null) {
              updatedOperations[operationId] = instance.reference.id;
            }
          } else {
            updatedInstances[index] = instance;
            if (operationId != null) {
              updatedOperations.remove(operationId);
            }
          }
        } else if (!isOptimistic) {
          updatedInstances.add(instance);
        }

        onTaskInstancesUpdate(updatedInstances);
        onOptimisticOperationsUpdate(updatedOperations);
        onCacheInvalidate();
      }
    }
  }

  static void handleRollback({
    required dynamic param,
    required List<ActivityInstanceRecord> taskInstances,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
    required Function() onCacheInvalidate,
    required Function(String) revertOptimisticUpdate,
  }) {
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      final operationType = param['operationType'] as String?;
      final originalInstance =
          param['originalInstance'] as ActivityInstanceRecord?;
      final optimisticInstance =
          param['optimisticInstance'] as ActivityInstanceRecord?;

      if (operationId != null &&
          optimisticOperations.containsKey(operationId)) {
        final updatedInstances =
            List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations =
            Map<String, String>.from(optimisticOperations);

        // Get the optimistic instance ID from the operations map
        final optimisticInstanceId = updatedOperations[operationId];
        updatedOperations.remove(operationId);

        // For creation operations, remove the optimistic instance
        if (operationType == 'create') {
          // Try multiple strategies to find and remove the optimistic instance
          bool removed = false;

          // Strategy 1: Use optimistic instance ID from operations map
          if (optimisticInstanceId != null) {
            final removedCount = updatedInstances.length;
            updatedInstances.removeWhere(
              (inst) => inst.reference.id == optimisticInstanceId,
            );
            removed = updatedInstances.length < removedCount;
          }

          // Strategy 2: Use optimistic instance from rollback event (for temp IDs)
          if (!removed && optimisticInstance != null) {
            final removedCount = updatedInstances.length;
            updatedInstances.removeWhere(
              (inst) => inst.reference.id == optimisticInstance.reference.id,
            );
            removed = updatedInstances.length < removedCount;
          }

          // Strategy 3: Try to find by instanceId (may be temp ID)
          if (!removed && instanceId != null) {
            final removedCount = updatedInstances.length;
            updatedInstances.removeWhere(
              (inst) => inst.reference.id == instanceId,
            );
            removed = updatedInstances.length < removedCount;
          }
        } else if (originalInstance != null && instanceId != null) {
          // For update operations, restore original instance
          final index = updatedInstances
              .indexWhere((inst) => inst.reference.id == instanceId);
          if (index != -1) {
            updatedInstances[index] = originalInstance;
          } else if (optimisticInstanceId != null) {
            // Fallback: try optimistic instance ID if instanceId doesn't match
            final index2 = updatedInstances.indexWhere(
                (inst) => inst.reference.id == optimisticInstanceId);
            if (index2 != -1) {
              updatedInstances[index2] = originalInstance;
            }
          }
        } else if (instanceId != null) {
          // Fallback: try to revert by fetching from backend
          revertOptimisticUpdate(instanceId);
        }

        onTaskInstancesUpdate(updatedInstances);
        onOptimisticOperationsUpdate(updatedOperations);
        onCacheInvalidate();
      }
    }
  }

  static Future<void> revertOptimisticUpdate({
    required String instanceId,
    required List<ActivityInstanceRecord> taskInstances,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function() onCacheInvalidate,
  }) async {
    try {
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
      final index = updatedInstances
          .indexWhere((inst) => inst.reference.id == instanceId);
      if (index != -1) {
        updatedInstances[index] = updatedInstance;
        onTaskInstancesUpdate(updatedInstances);
        onCacheInvalidate();
      }
    } catch (e) {
      // Error reverting - non-critical, will be fixed on next data load
    }
  }

  static void handleInstanceDeleted({
    required ActivityInstanceRecord instance,
    required String? categoryName,
    required List<ActivityInstanceRecord> taskInstances,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function() onCacheInvalidate,
  }) {
    if (instance.templateCategoryType == 'task') {
      final matchesCategory =
          categoryName == null || instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances = taskInstances
            .where(
              (inst) => inst.reference.id != instance.reference.id,
            )
            .toList();
        onTaskInstancesUpdate(updatedInstances);
        onCacheInvalidate();
      }
    }
  }

  static void updateInstanceInLocalState({
    required ActivityInstanceRecord updatedInstance,
    required List<ActivityInstanceRecord> taskInstances,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function() onCacheInvalidate,
    required Function() loadDataSilently,
  }) {
    final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
    final index = updatedInstances.indexWhere(
        (inst) => inst.reference.id == updatedInstance.reference.id);
    if (index != -1) {
      updatedInstances[index] = updatedInstance;
      onTaskInstancesUpdate(updatedInstances);
      onCacheInvalidate();
    }
    // Note: No need to reload from backend - optimistic update system handles synchronization
    // Removed: loadDataSilently(); - This was causing status flips by reloading stale data
  }

  static void removeInstanceFromLocalState({
    required ActivityInstanceRecord deletedInstance,
    required List<ActivityInstanceRecord> taskInstances,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function() onCacheInvalidate,
  }) {
    final updatedInstances = taskInstances
        .where(
          (inst) => inst.reference.id != deletedInstance.reference.id,
        )
        .toList();
    onTaskInstancesUpdate(updatedInstances);
    onCacheInvalidate();
  }
}
