import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

class SequenceOrderService {
  /// Initialize order values for sequences that don't have them
  static Future<void> initializeOrderValues(
    List<SequenceRecord> sequences,
  ) async {
    try {
      final batch = FirebaseFirestore.instance.batch();
      final userId = currentUserUid;
      for (int i = 0; i < sequences.length; i++) {
        final sequence = sequences[i];
        bool needsUpdate = false;
        Map<String, dynamic> updateData = {};
        if (!sequence.hasListOrder()) {
          updateData['listOrder'] = i;
          updateData['lastUpdated'] = DateTime.now();
          needsUpdate = true;
        }
        if (needsUpdate) {
          final sequenceRef =
              SequenceRecord.collectionForUser(userId).doc(sequence.reference.id);
          batch.update(sequenceRef, updateData);
        }
      }
      await batch.commit();
    } catch (e) {
      // Silently fail - order initialization is not critical
    }
  }

  /// Get the next order index for a new sequence
  static Future<int> getNextOrderIndex({String? userId}) async {
    try {
      final uid = userId ?? currentUserUid;
      if (uid.isEmpty) return 0;
      final query = SequenceRecord.collectionForUser(uid)
          .where('isActive', isEqualTo: true)
          .orderBy('listOrder', descending: true)
          .limit(1);
      final result = await query.get();
      if (result.docs.isEmpty) return 0;
      final lastSequence = SequenceRecord.fromSnapshot(result.docs.first);
      return (lastSequence.hasListOrder() ? lastSequence.listOrder : 0) + 1;
    } catch (e) {
      // If orderBy fails, count existing sequences
      try {
        final query = SequenceRecord.collectionForUser(
            userId ?? currentUserUid).where('isActive', isEqualTo: true);
        final result = await query.get();
        return result.docs.length;
      } catch (e2) {
        return 0;
      }
    }
  }

  /// Reorder sequences after drag operation
  static Future<void> reorderSequences(
    List<SequenceRecord> sequences,
    int oldIndex,
    int newIndex,
  ) async {
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);
    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // sequences is already in the desired order; just persist the order
        final batch = FirebaseFirestore.instance.batch();
        final userId = currentUserUid;
        final List<String> sequenceIds = [];
        for (int i = 0; i < sequences.length; i++) {
          final sequence = sequences[i];
          final sequenceRef =
              SequenceRecord.collectionForUser(userId).doc(sequence.reference.id);
          sequenceIds.add(sequence.reference.id);
          batch.update(sequenceRef, {
            'listOrder': i,
            'lastUpdated': DateTime.now(),
          });
        }
        // Commit the batch
        await batch.commit();
        // Validate that the updates were actually saved
        await _validateOrderUpdates(sequenceIds, sequences);
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
    List<String> sequenceIds,
    List<SequenceRecord> expectedSequences,
  ) async {
    try {
      final userId = currentUserUid;
      final List<Future<DocumentSnapshot>> futures = [];
      // Fetch all sequences to validate their order values
      for (final sequenceId in sequenceIds) {
        final sequenceRef =
            SequenceRecord.collectionForUser(userId).doc(sequenceId);
        futures.add(sequenceRef.get());
      }
      final snapshots = await Future.wait(futures);
      // Validate each sequence's order value
      for (int i = 0; i < snapshots.length; i++) {
        final snapshot = snapshots[i];
        if (!snapshot.exists) {
          throw Exception('Sequence ${sequenceIds[i]} not found after update');
        }
        final data = snapshot.data() as Map<String, dynamic>;
        final actualOrder = data['listOrder'] as int?;
        final expectedOrder = i;
        if (actualOrder != expectedOrder) {
          throw Exception(
              'Order validation failed for ${sequenceIds[i]}: expected $expectedOrder, got $actualOrder');
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Sort sequences by their order
  static List<SequenceRecord> sortSequencesByOrder(
    List<SequenceRecord> sequences,
  ) {
    final sortedSequences = List<SequenceRecord>.from(sequences);
    sortedSequences.sort((a, b) {
      final orderA = a.listOrder;
      final orderB = b.listOrder;
      if (orderA != orderB) return orderA.compareTo(orderB);
      return a.name.compareTo(b.name);
    });
    return sortedSequences;
  }
}

