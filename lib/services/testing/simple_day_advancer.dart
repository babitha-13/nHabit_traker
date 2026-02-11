import 'package:habit_tracker/features/Home/CatchUp/logic/day_end_processor.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Simple day advancer for testing day-end processing
/// Just advances the date and triggers day-end processing
class SimpleDayAdvancer {
  static DateTime _currentDate = DateTime.now();

  /// Get the current simulated date
  static DateTime get currentDate => _currentDate;

  /// Advance to the next day and process day-end
  static Future<void> advanceToNextDay() async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) {
      throw Exception('No authenticated user');
    }
    print(
        'SimpleDayAdvancer: Processing day-end for ${_currentDate.toIso8601String()}');
    // Enable test mode in DateService
    DateService.enableTestMode(_currentDate);
    // Process day-end for current date
    await DayEndProcessor.processDayEnd(
      userId: userId,
      targetDate: _currentDate,
    );
    // Advance to next day
    _currentDate = _currentDate.add(const Duration(days: 1));
    // Update DateService with new test date
    DateService.updateTestDate(_currentDate);
    print('SimpleDayAdvancer: Advanced to ${_currentDate.toIso8601String()}');
  }

  /// Reset to real current date
  static void resetToRealTime() {
    _currentDate = DateTime.now();
    DateService.disableTestMode();
  }

  /// Get status
  static Map<String, dynamic> getStatus() {
    return {
      'currentDate': _currentDate.toIso8601String(),
      'realDate': DateTime.now().toIso8601String(),
    };
  }
}
