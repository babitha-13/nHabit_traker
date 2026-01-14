import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_preferences_service.dart';

/// Service for tracking app usage and engagement
/// All business logic for engagement tracking is centralized here (#REFACTOR_NOW compliance)
class EngagementTracker {
  /// Record that the app was opened
  static Future<void> recordAppOpened(String userId) async {
    try {
      final now = DateTime.now();
      await UsersRecord.collection.doc(userId).update(
            createUsersRecordData(
              lastAppOpened: now,
            ),
          );
    } catch (e) {
      print('EngagementTracker: Error recording app opened: $e');
    }
  }

  /// Get the last time the app was opened
  static Future<DateTime?> getLastOpenedTime(String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return null;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      return userData.lastAppOpened;
    } catch (e) {
      print('EngagementTracker: Error getting last opened time: $e');
      return null;
    }
  }

  /// Check if an engagement reminder should be sent
  /// Returns true if app hasn't been opened for the configured threshold hours
  static Future<bool> shouldSendEngagementReminder(String userId) async {
    try {
      // Check if engagement reminders are enabled
      final isEnabled =
          await NotificationPreferencesService.isEngagementReminderEnabled(
              userId);
      if (!isEnabled) {
        return false;
      }

      final lastOpened = await getLastOpenedTime(userId);
      if (lastOpened == null) {
        // Never opened before, don't send reminder immediately
        return false;
      }

      final thresholdHours =
          await NotificationPreferencesService.getEngagementReminderHours(
              userId);
      final now = DateTime.now();
      final hoursSinceLastOpened = now.difference(lastOpened).inHours;

      // Check if it's been longer than the threshold
      return hoursSinceLastOpened >= thresholdHours;
    } catch (e) {
      print('EngagementTracker: Error checking engagement reminder: $e');
      return false;
    }
  }

  /// Get hours since last app opened
  static Future<int> getHoursSinceLastOpened(String userId) async {
    try {
      final lastOpened = await getLastOpenedTime(userId);
      if (lastOpened == null) {
        return 0;
      }
      final now = DateTime.now();
      return now.difference(lastOpened).inHours;
    } catch (e) {
      print('EngagementTracker: Error getting hours since last opened: $e');
      return 0;
    }
  }

  /// Check if user is in quiet hours (default: 10 PM - 6 AM)
  static Future<bool> isInQuietHours(String userId) async {
    try {
      final prefs =
          await NotificationPreferencesService.getUserNotificationPreferences(
              userId);
      final quietStart = prefs['quiet_hours_start'] as int? ?? 22; // 10 PM
      final quietEnd = prefs['quiet_hours_end'] as int? ?? 6; // 6 AM

      final now = DateTime.now();
      final currentHour = now.hour;

      // Handle quiet hours that span midnight (e.g., 10 PM - 6 AM)
      if (quietStart > quietEnd) {
        // Quiet hours span midnight
        return currentHour >= quietStart || currentHour < quietEnd;
      } else {
        // Quiet hours within same day
        return currentHour >= quietStart && currentHour < quietEnd;
      }
    } catch (e) {
      print('EngagementTracker: Error checking quiet hours: $e');
      return false;
    }
  }
}
