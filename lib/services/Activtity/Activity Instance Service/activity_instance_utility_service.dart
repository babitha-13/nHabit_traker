import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'activity_instance_helper_service.dart';
import 'activity_instance_creation_service.dart';

/// Service for utility methods and helper operations
class ActivityInstanceUtilityService {
  /// Tries hard delete first; falls back to soft deactivate if delete is denied.
  /// Returns true when fallback update was used.
  static Future<bool> _deleteOrDeactivateInstance(
    ActivityInstanceRecord instance,
  ) async {
    try {
      await instance.reference.delete();
      return false;
    } catch (deleteError) {
      try {
        await instance.reference.update({
          'isActive': false,
          'lastUpdated': DateTime.now(),
        });
        return true;
      } catch (updateError) {
        throw Exception(
          'Failed to delete or deactivate instance ${instance.reference.id}. '
          'deleteError=$deleteError, updateError=$updateError',
        );
      }
    }
  }

  /// Test method to manually create an instance (for debugging)
  static Future<void> testCreateInstance({
    required String templateId,
    String? userId,
  }) async {
    try {
      // Get the template
      final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
      final templateRef = ActivityRecord.collectionForUser(uid).doc(templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      // Create instance
      await ActivityInstanceCreationService.createActivityInstance(
        templateId: templateId,
        template: template,
        userId: uid,
      );
    } catch (e) {
      // Log error in test method - this is for debugging only
      print('Error in testCreateInstance: $e');
    }
  }

  /// Get all instances for a specific template (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final result = await query.get();
      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      instances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return -1;
        if (b.dueDate == null) return 1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return instances;
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getInstancesForTemplate ($templateId)',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      print('❌ Error in getInstancesForTemplate: $e');
      rethrow; // Re-throw to let the caller handle/log it excessively if needed
    }
  }

  /// Get all instances for a user (for debugging/testing)
  static Future<List<ActivityInstanceRecord>> getAllInstances({
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid);
      final result = await query.get();
      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
      instances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return -1;
        if (b.dueDate == null) return 1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      return instances;
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'getAllInstances',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      return [];
    }
  }

  /// Delete all instances for a template (cleanup utility)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    print(
        'ActivityInstanceUtilityService: deleteInstancesForTemplate called with templateId: $templateId');
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      var fallbackCount = 0;
      print(
          'ActivityInstanceUtilityService: Found ${instances.docs.length} instances to delete for templateId $templateId');
      for (final doc in instances.docs) {
        final deletedInstance = ActivityInstanceRecord.fromSnapshot(doc);
        print(
            'ActivityInstanceUtilityService: Deleting instance doc: ${doc.id}');
        final usedFallback = await _deleteOrDeactivateInstance(deletedInstance);
        if (usedFallback) {
          fallbackCount += 1;
        }
        InstanceEvents.broadcastInstanceDeleted(deletedInstance);
      }
      print(
          'ActivityInstanceUtilityService: Finished deleting instances for templateId $templateId (fallbacks=$fallbackCount)');
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'deleteInstancesForTemplate ($templateId)',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  /// Delete future instances for a template (for stopping recurring activities)
  static Future<void> deleteFutureInstances({
    required String templateId,
    required DateTime fromDate,
    String? userId,
  }) async {
    final uid = userId ?? ActivityInstanceHelperService.getCurrentUserId();
    try {
      // Fetch by templateId and filter in memory to avoid extra index requirements.
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);

      final result = await query.get();
      final targetDate = DateTime(fromDate.year, fromDate.month, fromDate.day);
      final instances = result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .where((instance) {
        // For habits, belongsToDate is the authoritative scheduling date.
        // Fall back to dueDate then createdTime for task instances.
        final dateToCompare =
            instance.belongsToDate ?? instance.dueDate ?? instance.createdTime;
        final isPending = instance.status == 'pending';
        if (dateToCompare == null) {
          // Pending items without a date should still be removed when stopping.
          return isPending;
        }

        // Compare just dates to be safe
        final instanceDate = DateTime(
            dateToCompare.year, dateToCompare.month, dateToCompare.day);
        // Remove all pending items (including older overdue ones) and all
        // dated items on/after the cut-off date.
        return instanceDate.isAtSameMomentAs(targetDate) ||
            instanceDate.isAfter(targetDate) ||
            isPending;
      }).toList();

      var fallbackCount = 0;
      for (final instance in instances) {
        final usedFallback = await _deleteOrDeactivateInstance(instance);
        if (usedFallback) {
          fallbackCount += 1;
        }
        InstanceEvents.broadcastInstanceDeleted(instance);
      }
      print(
          'ActivityInstanceUtilityService: Finished deleting future instances for templateId $templateId from $targetDate (count=${instances.length}, fallbacks=$fallbackCount)');
    } catch (e, stackTrace) {
      logFirestoreQueryError(
        e,
        queryDescription: 'deleteFutureInstances ($templateId)',
        collectionName: 'activity_instances',
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }
}
