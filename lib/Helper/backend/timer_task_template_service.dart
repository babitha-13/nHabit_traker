import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';

/// Service to manage the "Timer Task" template
/// This template is used as the base for all timer-generated task instances
class TimerTaskTemplateService {
  static ActivityRecord? _cachedTemplate;
  static DocumentReference? _cachedTemplateRef;

  /// Get or create the Timer Task template
  /// Returns the template ActivityRecord and its DocumentReference
  static Future<Map<String, dynamic>> getOrCreateTimerTaskTemplate() async {
    // Return cached template if available
    if (_cachedTemplate != null && _cachedTemplateRef != null) {
      return {
        'template': _cachedTemplate!,
        'templateRef': _cachedTemplateRef!,
      };
    }

    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) {
      throw Exception('User not authenticated');
    }

    try {
      // First, try to find existing Timer Task template
      final existingTemplates = await queryActivitiesRecordOnce(
        userId: currentUser.uid,
      );

      final timerTaskTemplates = existingTemplates
          .where((template) => template.name == 'Timer Task')
          .toList();

      if (timerTaskTemplates.isNotEmpty) {
        final template = timerTaskTemplates.first;
        _cachedTemplate = template;
        _cachedTemplateRef = template.reference;
        return {
          'template': template,
          'templateRef': template.reference,
        };
      }

      // Create new Timer Task template if it doesn't exist
      final inboxCategory = await getOrCreateInboxCategory();

      final templateRef = await createActivity(
        name: 'Timer Task',
        description: 'Template for timer-generated tasks',
        categoryName: inboxCategory.name,
        trackingType: 'duration',
        target: 0, // Duration will be set per instance
        unit: 'minutes',
        priority: 1,
        categoryType: 'task',
      );

      final template = await ActivityRecord.getDocumentOnce(templateRef);
      _cachedTemplate = template;
      _cachedTemplateRef = templateRef;

      return {
        'template': template,
        'templateRef': templateRef,
      };
    } catch (e) {
      print('Error getting/creating Timer Task template: $e');
      rethrow;
    }
  }

  /// Clear cached template (useful for testing or if template changes)
  static void clearCache() {
    _cachedTemplate = null;
    _cachedTemplateRef = null;
  }
}
