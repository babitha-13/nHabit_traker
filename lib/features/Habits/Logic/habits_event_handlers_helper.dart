import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';

class HabitsEventHandlersHelper {
  static void handleInstanceCreated({
    required dynamic param,
    required bool showCompleted,
    required List<ActivityInstanceRecord> habitInstances,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onHabitInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
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

    if (instance.templateCategoryType != 'habit') {
      return;
    }

    final updatedInstances = List<ActivityInstanceRecord>.from(habitInstances);
    final updatedOperations = Map<String, String>.from(optimisticOperations);
    final existingByIdIndex = updatedInstances
        .indexWhere((inst) => inst.reference.id == instance.reference.id);

    if (isOptimistic) {
      if (existingByIdIndex == -1) {
        updatedInstances.add(instance);
      } else {
        updatedInstances[existingByIdIndex] = instance;
      }
      if (operationId != null) {
        updatedOperations[operationId] = instance.reference.id;
      }
    } else {
      if (operationId != null && updatedOperations.containsKey(operationId)) {
        final optimisticId = updatedOperations[operationId];
        final optimisticIndex = optimisticId == null
            ? -1
            : updatedInstances
                .indexWhere((inst) => inst.reference.id == optimisticId);
        if (optimisticIndex != -1) {
          updatedInstances[optimisticIndex] = instance;
        } else if (existingByIdIndex == -1) {
          updatedInstances.add(instance);
        } else {
          updatedInstances[existingByIdIndex] = instance;
        }
        updatedOperations.remove(operationId);
      } else {
        if (existingByIdIndex == -1) {
          updatedInstances.add(instance);
        } else {
          updatedInstances[existingByIdIndex] = instance;
        }
      }
    }

    if (!showCompleted && instance.status == 'completed') {
      updatedInstances
          .removeWhere((inst) => inst.reference.id == instance.reference.id);
    }

    onHabitInstancesUpdate(updatedInstances);
    onOptimisticOperationsUpdate(updatedOperations);
  }

  static void handleInstanceUpdated({
    required dynamic param,
    required bool showCompleted,
    required List<ActivityInstanceRecord> habitInstances,
    required Set<String> reorderingInstanceIds,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onHabitInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
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

    if (instance.templateCategoryType != 'habit') {
      return;
    }
    if (reorderingInstanceIds.contains(instance.reference.id)) {
      return;
    }

    final updatedInstances = List<ActivityInstanceRecord>.from(habitInstances);
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
        final existing = updatedInstances[index];
        final incomingLastUpdated = instance.lastUpdated;
        final existingLastUpdated = existing.lastUpdated;
        if (incomingLastUpdated != null &&
            existingLastUpdated != null &&
            incomingLastUpdated.isBefore(existingLastUpdated)) {
          return;
        }
        updatedInstances[index] = instance;
        if (operationId != null) {
          updatedOperations.remove(operationId);
        }
      }
      if (!showCompleted && instance.status == 'completed') {
        updatedInstances
            .removeWhere((inst) => inst.reference.id == instance.reference.id);
      }
    } else if (!isOptimistic) {
      updatedInstances.add(instance);
      if (!showCompleted && instance.status == 'completed') {
        updatedInstances
            .removeWhere((inst) => inst.reference.id == instance.reference.id);
      }
    }

    onHabitInstancesUpdate(updatedInstances);
    onOptimisticOperationsUpdate(updatedOperations);
  }

  static void handleRollback({
    required dynamic param,
    required List<ActivityInstanceRecord> habitInstances,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onHabitInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
    required Function(String) revertOptimisticUpdate,
  }) {
    if (param is! Map) {
      return;
    }

    final operationId = param['operationId'] as String?;
    final instanceId = param['instanceId'] as String?;
    final operationType = param['operationType'] as String?;
    final originalInstance =
        param['originalInstance'] as ActivityInstanceRecord?;
    final optimisticInstance =
        param['optimisticInstance'] as ActivityInstanceRecord?;

    if (operationId == null || !optimisticOperations.containsKey(operationId)) {
      return;
    }

    final updatedInstances = List<ActivityInstanceRecord>.from(habitInstances);
    final updatedOperations = Map<String, String>.from(optimisticOperations);
    final optimisticInstanceId = updatedOperations[operationId];
    updatedOperations.remove(operationId);

    if (operationType == 'create') {
      final idToRemove = optimisticInstanceId ??
          optimisticInstance?.reference.id ??
          instanceId;
      if (idToRemove != null && idToRemove.isNotEmpty) {
        updatedInstances.removeWhere((inst) => inst.reference.id == idToRemove);
      }
    } else if (originalInstance != null) {
      final primaryId = instanceId ?? originalInstance.reference.id;
      final index =
          updatedInstances.indexWhere((inst) => inst.reference.id == primaryId);
      if (index != -1) {
        updatedInstances[index] = originalInstance;
      } else if (optimisticInstanceId != null) {
        final fallbackIndex = updatedInstances
            .indexWhere((inst) => inst.reference.id == optimisticInstanceId);
        if (fallbackIndex != -1) {
          updatedInstances[fallbackIndex] = originalInstance;
        }
      }
    } else {
      final fallbackId = instanceId ?? optimisticInstanceId;
      if (fallbackId != null) {
        onOptimisticOperationsUpdate(updatedOperations);
        revertOptimisticUpdate(fallbackId);
        return;
      }
    }

    onHabitInstancesUpdate(updatedInstances);
    onOptimisticOperationsUpdate(updatedOperations);
  }

  static void handleInstanceDeleted({
    required dynamic param,
    required List<ActivityInstanceRecord> habitInstances,
    required Map<String, String> optimisticOperations,
    required Function(List<ActivityInstanceRecord>) onHabitInstancesUpdate,
    required Function(Map<String, String>) onOptimisticOperationsUpdate,
  }) {
    ActivityInstanceRecord? instance;
    String? instanceId;

    if (param is ActivityInstanceRecord) {
      instance = param;
      instanceId = param.reference.id;
    } else if (param is Map) {
      if (param['instance'] is ActivityInstanceRecord) {
        instance = param['instance'] as ActivityInstanceRecord;
        instanceId = instance.reference.id;
      } else if (param['instanceId'] is String) {
        instanceId = param['instanceId'] as String;
      }
    }

    if (instance != null && instance.templateCategoryType != 'habit') {
      return;
    }
    if (instanceId == null || instanceId.isEmpty) {
      return;
    }

    final updatedInstances = List<ActivityInstanceRecord>.from(habitInstances)
      ..removeWhere((inst) => inst.reference.id == instanceId);
    final updatedOperations = Map<String, String>.from(optimisticOperations)
      ..removeWhere((_, value) => value == instanceId);

    onHabitInstancesUpdate(updatedInstances);
    onOptimisticOperationsUpdate(updatedOperations);
  }

  static Future<void> revertOptimisticUpdate({
    required String instanceId,
    required List<ActivityInstanceRecord> habitInstances,
    required Function(List<ActivityInstanceRecord>) onHabitInstancesUpdate,
  }) async {
    try {
      final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceId,
      );
      final updatedInstances =
          List<ActivityInstanceRecord>.from(habitInstances);
      final index = updatedInstances
          .indexWhere((inst) => inst.reference.id == instanceId);
      if (index != -1) {
        updatedInstances[index] = updatedInstance;
        onHabitInstancesUpdate(updatedInstances);
      }
    } catch (_) {
      // Non-critical: next repository refresh will converge state.
    }
  }
}
