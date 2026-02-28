import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';

/// Helper class for handling instance events in queue page
class QueueInstanceHandlers {
  static bool _isQueueType(String? type) {
    final normalized = (type ?? '').trim().toLowerCase();
    return normalized == 'task' || normalized == 'habit';
  }

  static bool _shouldTrackQueueInstance(ActivityInstanceRecord instance) {
    return instance.isActive && _isQueueType(instance.templateCategoryType);
  }

  /// Update instance in local state
  static void updateInstanceInLocalState(
    List<ActivityInstanceRecord> instances,
    ActivityInstanceRecord updatedInstance,
  ) {
    final index = instances.indexWhere(
        (inst) => inst.reference.id == updatedInstance.reference.id);
    if (!_shouldTrackQueueInstance(updatedInstance)) {
      if (index != -1) {
        instances.removeAt(index);
      }
      return;
    }
    if (index != -1) {
      instances[index] = updatedInstance;
    }
  }

  /// Remove instance from local state
  static void removeInstanceFromLocalState(
    List<ActivityInstanceRecord> instances,
    ActivityInstanceRecord deletedInstance,
  ) {
    instances.removeWhere(
        (inst) => inst.reference.id == deletedInstance.reference.id);
  }

  /// Handle instance created event
  static void handleInstanceCreated(
    List<ActivityInstanceRecord> instances,
    ActivityInstanceRecord instance, {
    Map<String, String>? optimisticOperations,
    String? operationId,
    bool isOptimistic = false,
  }) {
    if (!_shouldTrackQueueInstance(instance)) return;

    // Check if instance already exists to prevent duplicates
    final exists =
        instances.any((inst) => inst.reference.id == instance.reference.id);

    if (exists) return;

    if (isOptimistic) {
      // Optimistic creation: Add and track operation
      instances.add(instance);
      if (operationId != null && optimisticOperations != null) {
        optimisticOperations[operationId] = instance.reference.id;
      }
    } else {
      // Reconciled creation: Check if we have a pending optimistic operation
      if (operationId != null &&
          optimisticOperations != null &&
          optimisticOperations.containsKey(operationId)) {
        final tempId = optimisticOperations[operationId];
        final tempIndex =
            instances.indexWhere((inst) => inst.reference.id == tempId);

        if (tempIndex != -1) {
          // Replace optimistic instance with real one
          instances[tempIndex] = instance;
          optimisticOperations.remove(operationId);
          return;
        }
      }

      // Fallback: If no optimistic operation found, just add
      instances.add(instance);
    }
  }

  /// Handle instance updated event
  static void handleInstanceUpdated(
    List<ActivityInstanceRecord> instances,
    dynamic param,
    Set<String> reorderingInstanceIds,
    Map<String, String> optimisticOperations,
  ) {
    // Handle both optimistic and reconciled updates
    ActivityInstanceRecord instance;
    bool isOptimistic = false;
    String? operationId;

    if (param is Map) {
      instance = param['instance'] as ActivityInstanceRecord;
      isOptimistic = param['isOptimistic'] as bool? ?? false;
      operationId = param['operationId'] as String?;
    } else if (param is ActivityInstanceRecord) {
      // Backward compatibility: handle old format
      instance = param;
    } else {
      return;
    }

    // Skip updates for instances currently being reordered to prevent stale data overwrites
    if (reorderingInstanceIds.contains(instance.reference.id)) {
      return;
    }

    final index = instances
        .indexWhere((inst) => inst.reference.id == instance.reference.id);

    // Never allow non-queue types (or inactive items) to remain in queue state.
    if (!_shouldTrackQueueInstance(instance)) {
      if (index != -1) {
        instances.removeAt(index);
      }
      if (operationId != null) {
        optimisticOperations.remove(operationId);
      }
      return;
    }

    if (index != -1) {
      if (isOptimistic) {
        // Store optimistic state with operation ID for later reconciliation
        instances[index] = instance;
        if (operationId != null) {
          optimisticOperations[operationId] = instance.reference.id;
        }
      } else {
        // Ignore stale non-optimistic updates that are older than the currently held instance
        final existing = instances[index];
        final incomingLastUpdated = instance.lastUpdated;
        final existingLastUpdated = existing.lastUpdated;
        if (incomingLastUpdated != null &&
            existingLastUpdated != null &&
            incomingLastUpdated.isBefore(existingLastUpdated)) {
          // This is a stale update - ignore it
          return;
        }

        // Reconciled update - replace optimistic state
        instances[index] = instance;
        if (operationId != null) {
          optimisticOperations.remove(operationId);
        }
      }
    } else if (!isOptimistic) {
      // New instance from backend (not optimistic) - add it
      instances.add(instance);
    }
  }

  /// Handle rollback event
  static void handleRollback(
    List<ActivityInstanceRecord> instances,
    dynamic param,
    Map<String, String> optimisticOperations,
  ) {
    if (param is Map) {
      final operationId = param['operationId'] as String?;
      final instanceId = param['instanceId'] as String?;
      final originalInstance =
          param['originalInstance'] as ActivityInstanceRecord?;

      if (operationId != null &&
          optimisticOperations.containsKey(operationId)) {
        optimisticOperations.remove(operationId);
        if (originalInstance != null) {
          if (!_shouldTrackQueueInstance(originalInstance)) {
            instances.removeWhere((inst) => inst.reference.id == instanceId);
            return;
          }
          // Restore from original state
          final index =
              instances.indexWhere((inst) => inst.reference.id == instanceId);
          if (index != -1) {
            instances[index] = originalInstance;
          }
        } else if (instanceId != null) {
          // Fallback to reloading from backend - this needs to be handled by the page
          // as it requires async operation
        }
      }
    }
  }

  /// Revert optimistic update by fetching from backend
  static Future<ActivityInstanceRecord?> revertOptimisticUpdate(
      String instanceId) async {
    try {
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      return updatedInstance;
    } catch (e) {
      // Error reverting - non-critical, will be fixed on next data load
      return null;
    }
  }

  /// Handle instance deleted event
  static void handleInstanceDeleted(
    List<ActivityInstanceRecord> instances,
    ActivityInstanceRecord instance,
  ) {
    instances.removeWhere((inst) => inst.reference.id == instance.reference.id);
  }
}
