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
  static bool _stringListsEqual(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Remove stale/deleted/inactive routine items and normalize cached metadata.
  static Future<RoutineRecord> _sanitizeRoutineItems({
    required RoutineRecord routine,
    required String userId,
  }) async {
    if (routine.itemIds.isEmpty) {
      return routine;
    }

    Map<String, ActivityRecord> templates;
    try {
      // Bypass cache for correctness: routine sanitization should reflect current
      // template state after delete/deactivate operations.
      templates = await BatchReadService.batchGetTemplates(
        templateIds: routine.itemIds,
        userId: userId,
        useCache: false,
      );
    } catch (_) {
      // If lookup fails, keep routine unchanged to avoid destructive updates.
      return routine;
    }

    final activeTemplates = <String, ActivityRecord>{};
    for (final entry in templates.entries) {
      if (entry.value.isActive) {
        activeTemplates[entry.key] = entry.value;
      }
    }

    final validIds = activeTemplates.keys.toSet();
    final preferredOrder =
        routine.itemOrder.isNotEmpty ? routine.itemOrder : routine.itemIds;

    final sanitizedOrder = <String>[];
    for (final id in preferredOrder) {
      if (validIds.contains(id) && !sanitizedOrder.contains(id)) {
        sanitizedOrder.add(id);
      }
    }
    for (final id in routine.itemIds) {
      if (validIds.contains(id) && !sanitizedOrder.contains(id)) {
        sanitizedOrder.add(id);
      }
    }

    final sanitizedIds = List<String>.from(sanitizedOrder);
    final sanitizedNames = <String>[];
    final sanitizedTypes = <String>[];
    for (final id in sanitizedIds) {
      final template = activeTemplates[id];
      sanitizedNames.add(template?.name ?? 'Unknown Item');
      sanitizedTypes.add(template?.categoryType ?? 'habit');
    }

    final hasChanges = !_stringListsEqual(sanitizedIds, routine.itemIds) ||
        !_stringListsEqual(sanitizedOrder, routine.itemOrder) ||
        !_stringListsEqual(sanitizedNames, routine.itemNames) ||
        !_stringListsEqual(sanitizedTypes, routine.itemTypes);

    if (!hasChanges) {
      return routine;
    }

    final updateData = <String, dynamic>{
      'itemIds': sanitizedIds,
      'itemOrder': sanitizedOrder,
      'itemNames': sanitizedNames,
      'itemTypes': sanitizedTypes,
      'lastUpdated': DateTime.now(),
    };

    await routine.reference.update(updateData);
    final mergedData = Map<String, dynamic>.from(routine.snapshotData)
      ..addAll(updateData);

    NotificationCenter.post('routineUpdated', {
      'action': 'itemsSanitized',
      'routineId': routine.reference.id,
    });

    return RoutineRecord.getDocumentFromData(mergedData, routine.reference);
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
    bool clearDueTime = false,
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
    if (clearDueTime) {
      updateData['dueTime'] = null;
    } else if (dueTime != null) {
      updateData['dueTime'] = dueTime;
    }
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
      var routine = RoutineRecord.fromSnapshot(routineDoc);
      if (!routine.isActive) return null;

      routine = await _sanitizeRoutineItems(
        routine: routine,
        userId: uid,
      );

      final repo = TodayInstanceRepository.instance;
      await repo.ensureHydratedForTasks(
        userId: uid,
        includeHabitItems: true,
      );
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
      // Always fetch latest template state to avoid recreating instances for
      // recently deleted/deactivated routine items.
      final activityDoc =
          await ActivityRecord.collectionForUser(uid).doc(itemId).get();
      if (!activityDoc.exists) {
        return null;
      }
      final template = ActivityRecord.fromSnapshot(activityDoc);
      FirestoreCacheService().cacheTemplate(itemId, template);

      if (!template.isActive) {
        return null;
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
