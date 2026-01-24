import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Screens/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';

/// Service for managing persistent timer notifications
class TimerNotificationService {
  static final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  static const String _channelId = 'active_timers';
  static const String _channelName = 'Active Timers';
  static const int _notificationId = 9999; // Fixed ID for timer notification

  static Timer? _updateTimer;
  static bool _isNotificationActive = false;

  /// Initialize the timer notification service
  static Future<void> initialize() async {
    // Create notification channel for Android
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: 'Shows active timer notifications',
      importance:
          Importance.low, // Low importance - persistent but not intrusive
      playSound: false,
      enableVibration: false,
      showBadge: false,
    );

    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Listen to TimerManager changes
    TimerManager().addListener(_onTimerStateChanged);
  }

  /// Handle timer state changes
  static void _onTimerStateChanged() {
    final hasActiveTimers = TimerManager().hasActiveTimers;
    if (hasActiveTimers && !_isNotificationActive) {
      _startNotification();
    } else if (!hasActiveTimers && _isNotificationActive) {
      _stopNotification();
    } else if (_isNotificationActive) {
      _updateNotification();
    }
  }

  /// Start showing persistent notification
  static Future<void> _startNotification() async {
    _isNotificationActive = true;
    await _updateNotification();
    _startUpdateTimer();
  }

  /// Stop showing notification
  static Future<void> _stopNotification() async {
    _isNotificationActive = false;
    _updateTimer?.cancel();
    _updateTimer = null;
    try {
      await _notificationsPlugin.cancel(_notificationId);
    } catch (e) {
      // Ignore errors when canceling
    }
  }

  /// Shutdown timer notifications and detach listeners (used on logout).
  static Future<void> shutdown() async {
    TimerManager().removeListener(_onTimerStateChanged);
    await _stopNotification();
  }

  /// Update notification content
  static Future<void> _updateNotification() async {
    if (!_isNotificationActive) return;

    final activeTimers = TimerManager().activeTimers;
    if (activeTimers.isEmpty) {
      await _stopNotification();
      return;
    }

    // Format timer display
    String title;
    String body;

    if (activeTimers.length == 1) {
      final instance = activeTimers.first;
      title = instance.templateName;
      body = _formatTimerDisplay(instance);
    } else {
      title = '${activeTimers.length} Active Timers';
      final totalTime = activeTimers.fold<int>(
        0,
        (sum, inst) => sum + _getCurrentTime(inst),
      );
      body = 'Total: ${_formatDuration(totalTime)}';
    }

    // Create actions for notification
    final actions = <AndroidNotificationAction>[
      const AndroidNotificationAction(
        'stop_all',
        'Stop All',
        showsUserInterface: false,
      ),
    ];

    try {
      await _notificationsPlugin.show(
        _notificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: 'Shows active timer notifications',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            showWhen: false,
            actions: actions,
            category: AndroidNotificationCategory.status,
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: false,
            presentBadge: false,
            presentSound: false,
          ),
        ),
        payload: 'timer_notification',
      );
    } catch (e) {
      // Ignore notification errors
      debugPrint('Error updating timer notification: $e');
    }
  }

  /// Start periodic timer to update notification
  static void _startUpdateTimer() {
    _updateTimer?.cancel();
    _updateTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _updateNotification();
    });
  }

  /// Get current elapsed time for an instance
  static int _getCurrentTime(ActivityInstanceRecord instance) {
    int totalMilliseconds = instance.accumulatedTime;
    if (instance.isTimerActive && instance.timerStartTime != null) {
      final elapsed =
          DateTime.now().difference(instance.timerStartTime!).inMilliseconds;
      totalMilliseconds += elapsed;
    }
    return totalMilliseconds;
  }

  /// Format timer display for notification
  static String _formatTimerDisplay(ActivityInstanceRecord instance) {
    final totalMilliseconds = _getCurrentTime(instance);
    return _formatDuration(totalMilliseconds);
  }

  /// Format duration in HH:MM:SS or MM:SS format
  static String _formatDuration(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Handle notification action tap
  static Future<void> handleAction(String actionId) async {
    if (actionId == 'stop_all') {
      final activeTimers = TimerManager().activeTimers;
      for (final instance in activeTimers) {
        try {
          await ActivityInstanceService.toggleInstanceTimer(
            instanceId: instance.reference.id,
          );
        } catch (e) {
          // Ignore individual errors
        }
      }
    }
  }

  /// Cleanup
  static void dispose() {
    TimerManager().removeListener(_onTimerStateChanged);
    _updateTimer?.cancel();
    _updateTimer = null;
  }
}
