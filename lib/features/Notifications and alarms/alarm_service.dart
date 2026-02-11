import 'dart:async';
import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:vibration/vibration.dart';

/// Service for managing system alarms (Android)
/// Note: iOS doesn't support system alarms, so this will use notifications on iOS
@pragma('vm:entry-point')
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
    String? payload,
    String? reminderId,
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
            if (payload != null) 'payload': payload,
            if (reminderId != null) 'reminderId': reminderId,
          },
        );
        if (!scheduled) {
          await _fallbackToNotification(
            reminderId: reminderId ?? 'alarm_$id',
            title: title,
            scheduledTime: scheduledTime,
            body: body,
            payload: payload,
          );
        }
        return scheduled;
      } else {
        // iOS doesn't support system alarms
        // This should fall back to notifications
        return false;
      }
    } catch (e) {
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
  static Future<void> _alarmCallback(
      int id, Map<String, dynamic>? params) async {
    final title = params?['title'] ?? 'Alarm';
    final body = params?['body'] ?? title;
    final payload = params?['payload'] as String?;
    final reminderId = params?['reminderId'] as String?;
    try {
      WidgetsFlutterBinding.ensureInitialized();

      // Immediate vibration feedback
      try {
        if (await Vibration.hasVibrator()) {
          Vibration.vibrate(pattern: [0, 1000, 1000, 1000], repeat: 1);
        }
      } catch (e) {
        // Vibration failed, continue without it
      }

      await NotificationService.initialize();

      // Use fullScreenIntent priority for the notification
      // This will trigger the onNotificationResponse callback immediately if app is in foreground,
      // or show the high-priority notification that can launch the activity
      // Include reminderId in payload: ALARM_RINGING:title|body|payload|reminderId
      String ringingPayload = 'ALARM_RINGING:$title|$body|$payload';
      if (reminderId != null) {
        ringingPayload += '|$reminderId';
      }

      await NotificationService.showImmediate(
        id: 'alarm_${reminderId ?? id}',
        title: title,
        body: body,
        payload: ringingPayload, // Special payload format
      );
    } catch (e) {
      // Failed to show notification from alarm callback
    }
    // Note: To show notifications from this callback, you needed to
    // initialize the notification service in this isolate (done above).
  }

  static Future<void> _fallbackToNotification({
    required String reminderId,
    required String title,
    required DateTime scheduledTime,
    String? body,
    String? payload,
  }) async {
    try {
      await NotificationService.scheduleReminder(
        id: reminderId,
        title: title,
        scheduledTime: scheduledTime,
        body: body,
        payload: payload,
      );
    } catch (e) {
      // Fallback notification failed
    }
  }
}
