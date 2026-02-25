import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Routine/Backend_data/routine_order_service.dart';
import 'package:habit_tracker/features/Routine/routine_reminder_scheduler.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/backend/cache/batch_read_service.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';

class RoutineService {
  /// Create a new routine with items and order
  static Future<DocumentReference> createRoutine({
    required String name,
    String? description,
    required List<String> itemIds,
    required List<String> itemOrder,
    String? userId,
    String? dueTime,
    List<Map<String, dynamic>>? reminders,
    String? reminderFrequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    List<int>? specificDays,
    bool? remindersEnabled,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    // Get next order index for the new routine
    final listOrder = await RoutineOrderService.getNextOrderIndex(userId: uid);
    // Get item names and types from the item IDs - batch read for efficiency
    final itemNames = <String>[];
    final itemTypes = <String>[];
    try {
      // Batch read all templates at once
      final templates = await BatchReadService.batchGetTemplates(
        templateIds: itemIds,
        userId: uid,
        useCache: true,
      );
      for (final itemId in itemIds) {
        final template = templates[itemId];
        if (template != null) {
          itemNames.add(template.name);
          itemTypes.add(template.categoryType);
        } else {
          itemNames.add('Unknown Item');
          itemTypes.add('habit');
        }
      }
    } catch (e) {
      // Fallback: add unknown items
      for (final _ in itemIds) {
        itemNames.add('Unknown Item');
        itemTypes.add('habit');
      }
    }
    final routineData = createRoutineRecordData(
      uid: uid,
      name: name,
      description: description,
      itemIds: itemIds,
      itemNames: itemNames,
      itemOrder: itemOrder,
      itemTypes: itemTypes,
      isActive: true,
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      userId: uid,
      listOrder: listOrder,
      dueTime: dueTime,
      reminders: reminders,
      reminderFrequencyType: reminderFrequencyType,
      everyXValue: everyXValue,
      everyXPeriodType: everyXPeriodType,
      specificDays: specificDays,
      remindersEnabled: remindersEnabled,
    );
    final routineRef =
        await RoutineRecord.collectionForUser(uid).add(routineData);
    // Schedule reminders after creation
    try {
      final routine = RoutineRecord.fromSnapshot(await routineRef.get());
      await RoutineReminderScheduler.scheduleForRoutine(routine);
    } catch (e) {
      // Don't fail routine creation if reminder scheduling fails
      print('RoutineService: Error scheduling reminders: $e');
    }
    NotificationCenter.post('routineUpdated', {
      'action': 'created',
      'routineId': routineRef.id,
    });
    return routineRef;
  }

  /// Update a routine
  static Future<void> updateRoutine({
    required String routineId,
    String? name,
    String? description,
    List<String>? itemIds,
    List<String>? itemOrder,
    String? userId,
    int? listOrder,
    String? dueTime,
    List<Map<String, dynamic>>? reminders,
    String? reminderFrequencyType,
    int? everyXValue,
    String? everyXPeriodType,
    List<int>? specificDays,
    bool? remindersEnabled,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final routineRef = RoutineRecord.collectionForUser(uid).doc(routineId);
    final updateData = <String, dynamic>{
      'lastUpdated': DateTime.now(),
    };
    if (name != null) updateData['name'] = name;
    if (description != null) updateData['description'] = description;
    if (itemIds != null) {
      updateData['itemIds'] = itemIds;
      // Update cached names and types - batch read for efficiency
      final itemNames = <String>[];
      final itemTypes = <String>[];
      try {
        // Batch read all templates at once
        final templates = await BatchReadService.batchGetTemplates(
          templateIds: itemIds,
          userId: uid,
          useCache: true,
        );
        for (final itemId in itemIds) {
          final template = templates[itemId];
          if (template != null) {
            itemNames.add(template.name);
            itemTypes.add(template.categoryType);
          } else {
            itemNames.add('Unknown Item');
            itemTypes.add('habit');
          }
        }
      } catch (e) {
        // Fallback: add unknown items
        for (final _ in itemIds) {
          itemNames.add('Unknown Item');
          itemTypes.add('habit');
        }
      }
      updateData['itemNames'] = itemNames;
      updateData['itemTypes'] = itemTypes;
    }
    if (itemOrder != null) updateData['itemOrder'] = itemOrder;
    if (listOrder != null) updateData['listOrder'] = listOrder;
    if (dueTime != null) updateData['dueTime'] = dueTime;
    if (reminders != null) updateData['reminders'] = reminders;
    if (reminderFrequencyType != null) {
      updateData['reminderFrequencyType'] = reminderFrequencyType;
    }
    if (everyXValue != null) updateData['everyXValue'] = everyXValue;
    if (everyXPeriodType != null)
      updateData['everyXPeriodType'] = everyXPeriodType;
    if (specificDays != null) updateData['specificDays'] = specificDays;
    if (remindersEnabled != null)
      updateData['remindersEnabled'] = remindersEnabled;
    await routineRef.update(updateData);
    // Reschedule reminders after update
    try {
      final routineDoc = await routineRef.get();
      if (routineDoc.exists) {
        final routine = RoutineRecord.fromSnapshot(routineDoc);
        await RoutineReminderScheduler.scheduleForRoutine(routine);
      }
    } catch (e) {
      // Don't fail routine update if reminder scheduling fails
      print('RoutineService: Error scheduling reminders: $e');
    }
    NotificationCenter.post('routineUpdated', {
      'action': 'updated',
      'routineId': routineId,
    });
  }

  /// Delete a routine (soft delete)
  static Future<void> deleteRoutine(String routineId, {String? userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    // Cancel reminders before deleting
    try {
      await RoutineReminderScheduler.cancelForRoutine(routineId);
    } catch (e) {
      // Don't fail deletion if reminder cancellation fails
      print('RoutineService: Error canceling reminders: $e');
    }
    final routineRef = RoutineRecord.collectionForUser(uid).doc(routineId);
    await routineRef.update({
      'isActive': false,
      'lastUpdated': DateTime.now(),
    });
    NotificationCenter.post('routineUpdated', {
      'action': 'deleted',
      'routineId': routineId,
    });
  }

  /// Get routine with today's live instances
  static Future<RoutineWithInstances?> getRoutineWithInstances({
    required String routineId,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      // Get routine template
      final routineDoc =
          await RoutineRecord.collectionForUser(uid).doc(routineId).get();
      if (!routineDoc.exists) return null;
      final routine = RoutineRecord.fromSnapshot(routineDoc);
      if (!routine.isActive) return null;

      final repo = TodayInstanceRepository.instance;
      await repo.ensureHydrated(userId: uid);
      final selectedInstances = repo.selectRoutineItems(routine: routine);

      return RoutineWithInstances(
        routine: routine,
        instances: selectedInstances,
      );
    } catch (e) {
      return null;
    }
  }

  /// Create an instance for a routine item on-the-fly
  /// Returns null for Essential Activities (UI should show time log dialog instead)
  static Future<ActivityInstanceRecord?> createInstanceForRoutineItem({
    required String itemId,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      // Get the activity template - check cache first
      final cache = FirestoreCacheService();
      ActivityRecord? template = cache.getCachedTemplate(itemId);
      if (template == null) {
        final activityDoc =
            await ActivityRecord.collectionForUser(uid).doc(itemId).get();
        if (!activityDoc.exists) {
          return null;
        }
        template = ActivityRecord.fromSnapshot(activityDoc);
        cache.cacheTemplate(itemId, template);
      }

      // For Essential Activities, return null - UI should show time log dialog
      if (template.categoryType == 'essential') {
        return null; // Signal to UI to show time log dialog
      }

      // Use the centralized ActivityInstanceService for creation
      // This ensures windows, belongsToDate, etc. are calculated correctly
      final newInstanceRef =
          await ActivityInstanceService.createActivityInstance(
        templateId: itemId,
        template: template,
        userId: uid,
        dueDate: DateTime.now(), // Create for today
      );

      final instanceDoc = await newInstanceRef.get();
      if (instanceDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(instanceDoc);
      }
      return null;
    } catch (e) {
      print('RoutineService: Error creating instance for routine item: $e');
      return null;
    }
  }

  /// Reset all completed essential (routine item) instances in a routine
  /// Uncompletes existing instances while preserving time logs
  /// Leaves habits and tasks untouched
  static Future<int> resetRoutineItems({
    required String routineId,
    required Map<String, ActivityInstanceRecord> currentInstances,
    required List<String> itemTypes,
    required List<String> itemIds,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';

    int resetCount = 0;

    try {
      // Iterate through items and reset only Essential Activities that are completed
      for (int i = 0; i < itemIds.length; i++) {
        final itemId = itemIds[i];
        final itemType = i < itemTypes.length ? itemTypes[i] : 'habit';

        // Only process Essential Activities
        if (itemType != 'essential') continue;

        final instance = currentInstances[itemId];

        // Only reset if instance exists and is completed/skipped
        if (instance != null &&
            (instance.status == 'completed' || instance.status == 'skipped')) {
          // Uncomplete the existing instance, preserving time logs
          await ActivityInstanceService.uncompleteInstance(
            instanceId: instance.reference.id,
            userId: uid,
            deleteLogs: false, // Keep time logs for historical records
          );
          resetCount++;
        }
      }

      return resetCount;
    } catch (e) {
      return resetCount;
    }
  }

  /// Get all routines for a user
  static Future<List<RoutineRecord>> getUserRoutines({String? userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      final query = RoutineRecord.collectionForUser(uid)
          .where('isActive', isEqualTo: true)
          .orderBy('listOrder')
          .orderBy('name');
      final result = await query.get();
      final routines =
          result.docs.map((doc) => RoutineRecord.fromSnapshot(doc)).toList();
      // Fallback sort by listOrder locally if Firestore ordering fails
      routines.sort((a, b) {
        final orderCompare = a.listOrder.compareTo(b.listOrder);
        if (orderCompare != 0) return orderCompare;
        return a.name.compareTo(b.name);
      });
      return routines;
    } catch (e) {
      // If orderBy fails (e.g., no index), fallback to local sort
      try {
        final query = RoutineRecord.collectionForUser(uid)
            .where('isActive', isEqualTo: true);
        final result = await query.get();
        final routines =
            result.docs.map((doc) => RoutineRecord.fromSnapshot(doc)).toList();
        routines.sort((a, b) {
          final orderCompare = a.listOrder.compareTo(b.listOrder);
          if (orderCompare != 0) return orderCompare;
          return a.name.compareTo(b.name);
        });
        return routines;
      } catch (e2) {
        return [];
      }
    }
  }
}

/// Data class to hold routine with its instances
class RoutineWithInstances {
  final RoutineRecord routine;
  final Map<String, ActivityInstanceRecord> instances;
  RoutineWithInstances({
    required this.routine,
    required this.instances,
  });

  /// Get instances in the correct order
  List<ActivityInstanceRecord?> get orderedInstances {
    final ordered = <ActivityInstanceRecord?>[];
    for (final itemId in routine.itemOrder) {
      ordered.add(instances[itemId]);
    }
    return ordered;
  }

  /// Get items that don't have instances yet
  List<String> get missingInstances {
    return routine.itemIds
        .where((itemId) => !instances.containsKey(itemId))
        .toList();
  }
}
