import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';

/// Service for managing user notification preferences
/// All business logic for notification preferences is centralized here (#REFACTOR_NOW compliance)
class NotificationPreferencesService {
  /// Get user's notification preferences
  static Future<Map<String, dynamic>> getUserNotificationPreferences(
      String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return getDefaultNotificationPreferences();
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      final prefs = userData.notificationPreferences;
      // Merge with defaults to ensure all keys exist
      final defaults = getDefaultNotificationPreferences();
      defaults.addAll(prefs);

      // If wake_up_time or sleep_time exist, use them and recalculate notification times
      if (defaults['wake_up_time'] != null &&
          defaults['wake_up_time'].toString().isNotEmpty) {
        final wakeUpTime =
            TimeUtils.stringToTimeOfDay(defaults['wake_up_time'] as String);
        if (wakeUpTime != null) {
          final morningTime = calculateMorningNotificationTime(wakeUpTime);
          defaults['morning_time'] = TimeUtils.timeOfDayToString(morningTime);
          defaults['quiet_hours_end'] = wakeUpTime.hour;
        }
      }

      if (defaults['sleep_time'] != null &&
          defaults['sleep_time'].toString().isNotEmpty) {
        final sleepTime =
            TimeUtils.stringToTimeOfDay(defaults['sleep_time'] as String);
        if (sleepTime != null) {
          final eveningTime = calculateEveningNotificationTime(sleepTime);
          defaults['evening_time'] = TimeUtils.timeOfDayToString(eveningTime);
          defaults['quiet_hours_start'] = sleepTime.hour;
        }
      }

      // Fallback to stored notification times if wake/sleep times don't exist (backward compatibility)
      if (defaults['morning_time'] == null ||
          defaults['morning_time'].toString().isEmpty) {
        defaults['morning_time'] = userData.morningNotificationTime.isNotEmpty
            ? userData.morningNotificationTime
            : defaults['morning_time'];
      }
      if (defaults['evening_time'] == null ||
          defaults['evening_time'].toString().isEmpty) {
        defaults['evening_time'] = userData.eveningNotificationTime.isNotEmpty
            ? userData.eveningNotificationTime
            : defaults['evening_time'];
      }

      return defaults;
    } catch (e) {
      return getDefaultNotificationPreferences();
    }
  }

  /// Get default notification preferences
  static Map<String, dynamic> getDefaultNotificationPreferences() {
    return {
      'wake_up_time': '07:00', // 7:00 AM default
      'sleep_time': '22:00', // 10:00 PM default
      'morning_time': '08:00', // Calculated: wake up + 1 hour
      'evening_time': '21:00', // Calculated: sleep - 1 hour
      'morning_reminder_enabled': true,
      'evening_reminder_enabled': true,
      'engagement_reminder_enabled': true,
      'engagement_reminder_hours':
          6, // Send reminder if app not opened for 6 hours
      'max_notifications_per_day': 5,
      'quiet_hours_start': 22, // Will be calculated from sleep_time
      'quiet_hours_end': 7, // Will be calculated from wake_up_time
    };
  }

  /// Update notification preferences for a user
  static Future<void> updateNotificationPreferences(
    String userId,
    Map<String, dynamic> preferences,
  ) async {
    try {
      // Extract wake/sleep times and calculate notification times
      final wakeUpTimeString = preferences['wake_up_time'] as String?;
      final sleepTimeString = preferences['sleep_time'] as String?;

      // Calculate notification times if wake/sleep times are provided
      String? morningTimeString;
      String? eveningTimeString;

      if (wakeUpTimeString != null && wakeUpTimeString.isNotEmpty) {
        final wakeUpTime = TimeUtils.stringToTimeOfDay(wakeUpTimeString);
        if (wakeUpTime != null) {
          final morningTime = calculateMorningNotificationTime(wakeUpTime);
          morningTimeString = TimeUtils.timeOfDayToString(morningTime);
        }
      }

      if (sleepTimeString != null && sleepTimeString.isNotEmpty) {
        final sleepTime = TimeUtils.stringToTimeOfDay(sleepTimeString);
        if (sleepTime != null) {
          final eveningTime = calculateEveningNotificationTime(sleepTime);
          eveningTimeString = TimeUtils.timeOfDayToString(eveningTime);
        }
      }

      // Update quiet hours based on sleep/wake times
      final prefsMap = Map<String, dynamic>.from(preferences);
      if (sleepTimeString != null && sleepTimeString.isNotEmpty) {
        final sleepTime = TimeUtils.stringToTimeOfDay(sleepTimeString);
        if (sleepTime != null) {
          prefsMap['quiet_hours_start'] = sleepTime.hour;
        }
      }
      if (wakeUpTimeString != null && wakeUpTimeString.isNotEmpty) {
        final wakeUpTime = TimeUtils.stringToTimeOfDay(wakeUpTimeString);
        if (wakeUpTime != null) {
          prefsMap['quiet_hours_end'] = wakeUpTime.hour;
        }
      }

      // Remove calculated times from preferences map (they're stored separately)
      prefsMap.remove('morning_time');
      prefsMap.remove('evening_time');

      // Update user document
      await UsersRecord.collection.doc(userId).update(
            createUsersRecordData(
              morningNotificationTime: morningTimeString,
              eveningNotificationTime: eveningTimeString,
              notificationPreferences: prefsMap.isNotEmpty ? prefsMap : null,
            ),
          );
    } catch (e) {
      rethrow;
    }
  }

  /// Get wake up time as TimeOfDay
  static Future<TimeOfDay?> getWakeUpTime(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      final timeString = prefs['wake_up_time'] as String?;
      if (timeString == null || timeString.isEmpty) {
        return const TimeOfDay(hour: 7, minute: 0); // Default 7:00 AM
      }
      return TimeUtils.stringToTimeOfDay(timeString);
    } catch (e) {
      return const TimeOfDay(hour: 7, minute: 0);
    }
  }

  /// Get sleep time as TimeOfDay
  static Future<TimeOfDay?> getSleepTime(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      final timeString = prefs['sleep_time'] as String?;
      if (timeString == null || timeString.isEmpty) {
        return const TimeOfDay(hour: 22, minute: 0); // Default 10:00 PM
      }
      return TimeUtils.stringToTimeOfDay(timeString);
    } catch (e) {
      return const TimeOfDay(hour: 22, minute: 0);
    }
  }

  /// Calculate morning notification time (wake up time + 1 hour)
  static TimeOfDay calculateMorningNotificationTime(TimeOfDay wakeUpTime) {
    int hour = wakeUpTime.hour + 1;
    int minute = wakeUpTime.minute;
    if (hour >= 24) {
      hour = hour - 24;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Calculate evening notification time (sleep time - 1 hour)
  static TimeOfDay calculateEveningNotificationTime(TimeOfDay sleepTime) {
    int hour = sleepTime.hour - 1;
    int minute = sleepTime.minute;
    if (hour < 0) {
      hour = hour + 24;
    }
    return TimeOfDay(hour: hour, minute: minute);
  }

  /// Get morning notification time as TimeOfDay (calculated from wake up time)
  static Future<TimeOfDay?> getMorningNotificationTime(String userId) async {
    try {
      final wakeUpTime = await getWakeUpTime(userId);
      if (wakeUpTime == null) {
        return const TimeOfDay(hour: 8, minute: 0); // Default 8:00 AM
      }
      return calculateMorningNotificationTime(wakeUpTime);
    } catch (e) {
      return const TimeOfDay(hour: 8, minute: 0);
    }
  }

  /// Get evening notification time as TimeOfDay (calculated from sleep time)
  static Future<TimeOfDay?> getEveningNotificationTime(String userId) async {
    try {
      final sleepTime = await getSleepTime(userId);
      if (sleepTime == null) {
        return const TimeOfDay(hour: 21, minute: 0); // Default 9:00 PM
      }
      return calculateEveningNotificationTime(sleepTime);
    } catch (e) {
      return const TimeOfDay(hour: 21, minute: 0);
    }
  }

  /// Check if morning reminder is enabled
  static Future<bool> isMorningReminderEnabled(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      return prefs['morning_reminder_enabled'] as bool? ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Check if evening reminder is enabled
  static Future<bool> isEveningReminderEnabled(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      return prefs['evening_reminder_enabled'] as bool? ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Check if engagement reminder is enabled
  static Future<bool> isEngagementReminderEnabled(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      return prefs['engagement_reminder_enabled'] as bool? ?? true;
    } catch (e) {
      return true;
    }
  }

  /// Get engagement reminder hours threshold
  static Future<int> getEngagementReminderHours(String userId) async {
    try {
      final prefs = await getUserNotificationPreferences(userId);
      return prefs['engagement_reminder_hours'] as int? ?? 6;
    } catch (e) {
      return 6;
    }
  }

  /// Check if notification onboarding is completed
  static Future<bool> isNotificationOnboardingCompleted(String userId) async {
    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        return false;
      }
      final userData = UsersRecord.fromSnapshot(userDoc);
      return userData.notificationOnboardingCompleted;
    } catch (e) {
      return false;
    }
  }

  /// Mark notification onboarding as completed
  static Future<void> markNotificationOnboardingCompleted(String userId) async {
    try {
      await UsersRecord.collection.doc(userId).update(
            createUsersRecordData(
              notificationOnboardingCompleted: true,
            ),
          );
    } catch (e) {
      rethrow;
    }
  }
}
