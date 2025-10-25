import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';

class SequenceService {
  /// Create a new sequence with items and order
  static Future<DocumentReference> createSequence({
    required String name,
    String? description,
    required List<String> itemIds,
    required List<String> itemOrder,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
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
    final sequenceData = createSequenceRecordData(
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
    );
    return await SequenceRecord.collectionForUser(uid).add(sequenceData);
  }

  /// Update a sequence
  static Future<void> updateSequence({
    required String sequenceId,
    String? name,
    String? description,
    List<String>? itemIds,
    List<String>? itemOrder,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final sequenceRef = SequenceRecord.collectionForUser(uid).doc(sequenceId);
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
    await sequenceRef.update(updateData);
  }

  /// Delete a sequence (soft delete)
  static Future<void> deleteSequence(String sequenceId,
      {String? userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    final sequenceRef = SequenceRecord.collectionForUser(uid).doc(sequenceId);
    await sequenceRef.update({
      'isActive': false,
      'lastUpdated': DateTime.now(),
    });
  }

  /// Get sequence with today's live instances
  static Future<SequenceWithInstances?> getSequenceWithInstances({
    required String sequenceId,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      // Get sequence template
      final sequenceDoc =
          await SequenceRecord.collectionForUser(uid).doc(sequenceId).get();
      if (!sequenceDoc.exists) return null;
      final sequence = SequenceRecord.fromSnapshot(sequenceDoc);
      if (!sequence.isActive) return null;

      // Query ALL instances for the specific items in this sequence
      // This works for habits, tasks, and sequence_items (no category type restriction)
      // Handle Firestore's 10-item limit for whereIn by batching if needed
      final allInstances = <ActivityInstanceRecord>[];
      final itemIds = sequence.itemIds;

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

      // Apply "latest instance per template" logic
      final instancesMap = <String, List<ActivityInstanceRecord>>{};
      for (final instance in allInstances) {
        final templateId = instance.templateId;
        (instancesMap[templateId] ??= []).add(instance);
      }

      // For each template, find the latest actionable instance
      final latestInstances = <String, ActivityInstanceRecord>{};
      for (final itemId in sequence.itemIds) {
        final instances = instancesMap[itemId] ?? [];
        if (instances.isNotEmpty) {
          // Sort instances by due date (earliest first, nulls last)
          instances.sort((a, b) {
            if (a.dueDate == null && b.dueDate == null) return 0;
            if (a.dueDate == null) return 1;
            if (b.dueDate == null) return -1;
            return a.dueDate!.compareTo(b.dueDate!);
          });

          // Find the latest actionable instance (prefer pending, fallback to completed)
          ActivityInstanceRecord? latestInstance;
          for (final instance in instances) {
            if (instance.status == 'pending') {
              latestInstance = instance;
              break;
            }
          }
          // If no pending instance found, use the latest completed/skipped instance
          if (latestInstance == null) {
            for (final instance in instances.reversed) {
              if (instance.status == 'completed' ||
                  instance.status == 'skipped') {
                latestInstance = instance;
                break;
              }
            }
          }
          // If still no instance found, use the first one (fallback)
          if (latestInstance == null && instances.isNotEmpty) {
            latestInstance = instances.first;
          }

          if (latestInstance != null) {
            latestInstances[itemId] = latestInstance;
          }
        }
      }

      return SequenceWithInstances(
        sequence: sequence,
        instances: latestInstances,
      );
    } catch (e) {
      return null;
    }
  }

  /// Create a new sequence item (untracked activity)
  static Future<DocumentReference> createSequenceItem({
    required String name,
    String? description,
    required String trackingType,
    dynamic target,
    String? unit,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    // Create activity with categoryType='sequence_item'
    final activityData = createActivityRecordData(
      name: name,
      categoryName: 'Sequence Items', // Default category for sequence items
      trackingType: trackingType,
      target: target,
      description: description,
      unit: unit,
      isActive: true,
      createdTime: DateTime.now(),
      lastUpdated: DateTime.now(),
      categoryType: 'sequence_item', // Special type
    );
    return await ActivityRecord.collectionForUser(uid).add(activityData);
  }

  /// Create an instance for a sequence item on-the-fly
  static Future<ActivityInstanceRecord?> createInstanceForSequenceItem({
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

  /// Reset all completed sequence_item instances in a sequence
  /// Creates new pending instances for sequence_items only
  /// Leaves habits and tasks untouched
  static Future<int> resetSequenceItems({
    required String sequenceId,
    required Map<String, ActivityInstanceRecord> currentInstances,
    required List<String> itemTypes,
    required List<String> itemIds,
    String? userId,
  }) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';

    int resetCount = 0;

    try {
      // Iterate through items and reset only sequence_items that are completed
      for (int i = 0; i < itemIds.length; i++) {
        final itemId = itemIds[i];
        final itemType = i < itemTypes.length ? itemTypes[i] : 'habit';

        // Only process sequence_items
        if (itemType != 'sequence_item') continue;

        final instance = currentInstances[itemId];

        // Only reset if instance exists and is completed/skipped
        if (instance != null &&
            (instance.status == 'completed' || instance.status == 'skipped')) {
          // Create new pending instance
          final newInstance = await createInstanceForSequenceItem(
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

  /// Get all sequences for a user
  static Future<List<SequenceRecord>> getUserSequences({String? userId}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final uid = userId ?? currentUser?.uid ?? '';
    try {
      final query = SequenceRecord.collectionForUser(uid)
          .where('isActive', isEqualTo: true)
          .orderBy('name');
      final result = await query.get();
      return result.docs
          .map((doc) => SequenceRecord.fromSnapshot(doc))
          .toList();
    } catch (e) {
      return [];
    }
  }
}

/// Data class to hold sequence with its instances
class SequenceWithInstances {
  final SequenceRecord sequence;
  final Map<String, ActivityInstanceRecord> instances;
  SequenceWithInstances({
    required this.sequence,
    required this.instances,
  });

  /// Get instances in the correct order
  List<ActivityInstanceRecord?> get orderedInstances {
    final ordered = <ActivityInstanceRecord?>[];
    for (final itemId in sequence.itemOrder) {
      ordered.add(instances[itemId]);
    }
    return ordered;
  }

  /// Get items that don't have instances yet
  List<String> get missingInstances {
    return sequence.itemIds
        .where((itemId) => !instances.containsKey(itemId))
        .toList();
  }
}
