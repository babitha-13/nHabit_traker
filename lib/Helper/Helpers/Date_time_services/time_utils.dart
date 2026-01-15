import 'package:flutter/material.dart';
class TimeUtils {
  /// Convert TimeOfDay to "HH:mm" string format (24-hour)
  static String timeOfDayToString(TimeOfDay time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
  /// Convert "HH:mm" string to TimeOfDay
  static TimeOfDay? stringToTimeOfDay(String? timeString) {
    if (timeString == null || timeString.isEmpty) return null;
    try {
      final parts = timeString.split(':');
      if (parts.length != 2) return null;
      final hour = int.parse(parts[0]);
      final minute = int.parse(parts[1]);
      if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
      return TimeOfDay(hour: hour, minute: minute);
    } catch (e) {
      return null;
    }
  }
  /// Format time string to display format (12-hour with simplified style)
  /// Examples: "17:00" -> "5pm", "09:30" -> "9:30am", "12:00" -> "12pm"
  static String formatTimeForDisplay(String? timeString) {
    if (timeString == null || timeString.isEmpty) return '';
    final timeOfDay = stringToTimeOfDay(timeString);
    if (timeOfDay == null) return '';
    return formatTimeOfDayForDisplay(timeOfDay);
  }
  /// Format TimeOfDay to display format (12-hour with simplified style)
  static String formatTimeOfDayForDisplay(TimeOfDay time) {
    final hour = time.hour;
    final minute = time.minute;
    // Handle 12-hour format
    int displayHour = hour;
    String period = 'am';
    if (hour == 0) {
      displayHour = 12; // 12:xx AM
    } else if (hour == 12) {
      period = 'pm'; // 12:xx PM
    } else if (hour > 12) {
      displayHour = hour - 12;
      period = 'pm';
    }
    // Format with simplified style
    if (minute == 0) {
      return '$displayHour$period'; // "5pm", "12am"
    } else {
      final minuteStr = minute.toString().padLeft(2, '0');
      return '$displayHour:$minuteStr$period'; // "5:30pm", "9:15am"
    }
  }
  /// Validate time string format (HH:mm)
  static bool isValidTimeString(String? timeString) {
    if (timeString == null || timeString.isEmpty) return false;
    final timeOfDay = stringToTimeOfDay(timeString);
    return timeOfDay != null;
  }
  /// Get current time as TimeOfDay
  static TimeOfDay getCurrentTime() {
    final now = DateTime.now();
    return TimeOfDay(hour: now.hour, minute: now.minute);
  }
  /// Create TimeOfDay from hour and minute
  static TimeOfDay createTime(int hour, int minute) {
    return TimeOfDay(hour: hour, minute: minute);
  }
}
