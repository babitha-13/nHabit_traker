import 'package:cloud_firestore/cloud_firestore.dart';

/// Helper class for syncing template data with instance operations
/// Centralizes template update patterns that occur after instance operations
class TemplateSyncHelper {
  /// Update the template's due date
  ///
  /// This is commonly used after completing an instance to update the template
  /// with the next due date for recurring activities.
  ///
  /// [templateRef] - Reference to the template document
  /// [dueDate] - The new due date (or null to clear it)
  static Future<void> updateTemplateDueDate({
    required DocumentReference templateRef,
    required DateTime? dueDate,
  }) async {
    try {
      await templateRef.update({'dueDate': dueDate});
    } catch (e) {
      // Log error but don't fail the operation if template update fails
      // The instance operation should still succeed even if template sync fails
      print('Failed to update template due date: $e');
      // Re-throw if you want the caller to handle it
      // For now, we'll silently fail to not break instance operations
    }
  }

  /// Update template status and active state
  ///
  /// Used when completing one-time tasks or when activities are no longer active
  ///
  /// [templateRef] - Reference to the template document
  /// [isActive] - Whether the template should be active
  /// [status] - Optional status to set (e.g., 'complete')
  static Future<void> updateTemplateStatus({
    required DocumentReference templateRef,
    bool? isActive,
    String? status,
  }) async {
    try {
      final updates = <String, dynamic>{
        'lastUpdated': DateTime.now(),
      };
      if (isActive != null) {
        updates['isActive'] = isActive;
      }
      if (status != null) {
        updates['status'] = status;
      }
      await templateRef.update(updates);
    } catch (e) {
      print('Failed to update template status: $e');
      // Silently fail to not break instance operations
    }
  }
}
