import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/Services/manual_time_log_preview_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual_Time_Log/Services/manual_time_log_search_service.dart';

/// Service for date and time picker operations
class ManualTimeLogDateTimeService {
  /// Pick start time
  static Future<void> pickStartTime(ManualTimeLogModalState state) async {
    // Hide suggestions dropdown before showing time picker
    if (state.mounted) {
      state.setState(() => state.showSuggestions = false);
    }
    state.activityFocusNode.unfocus();
    ManualTimeLogSearchService.removeOverlay(state);

    final time = await showTimePicker(
      context: state.context,
      initialTime: TimeOfDay.fromDateTime(state.startTime),
    );
    if (time != null) {
      state.setState(() {
        // Properly combine selected date with chosen time
        // Use the date from widget.selectedDate and time from picker
        final selectedDateOnly = DateTime(
          state.widget.selectedDate.year,
          state.widget.selectedDate.month,
          state.widget.selectedDate.day,
        );
        state.startTime = selectedDateOnly.add(Duration(
          hours: time.hour,
          minutes: time.minute,
        ));
        // Auto-adjust end time if it's before start time
        if (state.endTime.isBefore(state.startTime)) {
          state.endTime = state.startTime
              .add(Duration(minutes: state.defaultDurationMinutes));
        }
        ManualTimeLogPreviewService.updatePreview(state);
      });
    }
  }

  /// Pick end time
  static Future<void> pickEndTime(ManualTimeLogModalState state) async {
    // Hide suggestions dropdown before showing time picker
    if (state.mounted) {
      state.setState(() => state.showSuggestions = false);
    }
    state.activityFocusNode.unfocus();
    ManualTimeLogSearchService.removeOverlay(state);

    final time = await showTimePicker(
      context: state.context,
      initialTime: TimeOfDay.fromDateTime(state.endTime),
    );
    if (time != null) {
      state.setState(() {
        // Properly combine selected date with chosen time
        // Use the date from widget.selectedDate and time from picker
        final selectedDateOnly = DateTime(
          state.widget.selectedDate.year,
          state.widget.selectedDate.month,
          state.widget.selectedDate.day,
        );
        state.endTime = selectedDateOnly.add(Duration(
          hours: time.hour,
          minutes: time.minute,
        ));
        ManualTimeLogPreviewService.updatePreview(state);
      });
    }
  }
}
