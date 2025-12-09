import 'package:habit_tracker/Helper/backend/day_end_processor.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';

/// Service for manual day-end processing
/// Provides method to manually trigger day-end processing
class BackgroundScheduler {
  static bool _isProcessing = false;

  /// Manually trigger day-end processing
  /// This is the only way to process day-end - all processing is manual
  /// When called manually (e.g., from Queue page), this will close expired instances
  static Future<void> triggerDayEndProcessing({DateTime? targetDate}) async {
    final currentUser = currentUserUid;
    if (currentUser.isEmpty) {
      throw Exception('No authenticated user');
    }
    if (_isProcessing) {
      throw Exception('Processing is already in progress');
    }
    _isProcessing = true;
    try {
      final date = targetDate ?? DateService.yesterdayStart;
      await DayEndProcessor.processDayEnd(
          userId: currentUser, targetDate: date, closeInstances: true);
    } finally {
      _isProcessing = false;
    }
  }

  /// Check if day-end processing is currently running
  static bool get isProcessing => _isProcessing;
}
