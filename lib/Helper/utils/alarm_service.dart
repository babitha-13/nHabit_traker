import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';

/// Service for managing system alarms (Android)
/// Note: iOS doesn't support system alarms, so this will use notifications on iOS
class AlarmService {
  static bool _initialized = false;

  /// Initialize the alarm service
  static Future<bool> initialize() async {
    if (_initialized) return true;
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        final initialized = await AndroidAlarmManager.initialize();
        _initialized = initialized;
        return initialized;
      }
      // iOS doesn't support system alarms, return true to allow fallback to notifications
      _initialized = true;
      return true;
    } catch (e) {
      print('AlarmService: Failed to initialize: $e');
      return false;
    }
  }

  /// Schedule a system alarm
  /// Returns true if successful, false otherwise
  static Future<bool> scheduleAlarm({
    required int id,
    required DateTime scheduledTime,
    required String title,
    String? body,
  }) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (!_initialized) {
          final initResult = await initialize();
          if (!initResult) return false;
        }
        // Calculate delay in milliseconds
        final now = DateTime.now();
        final delay = scheduledTime.difference(now).inMilliseconds;
        if (delay <= 0) {
          // Alarm time is in the past
          return false;
        }
        // Schedule the alarm
        final scheduled = await AndroidAlarmManager.oneShot(
          Duration(milliseconds: delay),
          id,
          _alarmCallback,
          exact: true,
          wakeup: true,
          alarmClock: true,
          params: {
            'title': title,
            'body': body ?? title,
          },
        );
        return scheduled;
      } else {
        // iOS doesn't support system alarms
        // This should fall back to notifications
        return false;
      }
    } catch (e) {
      print('AlarmService: Failed to schedule alarm: $e');
      return false;
    }
  }

  /// Cancel a scheduled alarm
  static Future<bool> cancelAlarm(int id) async {
    try {
      if (defaultTargetPlatform == TargetPlatform.android) {
        if (!_initialized) {
          await initialize();
        }
        return await AndroidAlarmManager.cancel(id);
      }
      return true;
    } catch (e) {
      print('AlarmService: Failed to cancel alarm: $e');
      return false;
    }
  }

  /// Reschedule an alarm (cancel old, schedule new)
  static Future<bool> rescheduleAlarm({
    required int id,
    required DateTime scheduledTime,
    required String title,
    String? body,
  }) async {
    await cancelAlarm(id);
    return await scheduleAlarm(
      id: id,
      scheduledTime: scheduledTime,
      title: title,
      body: body,
    );
  }

  /// Check if alarms are supported on this platform
  static bool isSupported() {
    return defaultTargetPlatform == TargetPlatform.android;
  }

  /// Callback function for alarm triggers
  /// This is called when the alarm fires
  @pragma('vm:entry-point')
  static Future<void> _alarmCallback(int id, Map<String, dynamic>? params) async {
    // This callback runs in a separate isolate
    // For now, we'll just print - in a real app, you might want to show
    // a notification or perform other actions
    final title = params?['title'] ?? 'Alarm';
    final body = params?['body'] ?? title;
    print('AlarmService: Alarm triggered - $title: $body');
    // Note: To show notifications from this callback, you'd need to
    // initialize the notification service in this isolate
  }
}

