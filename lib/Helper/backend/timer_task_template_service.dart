import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';

/// Service to create unique timer task templates
/// Each timer session gets its own template to avoid duplication
class TimerTaskTemplateService {
  /// Create a new timer task template for each session
  /// Returns the template ActivityRecord and its DocumentReference
  static Future<Map<String, dynamic>> createTimerTaskTemplate() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }
    try {
      // Create a new template for each timer session
      final inboxCategory = await getOrCreateInboxCategory();
      final uid = currentUser.uid;

      // Create template directly without using createActivity (which creates instances)
      final templateData = createActivityRecordData(
        name: 'Timer Task',
        categoryId: inboxCategory.reference.id,
        categoryName: inboxCategory.name,
        categoryType: 'task',
        trackingType: 'time',
        target: 0,
        unit: 'minutes',
        priority: 1,
        description: 'Timer-generated task',
        isActive: true,
        isRecurring: false, // Timer tasks are one-time tasks, not recurring
        createdTime: DateTime.now(),
        lastUpdated: DateTime.now(),
        userId: uid,
      );

      final templateRef =
          await ActivityRecord.collectionForUser(uid).add(templateData);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      return {
        'template': template,
        'templateRef': templateRef,
      };
    } catch (e) {
      rethrow;
    }
  }
}
