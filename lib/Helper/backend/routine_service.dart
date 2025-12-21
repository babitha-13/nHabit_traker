import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/backend/routine_order_service.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/routine_reminder_scheduler.dart';

class RoutineService {
  /// Check if instance is due today or overdue (mirrors Queue page logic)
  static bool _isInstanceForToday(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return true; // No due date = today
    final today = DateService.todayStart;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);

    // For habits: include if today is within the window [dueDate, windowEndDate]
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        // Today should be >= dueDate AND <= windowEnd
        final isWithinWindow = !today.isBefore(dueDate) &&
            !today.isAfter(
                DateTime(windowEnd.year, windowEnd.month, windowEnd.day));
        return isWithinWindow;
      }
      // Fallback to due date check if no window
      final isDueToday = dueDate.isAtSameMomentAs(today);
      return isDueToday;
    }

    // For tasks: only if due today or overdue
    final isTodayOrOverdue =
        dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);
    return isTodayOrOverdue;
  }

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
    // Get item names and types from the item IDs
    final itemNames = <String>[];
    final itemTypes = <String>[];
    for (final itemId in itemIds) {
      try {
        final activityDoc =
            await ActivityRecord.collectionForUser(uid).doc(itemId).get();
        if (activityDoc.exists) {
          final activityData = activityDoc.data() as Map<String, dynamic>?;
          if (activityData != null) {
            itemNames.add(activityData['name'] ?? 'Unknown Item');
            itemTypes.add(activityData['categoryType'] ?? 'habit');
          }
        }
      } catch (e) {
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
      // Update cached names and types
      final itemNames = <String>[];
      final itemTypes = <String>[];
      for (final itemId in itemIds) {
        try {
          final activityDoc =
              await ActivityRecord.collectionForUser(uid).doc(itemId).get();
          if (activityDoc.exists) {
            final activityData = activityDoc.data() as Map<String, dynamic>?;
            if (activityData != null) {
              itemNames.add(activityData['name'] ?? 'Unknown Item');
              itemTypes.add(activityData['categoryType'] ?? 'habit');
            }
          }
        } catch (e) {
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

      // Query ALL instances for the specific items in this routine
      // This works for habits, tasks, and non-productive items (no category type restriction)
      // Handle Firestore's 10-item limit for whereIn by batching if needed
      final allInstances = <ActivityInstanceRecord>[];
      final itemIds = routine.itemIds;

      if (itemIds.length <= 10) {
        // Single query for small sequences
        final result = await ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', whereIn: itemIds)
            .get();
        allInstances.addAll(
            result.docs.map((doc) => ActivityInstanceRecord.fromSnapshot(doc)));
      } else {
        // Batch queries for large sequences (Firestore whereIn limit is 10)
        for (int i = 0; i < itemIds.length; i += 10) {
          final batch = itemIds.skip(i).take(10).toList();
          final result = await ActivityInstanceRecord.collectionForUser(uid)
              .where('templateId', whereIn: batch)
              .get();
          allInstances.addAll(result.docs
              .map((doc) => ActivityInstanceRecord.fromSnapshot(doc)));
        }
      }

      // Apply "today's instance per template" logic (mirrors Queue page behavior)
      final instancesMap = <String, List<ActivityInstanceRecord>>{};
      for (final instance in allInstances) {
        final templateId = instance.templateId;
        (instancesMap[templateId] ??= []).add(instance);
      }

      // For each template, find today's instance
      final todayInstances = <String, ActivityInstanceRecord>{};
      for (final itemId in routine.itemIds) {
        final instances = instancesMap[itemId] ?? [];
        if (instances.isNotEmpty) {
          // Filter to only instances due today or overdue
          final todayInstancesForTemplate =
              instances.where((inst) => _isInstanceForToday(inst)).toList();

          if (todayInstancesForTemplate.isNotEmpty) {
            // Sort by due date (earliest first, nulls last)
            todayInstancesForTemplate.sort((a, b) {
              if (a.dueDate == null && b.dueDate == null) return 0;
              if (a.dueDate == null) return 1;
              if (b.dueDate == null) return -1;
              return a.dueDate!.compareTo(b.dueDate!);
            });

            // Take the first one (should only be one per template for today)
            todayInstances[itemId] = todayInstancesForTemplate.first;
          }
        }
      }

      return RoutineWithInstances(
        routine: routine,
        instances: todayInstances,
      );
    } catch (e) {
      return null;
    }
  }

  /// Create an instance for a routine item on-the-fly
  /// Returns null for non-productive items (UI should show time log dialog instead)
  static Future<ActivityInstanceRecord?> createInstanceForRoutineItem({
    required String itemId,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      // Get the activity template to understand its tracking type
      final activityDoc =
          await ActivityRecord.collectionForUser(uid).doc(itemId).get();
      if (!activityDoc.exists) {
        return null;
      }
      final activityData = activityDoc.data() as Map<String, dynamic>?;
      if (activityData == null) {
        return null;
      }
      // For non-productive items, return null - UI should show time log dialog
      final categoryType = activityData['categoryType'] ?? 'habit';
      if (categoryType == 'non_productive') {
        return null; // Signal to UI to show time log dialog
      }
      final trackingType = activityData['trackingType'] ?? 'binary';
      final target = activityData['target'];
      final unit = activityData['unit'];
      // Fetch category color for the instance
      String? categoryColor;
      try {
        final categoryId = activityData['categoryId'];
        if (categoryId != null && categoryId.toString().isNotEmpty) {
          final categoryDoc = await CategoryRecord.collectionForUser(uid)
              .doc(categoryId.toString())
              .get();
          if (categoryDoc.exists) {
            final category = CategoryRecord.fromSnapshot(categoryDoc);
            categoryColor = category.color;
          }
        }
      } catch (e) {
        // If category fetch fails, continue without color
      }
      // Create the instance data
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      // Inherit order from previous instance of the same template
      int? queueOrder;
      int? habitsOrder;
      int? tasksOrder;
      try {
        queueOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            itemId, 'queue', uid);
        habitsOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            itemId, 'habits', uid);
        tasksOrder = await InstanceOrderService.getOrderFromPreviousInstance(
            itemId, 'tasks', uid);
      } catch (e) {
        // If order lookup fails, continue with null values (will use default sorting)
      }
      final instanceData = createActivityInstanceRecordData(
        templateId: itemId,
        templateName: activityData['name'] ?? 'Unknown Item',
        templateCategoryType: activityData['categoryType'] ?? 'habit',
        templateCategoryColor: categoryColor,
        templateTrackingType: trackingType,
        templateTarget: target,
        templateUnit: unit,
        templatePriority: activityData['priority'] ?? 1,
        templateDescription: activityData['description'],
        dueDate: todayStart,
        status: 'pending',
        currentValue: 0,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
        // Inherit order from previous instance
        queueOrder: queueOrder,
        habitsOrder: habitsOrder,
        tasksOrder: tasksOrder,
      );
      // Create the instance
      final instanceRef =
          await ActivityInstanceRecord.collectionForUser(uid).add(instanceData);
      final instanceDoc = await instanceRef.get();
      if (instanceDoc.exists) {
        return ActivityInstanceRecord.fromSnapshot(instanceDoc);
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Reset all completed non-productive (routine item) instances in a routine
  /// Creates new pending instances for non-productive items only
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
      // Iterate through items and reset only non-productive items that are completed
      for (int i = 0; i < itemIds.length; i++) {
        final itemId = itemIds[i];
        final itemType = i < itemTypes.length ? itemTypes[i] : 'habit';

        // Only process non-productive items
        if (itemType != 'non_productive') continue;

        final instance = currentInstances[itemId];

        // Only reset if instance exists and is completed/skipped
        if (instance != null &&
            (instance.status == 'completed' || instance.status == 'skipped')) {
          // Create new pending instance
          final newInstance = await createInstanceForRoutineItem(
            itemId: itemId,
            userId: uid,
          );

          if (newInstance != null) {
            resetCount++;
          }
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
