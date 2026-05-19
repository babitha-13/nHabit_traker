import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Queue/Helpers/queue_mode_order_seeder.dart';
import 'package:habit_tracker/features/Queue/Helpers/queue_sort_state_manager.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';

/// Helper class for handling reordering in queue page
class QueueReorderHandler {
  /// Handle reordering of items within a section
  static Future<void> handleReorder({
    required List<ActivityInstanceRecord> items,
    required int oldIndex,
    required int newIndex,
    required List<ActivityInstanceRecord> allInstances,
    required Set<String> reorderingInstanceIds,
    required QueueSortState currentSort,
    required String sectionKey,
    required Function(List<ActivityInstanceRecord>, Set<String>)
        onOptimisticUpdate,
  }) async {
    final pageType =
        QueueModeOrderSeeder.pageTypeForSortType(currentSort.sortType);
    final fieldName = InstanceOrderService.orderFieldFor(pageType);
    // Allow dropping at the end (newIndex can equal items.length)
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return;
    }

    // Create a copy of the items list for reordering
    final reorderedItems = List<ActivityInstanceRecord>.from(items);
    // Adjust newIndex for the case where we're moving down
    int adjustedNewIndex = newIndex;
    if (oldIndex < newIndex) {
      adjustedNewIndex -= 1;
    }
    // Get the item being moved
    final movedItem = reorderedItems.removeAt(oldIndex);
    reorderedItems.insert(adjustedNewIndex, movedItem);

    // Update order values in the instances list
    final updatedInstances = List<ActivityInstanceRecord>.from(allInstances);
    final reorderingIds = <String>{};

    for (int i = 0; i < reorderedItems.length; i++) {
      final instance = reorderedItems[i];
      final instanceId = instance.reference.id;
      reorderingIds.add(instanceId);
      final index = updatedInstances
          .indexWhere((inst) => inst.reference.id == instanceId);
      if (index != -1) {
        // Optimistic snapshot: write the new index to the active mode's field.
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData[fieldName] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );
        updatedInstances[index] = updatedInstance;
      }
    }

    // Update UI immediately (Optimistic Update)
    onOptimisticUpdate(updatedInstances, reorderingIds);

    // Perform database update in background
    await InstanceOrderService.reorderInstancesInSection(
      reorderedItems,
      pageType,
      oldIndex,
      adjustedNewIndex,
    );
  }
}
