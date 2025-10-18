import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:intl/intl.dart';

class WindowDisplayHelper {
  /// Get subtitle text for when the current window ends
  /// Returns formatted text like "Window ends Today", "Window ends Tomorrow", or "Window ends Oct 20"
  static String getWindowEndSubtitle(ActivityInstanceRecord instance) {
    if (instance.windowEndDate == null) {
      return instance.templateCategoryName;
    }

    final today = DateService.todayStart;
    final windowEnd = DateTime(
      instance.windowEndDate!.year,
      instance.windowEndDate!.month,
      instance.windowEndDate!.day,
    );

    if (windowEnd.isAtSameMomentAs(today)) {
      return '${instance.templateCategoryName} • Window ends Today';
    } else if (windowEnd.isAtSameMomentAs(today.add(const Duration(days: 1)))) {
      return '${instance.templateCategoryName} • Window ends Tomorrow';
    } else {
      final formattedDate = DateFormat.MMMd().format(windowEnd);
      return '${instance.templateCategoryName} • Window ends $formattedDate';
    }
  }

  /// Get subtitle text for when the next window starts
  /// Returns formatted text like "Next window starts Tomorrow" or "Next window starts Oct 22"
  static String getNextWindowStartSubtitle(ActivityInstanceRecord instance) {
    if (instance.windowEndDate == null) {
      return instance.templateCategoryName;
    }

    // Calculate next window start = current windowEndDate + 1
    final nextWindowStart =
        instance.windowEndDate!.add(const Duration(days: 1));
    final today = DateService.todayStart;
    final nextStart = DateTime(
      nextWindowStart.year,
      nextWindowStart.month,
      nextWindowStart.day,
    );

    if (nextStart.isAtSameMomentAs(today)) {
      return '${instance.templateCategoryName} • Next window starts Today';
    } else if (nextStart.isAtSameMomentAs(today.add(const Duration(days: 1)))) {
      return '${instance.templateCategoryName} • Next window starts Tomorrow';
    } else {
      final formattedDate = DateFormat.MMMd().format(nextStart);
      return '${instance.templateCategoryName} • Next window starts $formattedDate';
    }
  }

  /// Check if an instance has a completion window
  static bool hasCompletionWindow(ActivityInstanceRecord instance) {
    return instance.windowEndDate != null && instance.windowDuration > 1;
  }
}
