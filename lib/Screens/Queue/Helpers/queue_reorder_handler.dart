import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';

/// Helper class for handling reordering in queue page
class QueueReorderHandler {
  /// Handle reordering of items within a section
  static Future<void> handleReorder({
    required List<ActivityInstanceRecord> items,
    required int oldIndex,
    required int newIndex,
    required List<ActivityInstanceRecord> allInstances,
    required Set<String> reorderingInstanceIds,
    required bool isSortActive,
    required String sectionKey,
    required Function(List<ActivityInstanceRecord>) onInstancesUpdate,
    required Function(Set<String>) onReorderingIdsUpdate,
    required Function() onCacheInvalidate,
    required Function() onLoadData,
    required BuildContext context,
  }) async {
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

    // Track reordering IDs locally
    final reorderingIds = <String>{};

    // Create optimistic updated instances list
    final updatedInstances = List<ActivityInstanceRecord>.from(allInstances);

    for (int i = 0; i < reorderedItems.length; i++) {
      final instance = reorderedItems[i];
      final instanceId = instance.reference.id;
      reorderingIds.add(instanceId);
      final index = updatedInstances
          .indexWhere((inst) => inst.reference.id == instanceId);
      if (index != -1) {
        // Create updated instance with new queue order by creating new data map
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['queueOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );
        updatedInstances[index] = updatedInstance;
      }
    }

    // Apply optimistic update
    final updatedReorderingIds = Set<String>.from(reorderingInstanceIds);
    updatedReorderingIds.addAll(reorderingIds);

    onInstancesUpdate(updatedInstances);
    onReorderingIdsUpdate(updatedReorderingIds);
    onCacheInvalidate();

    // Perform database update in background
    try {
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'queue',
        oldIndex,
        adjustedNewIndex,
      );

      // Remove ids from reordering set after success
      final finalReorderingIds = Set<String>.from(updatedReorderingIds);
      finalReorderingIds.removeAll(reorderingIds);
      // We don't need to update instances again as they are already correct from optimistic update
      // just clear the reordering flags
      onReorderingIdsUpdate(finalReorderingIds);
    } catch (e) {
      // Revert reordering ids on error
      final finalReorderingIds = Set<String>.from(reorderingInstanceIds);
      // We don't remove newly added ones because we are reverting to original state passed in
      // Actually strictly speaking we should just revert to `reorderingInstanceIds`
      onReorderingIdsUpdate(finalReorderingIds);

      // Reload data to revert UI
      await onLoadData();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
