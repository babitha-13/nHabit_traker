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
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        print(
            'InstanceOrderService: Attempt $attempt/$maxRetries for reordering instances');

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
        final List<String> instanceIds = [];

        for (int i = 0; i < instances.length; i++) {
          final instance = instances[i];
          final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
              .doc(instance.reference.id);
          instanceIds.add(instance.reference.id);

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

        // Commit the batch
        await batch.commit();
        print(
            'InstanceOrderService: Batch committed successfully for ${instanceIds.length} instances');

        // Validate that the updates were actually saved
        await _validateOrderUpdates(instanceIds, pageType, instances);

        print('InstanceOrderService: Order validation successful');
        return; // Success, exit retry loop
      } catch (e) {
        print('InstanceOrderService: Attempt $attempt failed: $e');

        if (attempt == maxRetries) {
          print('InstanceOrderService: All retry attempts failed');
          rethrow;
        }

        // Wait before retrying
        await Future.delayed(retryDelay);
      }
    }
  }

  /// Validate that order updates were actually saved to the database
  static Future<void> _validateOrderUpdates(
    List<String> instanceIds,
    String pageType,
    List<ActivityInstanceRecord> expectedInstances,
  ) async {
    try {
      final userId = currentUserUid;
      final List<Future<DocumentSnapshot>> futures = [];

      // Fetch all instances to validate their order values
      for (final instanceId in instanceIds) {
        final instanceRef =
            ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);
        futures.add(instanceRef.get());
      }

      final snapshots = await Future.wait(futures);

      // Validate each instance's order value
      for (int i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        if (!snapshot.exists) {
          throw Exception('Instance ${instanceIds[i]} not found after update');
        }

        final data = snapshot.data() as Map<String, dynamic>;
        int? actualOrder;

        switch (pageType) {
          case 'queue':
            actualOrder = data['queueOrder'] as int?;
            break;
          case 'habits':
            actualOrder = data['habitsOrder'] as int?;
            break;
          case 'tasks':
            actualOrder = data['tasksOrder'] as int?;
            break;
        }

        final expectedOrder = i;
        if (actualOrder != expectedOrder) {
          throw Exception(
              'Order validation failed for ${instanceIds[i]}: expected $expectedOrder, got $actualOrder');
        }
      }

      print('InstanceOrderService: All order values validated successfully');
    } catch (e) {
      print('InstanceOrderService: Order validation failed: $e');
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
