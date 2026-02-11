import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart' as habit_schema;
import 'task_instance_helper_service.dart';

/// Service for utility methods
class TaskInstanceUtilityService {
  static Future<void> updateInstanceProgress({
    required String instanceId,
    required String instanceType, // 'task' or 'habit'
    dynamic currentValue,
    int? accumulatedTime,
    bool? isTimerActive,
    DateTime? timerStartTime,
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    final updateData = <String, dynamic>{
      'lastUpdated': DateTime.now(),
    };
    if (currentValue != null) updateData['currentValue'] = currentValue;
    if (accumulatedTime != null)
      updateData['accumulatedTime'] = accumulatedTime;
    if (isTimerActive != null) updateData['isTimerActive'] = isTimerActive;
    if (timerStartTime != null) updateData['timerStartTime'] = timerStartTime;
    if (instanceType == 'task') {
      await ActivityInstanceRecord.collectionForUser(uid)
          .doc(instanceId)
          .update(updateData);
    } else {
      await habit_schema.HabitInstanceRecord.collectionForUser(uid)
          .doc(instanceId)
          .update(updateData);
    }
  }

  /// Delete all instances for a template (when template is deleted)
  static Future<void> deleteInstancesForTemplate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      if (templateType == 'task') {
        final query = ActivityInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId);
        final instances = await query.get();
        for (final doc in instances.docs) {
          await doc.reference.update({
            'isActive': false,
            'lastUpdated': DateTime.now(),
          });
        }
      } else {
        final query = habit_schema.HabitInstanceRecord.collectionForUser(uid)
            .where('templateId', isEqualTo: templateId);
        final instances = await query.get();
        for (final doc in instances.docs) {
          await doc.reference.update({
            'isActive': false,
            'lastUpdated': DateTime.now(),
          });
        }
      }
    } catch (e) {
      rethrow;
    }
  }
}
