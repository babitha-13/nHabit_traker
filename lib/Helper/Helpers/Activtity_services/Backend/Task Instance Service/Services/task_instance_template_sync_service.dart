import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'task_instance_helper_service.dart';

/// Service for template synchronization
class TaskInstanceTemplateSyncService {
  /// When a template is updated (e.g., schedule change), regenerate instances
  static Future<void> syncInstancesOnTemplateUpdate({
    required String templateId,
    required String templateType, // 'task' or 'habit'
    required DateTime? nextDueDate,
    String? userId,
  }) async {
    final uid = userId ?? TaskInstanceHelperService.getCurrentUserId();
    try {
      if (templateType == 'task') {
        await ActivityRecord.collectionForUser(uid).doc(templateId).update({
          'nextDueDate': nextDueDate,
          'lastUpdated': DateTime.now(),
        });
      } else {
        await ActivityRecord.collectionForUser(uid).doc(templateId).update({
          'nextDueDate': nextDueDate,
          'lastUpdated': DateTime.now(),
        });
      }
    } catch (e) {
      // Don't rethrow - this is a sync operation, shouldn't fail the main operation
    }
  }
}
