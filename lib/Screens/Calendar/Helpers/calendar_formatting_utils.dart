import 'package:flutter/material.dart';
import 'package:from_css_color/from_css_color.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';

/// Utility functions for calendar formatting
class CalendarFormattingUtils {
  /// Format duration to human-readable string
  static String formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }

  /// Parse color string to Color object
  static Color parseColor(String colorString) {
    try {
      return fromCssColor(colorString);
    } catch (e) {
      return Colors.blue; // Default color
    }
  }

  /// Parse due time string to DateTime
  static DateTime parseDueTime(String dueTime, DateTime targetDate) {
    final timeOfDay = TimeUtils.stringToTimeOfDay(dueTime);
    if (timeOfDay == null) {
      return DateTime(targetDate.year, targetDate.month, targetDate.day, 9, 0);
    }
    return DateTime(
      targetDate.year,
      targetDate.month,
      targetDate.day,
      timeOfDay.hour,
      timeOfDay.minute,
    );
  }
}
