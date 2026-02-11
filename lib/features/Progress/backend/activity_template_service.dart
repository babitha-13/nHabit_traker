import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';

/// Service to fetch ActivityRecord templates for point calculations
/// Encapsulates Firestore access for template data needed by PointsService
class ActivityTemplateService {
  /// Fetch a single ActivityRecord template by ID
  /// Returns null if template not found or on error
  static Future<ActivityRecord?> getTemplateById({
    required String userId,
    required String templateId,
  }) async {
    try {
      final templateRef =
          ActivityRecord.collectionForUser(userId).doc(templateId);
      final template = await ActivityRecord.getDocumentOnce(templateRef);
      return template;
    } catch (e) {
      // Return null on error (template not found, network error, etc.)
      return null;
    }
  }

  /// Fetch multiple ActivityRecord templates by IDs
  /// Returns a map of templateId -> ActivityRecord (only successful fetches)
  static Future<Map<String, ActivityRecord>> getTemplatesByIds({
    required String userId,
    required List<String> templateIds,
  }) async {
    final Map<String, ActivityRecord> templates = {};

    // Fetch templates in parallel
    final futures = templateIds.map((templateId) async {
      final template = await getTemplateById(
        userId: userId,
        templateId: templateId,
      );
      if (template != null) {
        return MapEntry(templateId, template);
      }
      return null;
    });

    final results = await Future.wait(futures);
    for (final result in results) {
      if (result != null) {
        templates[result.key] = result.value;
      }
    }

    return templates;
  }
}
