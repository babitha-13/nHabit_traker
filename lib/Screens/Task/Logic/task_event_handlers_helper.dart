import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';

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
      final matchesCategory = categoryName == null ||
          instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations = Map<String, String>.from(optimisticOperations);

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
      final matchesCategory = categoryName == null ||
          instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations = Map<String, String>.from(optimisticOperations);

        final index = updatedInstances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);

        if (index != -1) {
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
      final originalInstance =
          param['originalInstance'] as ActivityInstanceRecord?;

      if (operationId != null &&
          optimisticOperations.containsKey(operationId)) {
        final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
        final updatedOperations = Map<String, String>.from(optimisticOperations);

        updatedOperations.remove(operationId);
        if (originalInstance != null) {
          final index = updatedInstances
              .indexWhere((inst) => inst.reference.id == instanceId);
          if (index != -1) {
            updatedInstances[index] = originalInstance;
          }
        } else if (instanceId != null) {
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
      final matchesCategory = categoryName == null ||
          instance.templateCategoryName == categoryName;
      if (matchesCategory) {
        final updatedInstances = taskInstances.where(
          (inst) => inst.reference.id != instance.reference.id,
        ).toList();
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
    loadDataSilently();
  }

  static void removeInstanceFromLocalState({
    required ActivityInstanceRecord deletedInstance,
    required List<ActivityInstanceRecord> taskInstances,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function() onCacheInvalidate,
  }) {
    final updatedInstances = taskInstances.where(
      (inst) => inst.reference.id != deletedInstance.reference.id,
    ).toList();
    onTaskInstancesUpdate(updatedInstances);
    onCacheInvalidate();
  }
}
