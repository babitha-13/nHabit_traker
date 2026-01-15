import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';

/// Centralized helper for broadcasting activity template level events.
/// Use this when template metadata (e.g., name, time estimate) changes and
/// other parts of the app (calendar, routines) need to react immediately.
class ActivityTemplateEvents {
  static const String templateUpdated = 'activityTemplateUpdated';

  /// Broadcast that an activity template was updated.
  /// [context] can carry optional metadata like which fields changed.
  static void broadcastTemplateUpdated({
    required String templateId,
    Map<String, dynamic>? context,
  }) {
    NotificationCenter.post(templateUpdated, {
      'templateId': templateId,
      if (context != null) ...context,
    });
  }
}
