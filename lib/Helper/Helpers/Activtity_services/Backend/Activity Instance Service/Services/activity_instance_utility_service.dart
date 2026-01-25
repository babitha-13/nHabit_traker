import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';
import 'activity_instance_helper_service.dart';
import 'activity_instance_creation_service.dart';

/// Service for utility methods and helper operations
class ActivityInstanceUtilityService {
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
          .where('templateId', isEqualTo: templateId)
          .orderBy('dueDate', descending: false);
      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
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
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .orderBy('dueDate', descending: false);
      final result = await query.get();
      return result.docs
          .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
          .toList();
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
    try {
      final query = ActivityInstanceRecord.collectionForUser(uid)
          .where('templateId', isEqualTo: templateId);
      final instances = await query.get();
      for (final doc in instances.docs) {
        await doc.reference.delete();
      }
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
}
