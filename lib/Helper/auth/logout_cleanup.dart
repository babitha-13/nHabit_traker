import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/core/constants.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/daily_notification_scheduler.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/features/Timer/Helpers/TimeManager.dart';
import 'package:habit_tracker/features/Timer/Helpers/timer_notification_service.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/core/services/local_storage_services.dart';

Future<void> handleLogoutCleanup({String? userId}) async {
  // Stop in-app observers and optimistic operations.
  NotificationCenter.reset();
  OptimisticOperationTracker.clearAll();

  // Clear local caches.
  FirestoreCacheService().invalidateAllCache();

  // Stop timers and timer notifications.
  TimerManager().clear();
  await TimerNotificationService.shutdown();

  // Cancel local notifications.
  await NotificationService.cancelAllNotifications();
  await NotificationService.cancelDayEndNotifications();
  await DailyNotificationScheduler.cancelMorningReminder();
  await DailyNotificationScheduler.cancelEveningReminder();

  if (userId != null && userId.isNotEmpty) {
    await EngagementReminderScheduler.cancelEngagementReminders(userId);
  }
}

Future<void> performLogout({
  required SharedPref sharedPref,
  required Future<void> Function() onLoggedOut,
}) async {
  final userId = currentUserUid;

  // Ensure all optimistic progress and pending offline writes are synced
  // before clearing the auth token, avoiding PERMISSION_DENIED data loss.
  try {
    await FirebaseFirestore.instance.waitForPendingWrites();
  } catch (e) {
    debugPrint('Error waiting for pending writes during logout: $e');
  }

  await handleLogoutCleanup(userId: userId);
  await authManager.signOut();
  await sharedPref.remove(SharedPreference.name.sUserDetails);
  await onLoggedOut();
}
