import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';

/// Helper class for handling reordering in queue page
class QueueReorderHandler {
  /// Handle reordering of items within a section
  static Future<ReorderResult> handleReorder({
    required List<ActivityInstanceRecord> items,
    required int oldIndex,
    required int newIndex,
    required List<ActivityInstanceRecord> allInstances,
    required Set<String> reorderingInstanceIds,
    required bool isSortActive,
    required String sectionKey,
  }) async {
    // Allow dropping at the end (newIndex can equal items.length)
    if (oldIndex < 0 ||
        oldIndex >= items.length ||
        newIndex < 0 ||
        newIndex > items.length) {
      return ReorderResult(success: false);
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
      final index =
          updatedInstances.indexWhere((inst) => inst.reference.id == instanceId);
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

    // Perform database update in background
    try {
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'queue',
        oldIndex,
        adjustedNewIndex,
      );
      return ReorderResult(
        success: true,
        updatedInstances: updatedInstances,
        reorderingIds: reorderingIds,
        shouldClearSort: isSortActive,
      );
    } catch (e) {
      return ReorderResult(
        success: false,
        error: e,
        reorderingIds: reorderingIds,
      );
    }
  }
}

/// Result class for reorder operation
class ReorderResult {
  final bool success;
  final List<ActivityInstanceRecord>? updatedInstances;
  final Set<String>? reorderingIds;
  final bool shouldClearSort;
  final dynamic error;

  ReorderResult({
    required this.success,
    this.updatedInstances,
    this.reorderingIds,
    this.shouldClearSort = false,
    this.error,
  });
}
