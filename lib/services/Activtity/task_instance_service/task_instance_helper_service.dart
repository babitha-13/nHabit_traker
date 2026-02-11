import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Helper service for task instance shared utilities
class TaskInstanceHelperService {
  /// Get current user ID
  static String getCurrentUserId() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User not authenticated');
    return user.uid;
  }

  /// Get today's date at midnight (start of day)
  static DateTime getTodayStart() {
    return DateService.todayStart;
  }
}
