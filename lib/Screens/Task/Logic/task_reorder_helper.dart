import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';

class TaskReorderHelper {
  static Future<void> handleReorder({
    required int oldIndex,
    required int newIndex,
    required String sectionKey,
    required Map<String, List<dynamic>> bucketedItems,
    required List<ActivityInstanceRecord> taskInstances,
    required Set<String> reorderingInstanceIds,
    required Function(List<ActivityInstanceRecord>) onTaskInstancesUpdate,
    required Function(Set<String>) onReorderingInstanceIdsUpdate,
    required Function() onCacheInvalidate,
    required Function() loadData,
    required BuildContext? context,
  }) async {
    final reorderingIds = <String>{};
    try {
      final items = bucketedItems[sectionKey]!;
      if (oldIndex < 0 ||
          oldIndex >= items.length ||
          newIndex < 0 ||
          newIndex > items.length) return;

      final reorderedItems = List<ActivityInstanceRecord>.from(items);
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }

      final movedItem = reorderedItems.removeAt(oldIndex);
      reorderedItems.insert(adjustedNewIndex, movedItem);

      // OPTIMISTIC UI UPDATE
      final updatedInstances = List<ActivityInstanceRecord>.from(taskInstances);
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];
        final instanceId = instance.reference.id;
        reorderingIds.add(instanceId);

        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['tasksOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );

        final taskIndex = updatedInstances
            .indexWhere((inst) => inst.reference.id == instanceId);
        if (taskIndex != -1) {
          updatedInstances[taskIndex] = updatedInstance;
        }
      }

      final updatedReorderingIds = Set<String>.from(reorderingInstanceIds);
      updatedReorderingIds.addAll(reorderingIds);

      onTaskInstancesUpdate(updatedInstances);
      onReorderingInstanceIdsUpdate(updatedReorderingIds);
      onCacheInvalidate();

      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'tasks',
        oldIndex,
        adjustedNewIndex,
      );

      final finalReorderingIds = Set<String>.from(updatedReorderingIds);
      finalReorderingIds.removeAll(reorderingIds);
      onReorderingInstanceIdsUpdate(finalReorderingIds);
    } catch (e) {
      final finalReorderingIds = Set<String>.from(reorderingInstanceIds);
      finalReorderingIds.removeAll(reorderingIds);
      onReorderingInstanceIdsUpdate(finalReorderingIds);
      await loadData();
      if (context != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
