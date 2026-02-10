import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';

/// Information about a duplicate group
class DuplicateGroup {
  final String templateName;
  final DateTime? dueDate;
  final ActivityInstanceRecord instanceToKeep;
  final List<ActivityInstanceRecord> instancesToDelete;

  DuplicateGroup({
    required this.templateName,
    required this.dueDate,
    required this.instanceToKeep,
    required this.instancesToDelete,
  });
}

/// Results from scanning for duplicates
class DuplicateScanResults {
  final int totalInstancesScanned;
  final int instancesWithNullDueDate;
  final int duplicateGroupsFound;
  final List<DuplicateGroup> duplicateGroups;
  final Map<String, int> duplicatesPerTemplate;
  final List<String> instanceIdsToDelete;

  DuplicateScanResults({
    required this.totalInstancesScanned,
    required this.instancesWithNullDueDate,
    required this.duplicateGroupsFound,
    required this.duplicateGroups,
    required this.duplicatesPerTemplate,
    required this.instanceIdsToDelete,
  });

  /// Print detailed scan statistics to console
  void printScanStats() {
    print('═══════════════════════════════════════════════════════════');
    print('🔍 DUPLICATE INSTANCE SCAN RESULTS');
    print('═══════════════════════════════════════════════════════════');
    print('Total instances scanned: $totalInstancesScanned');
    print('Instances with null dueDate (skipped): $instancesWithNullDueDate');
    print('Duplicate groups found: $duplicateGroupsFound');
    print('Total instances to delete: ${instanceIdsToDelete.length}');
    print('');

    if (duplicatesPerTemplate.isNotEmpty) {
      print('📊 Duplicates per template:');
      duplicatesPerTemplate.forEach((templateName, count) {
        print('  • $templateName: $count duplicate(s)');
      });
      print('');
    }

    if (duplicateGroups.isNotEmpty) {
      print('📋 Duplicate groups details:');
      for (final group in duplicateGroups) {
        final dateStr =
            group.dueDate?.toIso8601String().split('T')[0] ?? 'null';
        print('  • ${group.templateName} (dueDate: $dateStr)');
        print(
            '    Keeping: ${group.instanceToKeep.reference.id} (status: ${group.instanceToKeep.status}, created: ${group.instanceToKeep.createdTime})');
        print('    Deleting: ${group.instancesToDelete.length} instance(s)');
        for (final inst in group.instancesToDelete) {
          print(
              '      - ${inst.reference.id} (status: ${inst.status}, created: ${inst.createdTime})');
        }
      }
      print('');
    }

    if (instanceIdsToDelete.isNotEmpty) {
      print('🗑️  Instance IDs to delete (${instanceIdsToDelete.length}):');
      for (int i = 0; i < instanceIdsToDelete.length && i < 20; i++) {
        print('  • ${instanceIdsToDelete[i]}');
      }
      if (instanceIdsToDelete.length > 20) {
        print('  ... and ${instanceIdsToDelete.length - 20} more');
      }
    }

    print('═══════════════════════════════════════════════════════════');
  }
}

/// Statistics from duplicate instance cleanup
class DuplicateCleanupStats {
  final int totalInstancesScanned;
  final int instancesWithNullDueDate;
  final int duplicateGroupsFound;
  final int totalInstancesDeleted;
  final int totalInstancesKept;
  final Map<String, int> duplicatesPerTemplate;
  final List<String> deletedInstanceIds;

  DuplicateCleanupStats({
    required this.totalInstancesScanned,
    required this.instancesWithNullDueDate,
    required this.duplicateGroupsFound,
    required this.totalInstancesDeleted,
    required this.totalInstancesKept,
    required this.duplicatesPerTemplate,
    required this.deletedInstanceIds,
  });

  /// Print detailed statistics to console
  void printStats() {
    print('═══════════════════════════════════════════════════════════');
    print('🔍 DUPLICATE INSTANCE CLEANUP STATISTICS');
    print('═══════════════════════════════════════════════════════════');
    print('Total instances scanned: $totalInstancesScanned');
    print('Instances with null dueDate (skipped): $instancesWithNullDueDate');
    print('Duplicate groups found: $duplicateGroupsFound');
    print('Total instances deleted: $totalInstancesDeleted');
    print('Total instances kept: $totalInstancesKept');
    print('');

    if (duplicatesPerTemplate.isNotEmpty) {
      print('📊 Duplicates per template:');
      duplicatesPerTemplate.forEach((templateName, count) {
        print('  • $templateName: $count duplicate(s)');
      });
      print('');
    }

    if (deletedInstanceIds.isNotEmpty) {
      print('🗑️  Deleted instance IDs (${deletedInstanceIds.length}):');
      for (int i = 0; i < deletedInstanceIds.length && i < 20; i++) {
        print('  • ${deletedInstanceIds[i]}');
      }
      if (deletedInstanceIds.length > 20) {
        print('  ... and ${deletedInstanceIds.length - 20} more');
      }
    }

    print('═══════════════════════════════════════════════════════════');
  }
}

/// Service for cleaning up duplicate activity instances
class DuplicateInstanceCleanup {
  /// Normalize a DateTime to date only (year, month, day)
  static DateTime? normalizeDate(DateTime? date) {
    if (date == null) return null;
    return DateTime(date.year, date.month, date.day);
  }

  /// Create a key for grouping instances (templateName + normalized dueDate)
  static String? createGroupKey(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return null;
    final normalizedDate = normalizeDate(instance.dueDate);
    if (normalizedDate == null) return null;
    return '${instance.templateName}|${normalizedDate.toIso8601String().split('T')[0]}';
  }

  /// Determine which instance to keep from a group
  /// Priority: 1) Completed instance, 2) Oldest instance (by createdTime)
  static ActivityInstanceRecord selectInstanceToKeep(
      List<ActivityInstanceRecord> instances) {
    // First, try to find a completed instance
    final completedInstances =
        instances.where((inst) => inst.status == 'completed').toList();

    if (completedInstances.isNotEmpty) {
      // If multiple completed instances, keep the oldest one
      completedInstances.sort((a, b) {
        final aTime = a.createdTime ?? DateTime(1970);
        final bTime = b.createdTime ?? DateTime(1970);
        return aTime.compareTo(bTime);
      });
      return completedInstances.first;
    }

    // No completed instances, keep the oldest one
    instances.sort((a, b) {
      final aTime = a.createdTime ?? DateTime(1970);
      final bTime = b.createdTime ?? DateTime(1970);
      return aTime.compareTo(bTime);
    });
    return instances.first;
  }

  /// Scan for duplicate instances (does not delete)
  /// Returns scan results with details about duplicates found
  static Future<DuplicateScanResults> scanForDuplicates(String userId) async {
    print('🔍 Starting duplicate instance scan for user: $userId');

    int totalInstancesScanned = 0;
    int instancesWithNullDueDate = 0;
    final List<DuplicateGroup> duplicateGroups = [];
    final Map<String, int> duplicatesPerTemplate = {};
    final List<String> instanceIdsToDelete = [];

    try {
      // Query all activity instances for the user
      print('📥 Querying all activity instances...');
      final query = ActivityInstanceRecord.collectionForUser(userId);
      final snapshot = await query.get();
      totalInstancesScanned = snapshot.docs.length;
      print('   Found $totalInstancesScanned total instances');

      // Group instances by templateName + normalized dueDate
      final Map<String, List<ActivityInstanceRecord>> groups = {};

      for (final doc in snapshot.docs) {
        final instance = ActivityInstanceRecord.fromSnapshot(doc);

        // Skip instances with null dueDate
        if (instance.dueDate == null) {
          instancesWithNullDueDate++;
          continue;
        }

        final groupKey = createGroupKey(instance);
        if (groupKey == null) {
          instancesWithNullDueDate++;
          continue;
        }

        if (!groups.containsKey(groupKey)) {
          groups[groupKey] = [];
        }
        groups[groupKey]!.add(instance);
      }

      print('   Grouped into ${groups.length} unique groups');
      print('   Skipped $instancesWithNullDueDate instances with null dueDate');

      // Find duplicate groups (groups with more than 1 instance)
      final duplicateGroupEntries =
          groups.entries.where((entry) => entry.value.length > 1).toList();

      print('   Found ${duplicateGroupEntries.length} duplicate groups');

      if (duplicateGroupEntries.isEmpty) {
        print('✅ No duplicates found.');
        return DuplicateScanResults(
          totalInstancesScanned: totalInstancesScanned,
          instancesWithNullDueDate: instancesWithNullDueDate,
          duplicateGroupsFound: 0,
          duplicateGroups: [],
          duplicatesPerTemplate: {},
          instanceIdsToDelete: [],
        );
      }

      // Process each duplicate group
      for (final groupEntry in duplicateGroupEntries) {
        final instances = groupEntry.value;
        final instanceToKeep = selectInstanceToKeep(instances);
        final instancesToDelete = instances
            .where((inst) => inst.reference.id != instanceToKeep.reference.id)
            .toList();

        // Track statistics
        final templateName = instanceToKeep.templateName;
        duplicatesPerTemplate[templateName] =
            (duplicatesPerTemplate[templateName] ?? 0) +
                instancesToDelete.length;

        // Add to delete list
        for (final instance in instancesToDelete) {
          instanceIdsToDelete.add(instance.reference.id);
        }

        // Create duplicate group info
        duplicateGroups.add(DuplicateGroup(
          templateName: templateName,
          dueDate: normalizeDate(instanceToKeep.dueDate),
          instanceToKeep: instanceToKeep,
          instancesToDelete: instancesToDelete,
        ));
      }

      // Create and return scan results
      final results = DuplicateScanResults(
        totalInstancesScanned: totalInstancesScanned,
        instancesWithNullDueDate: instancesWithNullDueDate,
        duplicateGroupsFound: duplicateGroups.length,
        duplicateGroups: duplicateGroups,
        duplicatesPerTemplate: duplicatesPerTemplate,
        instanceIdsToDelete: instanceIdsToDelete,
      );

      results.printScanStats();
      return results;
    } catch (e, stackTrace) {
      print('❌ Error during duplicate scan: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Delete duplicate instances based on scan results
  /// Returns statistics about the deletion operation
  static Future<DuplicateCleanupStats> deleteDuplicates(
      String userId, DuplicateScanResults scanResults) async {
    print('🗑️  Starting duplicate instance deletion for user: $userId');

    if (scanResults.instanceIdsToDelete.isEmpty) {
      print('⚠️  No instances to delete.');
      return DuplicateCleanupStats(
        totalInstancesScanned: scanResults.totalInstancesScanned,
        instancesWithNullDueDate: scanResults.instancesWithNullDueDate,
        duplicateGroupsFound: scanResults.duplicateGroupsFound,
        totalInstancesDeleted: 0,
        totalInstancesKept: scanResults.duplicateGroupsFound,
        duplicatesPerTemplate: scanResults.duplicatesPerTemplate,
        deletedInstanceIds: [],
      );
    }

    try {
      // Get references for instances to delete
      final List<DocumentReference> toDelete = [];
      for (final instanceId in scanResults.instanceIdsToDelete) {
        toDelete.add(
            ActivityInstanceRecord.collectionForUser(userId).doc(instanceId));
      }

      // Delete duplicates using batch operations (Firestore limit: 500 per batch)
      print('🗑️  Deleting ${toDelete.length} duplicate instances...');

      const batchSize = 500;
      int batchCount = 0;

      for (int i = 0; i < toDelete.length; i += batchSize) {
        batchCount++;
        final batch = FirebaseFirestore.instance.batch();
        final batchEnd =
            (i + batchSize < toDelete.length) ? i + batchSize : toDelete.length;

        for (int j = i; j < batchEnd; j++) {
          batch.delete(toDelete[j]);
        }

        await batch.commit();
        print('   Batch $batchCount: Deleted ${batchEnd - i} instances');
      }

      print('✅ Successfully deleted all duplicates');

      // Create and return statistics
      final stats = DuplicateCleanupStats(
        totalInstancesScanned: scanResults.totalInstancesScanned,
        instancesWithNullDueDate: scanResults.instancesWithNullDueDate,
        duplicateGroupsFound: scanResults.duplicateGroupsFound,
        totalInstancesDeleted: scanResults.instanceIdsToDelete.length,
        totalInstancesKept: scanResults.duplicateGroupsFound,
        duplicatesPerTemplate: scanResults.duplicatesPerTemplate,
        deletedInstanceIds: scanResults.instanceIdsToDelete,
      );

      stats.printStats();
      return stats;
    } catch (e, stackTrace) {
      print('❌ Error during duplicate deletion: $e');
      print('Stack trace: $stackTrace');
      rethrow;
    }
  }
}
