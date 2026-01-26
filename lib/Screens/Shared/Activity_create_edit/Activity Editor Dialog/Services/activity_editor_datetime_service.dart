import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';

/// Service for date and time picker operations
class ActivityEditorDateTimeService {
  /// Pick due date
  static Future<void> pickDueDate(ActivityEditorDialogState state) async {
    final picked = await showDatePicker(
      context: state.context,
      initialDate: state.dueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) state.setState(() => state.dueDate = picked);
  }

  /// Pick due time
  static Future<void> pickDueTime(ActivityEditorDialogState state) async {
    final TimeOfDay? picked = await showTimePicker(
      context: state.context,
      initialTime: state.selectedDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != state.selectedDueTime) {
      state.setState(() => state.selectedDueTime = picked);
    }
  }
}
