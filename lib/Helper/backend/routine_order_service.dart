import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class RoutineOrderService {
  /// Initialize order values for routines that don't have them
  static Future<void> initializeOrderValues(
    List<RoutineRecord> routines,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userId = currentUserUid;
      for (int i = 0; i < routines.length; i++) {
        final routine = routines[i];
        bool needsUpdate = false;
        Map<String, dynamic> updateData = {};
        if (!routine.hasListOrder()) {
          updateData['listOrder'] = i;
          updateData['lastUpdated'] = DateTime.now();
          needsUpdate = true;
        }
        if (needsUpdate) {
          final routineRef =
              RoutineRecord.collectionForUser(userId).doc(routine.reference.id);
          batch.update(routineRef, updateData);
        }
      }
      await batch.commit();
    } catch (e) {
      // Silently fail - order initialization is not critical
    }
  }

  /// Get the next order index for a new routine
  static Future<int> getNextOrderIndex({String? userId}) async {
    try {
      final uid = userId ?? currentUserUid;
      if (uid.isEmpty) return 0;
      final query = RoutineRecord.collectionForUser(uid)
          .where('isActive', isEqualTo: true)
          .orderBy('listOrder', descending: true)
          .limit(1);
      final result = await query.get();
      if (result.docs.isEmpty) return 0;
      final lastRoutine = RoutineRecord.fromSnapshot(result.docs.first);
      return (lastRoutine.hasListOrder() ? lastRoutine.listOrder : 0) + 1;
    } catch (e) {
      // If orderBy fails, count existing routines
      try {
        final query = RoutineRecord.collectionForUser(userId ?? currentUserUid)
            .where('isActive', isEqualTo: true);
        final result = await query.get();
        return result.docs.length;
      } catch (e2) {
        return 0;
      }
    }
  }

  /// Reorder routines after drag operation
  static Future<void> reorderRoutines(
    List<RoutineRecord> routines,
    int oldIndex,
    int newIndex,
  ) async {
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // routines is already in the desired order; just persist the order
        final batch = FirebaseFirestore.instance.batch();
        final userId = currentUserUid;
        final List<String> routineIds = [];
        for (int i = 0; i < routines.length; i++) {
          final routine = routines[i];
          final routineRef =
              RoutineRecord.collectionForUser(userId).doc(routine.reference.id);
          routineIds.add(routine.reference.id);
          batch.update(routineRef, {
            'listOrder': i,
            'lastUpdated': DateTime.now(),
          });
        }
        // Commit the batch
        await batch.commit();
        // Validate that the updates were actually saved
        await _validateOrderUpdates(routineIds, routines);
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
    List<String> routineIds,
    List<RoutineRecord> expectedRoutines,
  ) async {
    try {
      final userId = currentUserUid;
      final List<Future<DocumentSnapshot>> futures = [];
      // Fetch all routines to validate their order values
      for (final routineId in routineIds) {
        final routineRef =
            RoutineRecord.collectionForUser(userId).doc(routineId);
        futures.add(routineRef.get());
      }
      final snapshots = await Future.wait(futures);
      // Validate each routine's order value
      for (int i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        if (!snapshot.exists) {
          throw Exception('Routine ${routineIds[i]} not found after update');
        }
        final data = snapshot.data() as Map<String, dynamic>;
        final actualOrder = data['listOrder'] as int?;
        final expectedOrder = i;
        if (actualOrder != expectedOrder) {
          throw Exception(
              'Order validation failed for ${routineIds[i]}: expected $expectedOrder, got $actualOrder');
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Sort routines by their order
  static List<RoutineRecord> sortRoutinesByOrder(
    List<RoutineRecord> routines,
  ) {
    final sortedRoutines = List<RoutineRecord>.from(routines);
    sortedRoutines.sort((a, b) {
      final orderA = a.listOrder;
      final orderB = b.listOrder;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.name.compareTo(b.name);
    });
    return sortedRoutines;
  }
}
