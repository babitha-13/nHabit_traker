import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

class SequenceInstanceService {
  /// Get or create today's sequence instance
  static Future<SequenceInstanceRecord?> getOrCreateSequenceInstance({
    required String sequenceId,
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
      final existingQuery = SequenceInstanceRecord.collectionForUser(uid)
          .where('sequenceId', isEqualTo: sequenceId)
          .where('date', isEqualTo: dateStart)
          .where('isActive', isEqualTo: true)
          .limit(1);
      final existingSnapshot = await existingQuery.get();
      if (existingSnapshot.docs.isNotEmpty) {
        return SequenceInstanceRecord.fromSnapshot(existingSnapshot.docs.first);
      }
      // Create new sequence instance
      final sequenceInstanceData = createSequenceInstanceRecordData(
        sequenceId: sequenceId,
        date: dateStart,
        itemInstanceIds: {},
        status: 'pending',
        isActive: true,
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: uid,
      );
      final sequenceInstanceRef =
          await SequenceInstanceRecord.collectionForUser(uid)
              .add(sequenceInstanceData);
      return SequenceInstanceRecord.fromSnapshot(
        await sequenceInstanceRef.get(),
      );
    } catch (e) {
      return null;
    }
  }

  /// Get all item instances for a sequence on a specific date
  static Future<Map<String, ActivityInstanceRecord>> getInstancesForSequence({
    required String sequenceId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      // Get sequence instance
      final sequenceInstance = await getOrCreateSequenceInstance(
        sequenceId: sequenceId,
        date: dateStart,
        userId: userId,
      );
      if (sequenceInstance == null) return {};
      final instances = <String, ActivityInstanceRecord>{};
      // For each item in the sequence instance, get or create its activity instance
      for (final entry in sequenceInstance.itemInstanceIds.entries) {
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

  /// Link an activity instance to a sequence
  static Future<void> linkInstanceToSequence({
    required String sequenceId,
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
      // Get or create sequence instance
      final sequenceInstance = await getOrCreateSequenceInstance(
        sequenceId: sequenceId,
        date: dateStart,
        userId: userId,
      );
      if (sequenceInstance == null) return;
      // Update the itemInstanceIds map
      final updatedItemInstanceIds =
          Map<String, String>.from(sequenceInstance.itemInstanceIds);
      updatedItemInstanceIds[itemId] = instanceId;
      await SequenceInstanceRecord.collectionForUser(uid)
          .doc(sequenceInstance.reference.id)
          .update({
        'itemInstanceIds': updatedItemInstanceIds,
        'lastUpdated': DateTime.now(),
      });
    } catch (e) {}
  }

  /// Update sequence instance status
  static Future<void> updateSequenceStatus({
    required String sequenceId,
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
      final sequenceInstanceQuery =
          SequenceInstanceRecord.collectionForUser(uid)
              .where('sequenceId', isEqualTo: sequenceId)
              .where('date', isEqualTo: dateStart)
              .where('isActive', isEqualTo: true)
              .limit(1);
      final sequenceInstanceSnapshot = await sequenceInstanceQuery.get();
      if (sequenceInstanceSnapshot.docs.isEmpty) return;
      final sequenceInstance = SequenceInstanceRecord.fromSnapshot(
          sequenceInstanceSnapshot.docs.first);
      final updateData = <String, dynamic>{
        'status': status,
        'lastUpdated': DateTime.now(),
      };
      if (status == 'started' && sequenceInstance.startedAt == null) {
        updateData['startedAt'] = DateTime.now();
      } else if (status == 'completed' &&
          sequenceInstance.completedAt == null) {
        updateData['completedAt'] = DateTime.now();
      }
      await SequenceInstanceRecord.collectionForUser(uid)
          .doc(sequenceInstance.reference.id)
          .update(updateData);
    } catch (e) {}
  }

  /// Get sequence instance for a specific date
  static Future<SequenceInstanceRecord?> getSequenceInstance({
    required String sequenceId,
    DateTime? date,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final targetDate = date ?? DateTime.now();
    final dateStart =
        DateTime(targetDate.year, targetDate.month, targetDate.day);
    try {
      final sequenceInstanceQuery =
          SequenceInstanceRecord.collectionForUser(uid)
              .where('sequenceId', isEqualTo: sequenceId)
              .where('date', isEqualTo: dateStart)
              .where('isActive', isEqualTo: true)
              .limit(1);
      final sequenceInstanceSnapshot = await sequenceInstanceQuery.get();
      if (sequenceInstanceSnapshot.docs.isEmpty) return null;
      return SequenceInstanceRecord.fromSnapshot(
          sequenceInstanceSnapshot.docs.first);
    } catch (e) {
      return null;
    }
  }
}
