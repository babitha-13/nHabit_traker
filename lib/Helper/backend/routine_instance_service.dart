import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class RoutineInstanceService {
  /// Get or create today's routine instance
  static Future<RoutineInstanceRecord?> getOrCreateRoutineInstance({
    required String routineId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      // Try to find existing instance for this date
      final existingQuery = RoutineInstanceRecord.collectionForUser(uid)
          .where('sequenceId', isEqualTo: routineId)
          .where('date', isEqualTo: dateStart)
          .where('isActive', isEqualTo: true)
          .limit(1);
      final existingSnapshot = await existingQuery.get();
      if (existingSnapshot.docs.isNotEmpty) {
        return RoutineInstanceRecord.fromSnapshot(existingSnapshot.docs.first);
      }
      // Create new routine instance
      final routineInstanceData = createRoutineInstanceRecordData(
        sequenceId: routineId,
        date: dateStart,
        itemInstanceIds: {},
        status: 'pending',
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: uid,
      );
      final routineInstanceRef =
          await RoutineInstanceRecord.collectionForUser(uid)
              .add(routineInstanceData);
      return RoutineInstanceRecord.fromSnapshot(
        await routineInstanceRef.get(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get all item instances for a routine on a specific date
  static Future<Map<String, ActivityInstanceRecord>> getInstancesForRoutine({
    required String routineId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      // Get routine instance
      final routineInstance = await getOrCreateRoutineInstance(
        routineId: routineId,
        date: dateStart,
        userId: userId,
      );
      if (routineInstance == null) return {};
      final instances = <String, ActivityInstanceRecord>{};
      // For each item in the routine instance, get or create its activity instance
      for (final entry in routineInstance.itemInstanceIds.entries) {
        final itemId = entry.key;
        final instanceId = entry.value;
        try {
          final instanceDoc =
              await ActivityInstanceRecord.collectionForUser(uid)
                  .doc(instanceId)
                  .get();
          if (instanceDoc.exists) {
            instances[itemId] =
                ActivityInstanceRecord.fromSnapshot(instanceDoc);
          }
        } catch (e) {}
      }
      return instances;
    } catch (e) {
      return {};
    }
  }

  /// Link an activity instance to a routine
  static Future<void> linkInstanceToRoutine({
    required String routineId,
    required String itemId,
    required String instanceId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      // Get or create routine instance
      final routineInstance = await getOrCreateRoutineInstance(
        routineId: routineId,
        date: dateStart,
        userId: userId,
      );
      if (routineInstance == null) return;
      // Update the itemInstanceIds map
      final updatedItemInstanceIds =
          Map<String, String>.from(routineInstance.itemInstanceIds);
      updatedItemInstanceIds[itemId] = instanceId;
      await RoutineInstanceRecord.collectionForUser(uid)
          .doc(routineInstance.reference.id)
          .update({
        'itemInstanceIds': updatedItemInstanceIds,
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {}
  }

  /// Update routine instance status
  static Future<void> updateRoutineStatus({
    required String routineId,
    required String status,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      final routineInstanceQuery =
          RoutineInstanceRecord.collectionForUser(uid)
              .where('sequenceId', isEqualTo: routineId)
              .where('date', isEqualTo: dateStart)
              .where('isActive', isEqualTo: true)
              .limit(1);
      final routineInstanceSnapshot = await routineInstanceQuery.get();
      if (routineInstanceSnapshot.docs.isEmpty) return;
      final routineInstance = RoutineInstanceRecord.fromSnapshot(
          routineInstanceSnapshot.docs.first);
      final updateData = <String, dynamic>{
        'status': status,
        'lastUpdated': DateTime.now(),
      };
      if (status == 'started' && routineInstance.startedAt == null) {
        updateData['startedAt'] = DateTime.now();
      } else if (status == 'completed' &&
          routineInstance.completedAt == null) {
        updateData['completedAt'] = DateTime.now();
      }
      await RoutineInstanceRecord.collectionForUser(uid)
          .doc(routineInstance.reference.id)
          .update(updateData);
    } catch (e) {}
  }

  /// Get routine instance for a specific date
  static Future<RoutineInstanceRecord?> getRoutineInstance({
    required String routineId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      final routineInstanceQuery =
          RoutineInstanceRecord.collectionForUser(uid)
              .where('sequenceId', isEqualTo: routineId)
              .where('date', isEqualTo: dateStart)
              .where('isActive', isEqualTo: true)
              .limit(1);
      final routineInstanceSnapshot = await routineInstanceQuery.get();
      if (routineInstanceSnapshot.docs.isEmpty) return null;
      return RoutineInstanceRecord.fromSnapshot(
          routineInstanceSnapshot.docs.first);
    } catch (e) {
      return null;
    }
  }
}
