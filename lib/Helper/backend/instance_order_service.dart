import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class InstanceOrderService {
  /// Update the order of a single instance for a specific page
  static Future<void> updateInstanceOrder(
    String instanceId,
    String pageType, // 'queue', 'habits', 'tasks'
    int newOrder,
  ) async {
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) return;

      final instanceRef =
          ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);

      Map<String, dynamic> updateData = {};
      switch (pageType) {
        case 'queue':
          updateData['queueOrder'] = newOrder;
          break;
        case 'habits':
          updateData['habitsOrder'] = newOrder;
          break;
        case 'tasks':
          updateData['tasksOrder'] = newOrder;
          break;
        default:
          throw ArgumentError('Invalid page type: $pageType');
      }

      await instanceRef.update(updateData);
    } catch (e) {
      print('Error updating instance order: $e');
      rethrow;
    }
  }

  /// Reorder instances within a section after drag operation
  static Future<void> reorderInstancesInSection(
    List<ActivityInstanceRecord> instances,
    String pageType,
    int oldIndex,
    int newIndex,
  ) async {
    try {
      // Adjust newIndex for the case where we're moving down
      if (oldIndex < newIndex) {
        newIndex -= 1;
      }

      // Get the item being moved
      final movedItem = instances.removeAt(oldIndex);
      instances.insert(newIndex, movedItem);

      // Update orders for all affected instances
      final batch = FirebaseFirestore.instance.batch();
      final userId = currentUserUid;

      for (int i = 0; i < instances.length; i++) {
        final instance = instances[i];
        final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
            .doc(instance.reference.id);

        Map<String, dynamic> updateData = {};
        switch (pageType) {
          case 'queue':
            updateData['queueOrder'] = i;
            break;
          case 'habits':
            updateData['habitsOrder'] = i;
            break;
          case 'tasks':
            updateData['tasksOrder'] = i;
            break;
        }

        batch.update(instanceRef, updateData);
      }

      await batch.commit();
    } catch (e) {
      print('Error reordering instances: $e');
      rethrow;
    }
  }

  /// Initialize order values for instances that don't have them
  static Future<void> initializeOrderValues(
    List<ActivityInstanceRecord> instances,
    String pageType,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userId = currentUserUid;

      for (int i = 0; i < instances.length; i++) {
        final instance = instances[i];
        bool needsUpdate = false;
        Map<String, dynamic> updateData = {};

        switch (pageType) {
          case 'queue':
            if (!instance.hasQueueOrder()) {
              updateData['queueOrder'] = i;
              needsUpdate = true;
            }
            break;
          case 'habits':
            if (!instance.hasHabitsOrder()) {
              updateData['habitsOrder'] = i;
              needsUpdate = true;
            }
            break;
          case 'tasks':
            if (!instance.hasTasksOrder()) {
              updateData['tasksOrder'] = i;
              needsUpdate = true;
            }
            break;
        }

        if (needsUpdate) {
          final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
              .doc(instance.reference.id);
          batch.update(instanceRef, updateData);
        }
      }

      await batch.commit();
    } catch (e) {
      print('Error initializing order values: $e');
      rethrow;
    }
  }

  /// Get the appropriate order field for a page type
  static int getOrderValue(ActivityInstanceRecord instance, String pageType) {
    switch (pageType) {
      case 'queue':
        return instance.queueOrder;
      case 'habits':
        return instance.habitsOrder;
      case 'tasks':
        return instance.tasksOrder;
      default:
        return 0;
    }
  }

  /// Sort instances by their order for a specific page
  static List<ActivityInstanceRecord> sortInstancesByOrder(
    List<ActivityInstanceRecord> instances,
    String pageType,
  ) {
    final sortedInstances = List<ActivityInstanceRecord>.from(instances);
    sortedInstances.sort((a, b) {
      final orderA = getOrderValue(a, pageType);
      final orderB = getOrderValue(b, pageType);
      return orderA.compareTo(orderB);
    });
    return sortedInstances;
  }
}
