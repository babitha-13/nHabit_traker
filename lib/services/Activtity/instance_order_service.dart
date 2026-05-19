import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class InstanceOrderService {
  /// pageType values:
  ///   'queue'         => queueOrder (Manual / 'none' sort)
  ///   'queue_points'  => queuePointsOrder
  ///   'queue_time'    => queueTimeOrder
  ///   'queue_urgency' => queueUrgencyOrder
  ///   'habits'        => habitsOrder
  ///   'tasks'         => tasksOrder
  static String orderFieldFor(String pageType) {
    switch (pageType) {
      case 'queue':
        return 'queueOrder';
      case 'queue_points':
        return 'queuePointsOrder';
      case 'queue_time':
        return 'queueTimeOrder';
      case 'queue_urgency':
        return 'queueUrgencyOrder';
      case 'habits':
        return 'habitsOrder';
      case 'tasks':
        return 'tasksOrder';
      default:
        throw ArgumentError('Invalid page type: $pageType');
    }
  }

  /// Update the order of a single instance for a specific page
  static Future<void> updateInstanceOrder(
    String instanceId,
    String pageType,
    int newOrder,
  ) async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final instanceRef =
          ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);
      await instanceRef.update({orderFieldFor(pageType): newOrder});
    } catch (e) {
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
        // instances is already in the desired order; just persist the order
        final batch = FirebaseFirestore.instance.batch();
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        final List<String> instanceIds = [];
        final fieldName = orderFieldFor(pageType);
        for (int i = 0; i < instances.length; i++) {
          final instance = instances[i];
          final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
              .doc(instance.reference.id);
          instanceIds.add(instance.reference.id);
          batch.update(instanceRef, {fieldName: i});
        }
        // Commit the batch
        await batch.commit();
        // Validate that the updates were actually saved
        await _validateOrderUpdates(instanceIds, pageType, instances);
        return; // Success, exit retry loop
      } catch (e) {
        if (attempt == maxRetries) {
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
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final List<Future<DocumentSnapshot>> futures = [];
      // Fetch all instances to validate their order values
      for (final instanceId in instanceIds) {
        final instanceRef =
            ActivityInstanceRecord.collectionForUser(userId).doc(instanceId);
        futures.add(instanceRef.get());
      }
      final snapshots = await Future.wait(futures);
      final fieldName = orderFieldFor(pageType);
      // Validate each instance's order value
      for (int i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        if (!snapshot.exists) {
          throw Exception('Instance ${instanceIds[i]} not found after update');
        }
        final data = snapshot.data() as Map<String, dynamic>;
        final actualOrder = data[fieldName] as int?;
        final expectedOrder = i;
        if (actualOrder != expectedOrder) {
          throw Exception(
              'Order validation failed for ${instanceIds[i]}: expected $expectedOrder, got $actualOrder');
        }
      }
    } catch (e) {
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
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      final fieldName = orderFieldFor(pageType);
      for (int i = 0; i < instances.length; i++) {
        final instance = instances[i];
        if (hasOrderValue(instance, pageType)) continue;
        final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
            .doc(instance.reference.id);
        batch.update(instanceRef, {fieldName: i});
      }
      await batch.commit();
    } catch (e) {
      rethrow;
    }
  }

  /// Get the appropriate order field for a page type
  static int getOrderValue(ActivityInstanceRecord instance, String pageType) {
    switch (pageType) {
      case 'queue':
        return instance.queueOrder;
      case 'queue_points':
        return instance.queuePointsOrder;
      case 'queue_time':
        return instance.queueTimeOrder;
      case 'queue_urgency':
        return instance.queueUrgencyOrder;
      case 'habits':
        return instance.habitsOrder;
      case 'tasks':
        return instance.tasksOrder;
      default:
        return 0;
    }
  }

  /// Whether the instance has a stored order value for this page type.
  static bool hasOrderValue(
      ActivityInstanceRecord instance, String pageType) {
    switch (pageType) {
      case 'queue':
        return instance.hasQueueOrder();
      case 'queue_points':
        return instance.hasQueuePointsOrder();
      case 'queue_time':
        return instance.hasQueueTimeOrder();
      case 'queue_urgency':
        return instance.hasQueueUrgencyOrder();
      case 'habits':
        return instance.hasHabitsOrder();
      case 'tasks':
        return instance.hasTasksOrder();
      default:
        return false;
    }
  }

  /// Get order value from the most recent instance of the same template
  /// Returns null if no previous instance exists or if order is not set
  static Future<int?> getOrderFromPreviousInstance(
    String templateId,
    String pageType,
    String userId,
  ) async {
    try {
      if (userId.isEmpty || templateId.isEmpty) return null;
      // Query for the most recent instance of this template, sorted by createdTime descending
      final query = ActivityInstanceRecord.collectionForUser(userId)
          .where('templateId', isEqualTo: templateId)
          .orderBy('createdTime', descending: true)
          .limit(1);
      final querySnapshot = await query.get();
      if (querySnapshot.docs.isEmpty) return null;
      final previousInstance =
          ActivityInstanceRecord.fromSnapshot(querySnapshot.docs.first);
      // Get the order value for the specified page type
      if (!hasOrderValue(previousInstance, pageType)) return null;
      return getOrderValue(previousInstance, pageType);
    } catch (e) {
      // If query fails, return null to allow instance creation to continue
      return null;
    }
  }

  /// Sort instances by their order for a specific page
  /// Uses secondary sort keys (templateName, createdTime) for stable ordering when order values are equal
  static List<ActivityInstanceRecord> sortInstancesByOrder(
    List<ActivityInstanceRecord> instances,
    String pageType,
  ) {
    final sortedInstances = List<ActivityInstanceRecord>.from(instances);
    sortedInstances.sort((a, b) {
      final orderA = getOrderValue(a, pageType);
      final orderB = getOrderValue(b, pageType);

      // Primary sort: by order value
      final orderComparison = orderA.compareTo(orderB);
      if (orderComparison != 0) {
        return orderComparison;
      }

      // Secondary sort: by createdTime (latest first) for new tasks to appear on top
      final createdA = a.createdTime ?? DateTime(0);
      final createdB = b.createdTime ?? DateTime(0);
      final timeComparison = createdB.compareTo(createdA);
      if (timeComparison != 0) {
        return timeComparison;
      }

      // Tertiary sort: by template name (alphabetical)
      final nameA = a.templateName.toLowerCase();
      final nameB = b.templateName.toLowerCase();
      return nameA.compareTo(nameB);
    });
    return sortedInstances;
  }
}
