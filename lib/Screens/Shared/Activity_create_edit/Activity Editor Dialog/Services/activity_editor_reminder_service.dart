import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';
import 'activity_editor_datetime_service.dart';
import 'activity_editor_helper_service.dart';

/// Service for reminder operations
class ActivityEditorReminderService {
  /// Open reminder dialog
  static Future<void> openReminderDialog(ActivityEditorDialogState state) async {
    final reminders = await ReminderConfigDialog.show(
      context: state.context,
      initialReminders: state.reminders,
      dueTime: state.selectedDueTime,
      onRequestDueTime: () => ActivityEditorDateTimeService.pickDueTime(state),
    );
    if (reminders != null) {
      state.setState(() {
        state.reminders = reminders;
        if (state.reminders.isNotEmpty && !ActivityEditorHelperService.isRecurring(state) && state.dueDate == null) {
          state.dueDate = DateTime.now();
        }
      });
    }
  }

  /// Get reminder summary text
  static String reminderSummary(ActivityEditorDialogState state) {
    if (state.reminders.isEmpty) return '+ Add Reminder';
    if (state.reminders.length == 1) return state.reminders.first.getDescription();
    return '${state.reminders.length} reminders';
  }

  /// Validate reminder times for one-time tasks
  /// Returns error message if validation fails, null otherwise
  static String? validateReminderTimes(ActivityEditorDialogState state) {
    if (state.quickIsTaskRecurring) {
      // Recurring items are allowed - they'll fire for next instance
      return null;
    }

    if (state.reminders.isEmpty) {
      return null;
    }

    // Need due date and due time to validate
    if (state.dueDate == null || state.selectedDueTime == null) {
      return null; // Can't validate without due date/time
    }

    final now = DateTime.now();

    for (final reminder in state.reminders) {
      if (!reminder.enabled) continue;

      DateTime? reminderDateTime;

      if (reminder.fixedTimeMinutes != null) {
        // Fixed time reminder
        final hour = reminder.fixedTimeMinutes! ~/ 60;
        final minute = reminder.fixedTimeMinutes! % 60;
        reminderDateTime = DateTime(
          state.dueDate!.year,
          state.dueDate!.month,
          state.dueDate!.day,
          hour,
          minute,
        );
      } else {
        // Offset-based reminder
        final dueDateTime = DateTime(
          state.dueDate!.year,
          state.dueDate!.month,
          state.dueDate!.day,
          state.selectedDueTime!.hour,
          state.selectedDueTime!.minute,
        );
        reminderDateTime =
            dueDateTime.add(Duration(minutes: reminder.offsetMinutes));
      }

      if (reminderDateTime.isBefore(now)) {
        return 'Reminder time cannot be in the past for one-time tasks. Please adjust the reminder time or make this a recurring task.';
      }
    }

    return null;
  }
}
