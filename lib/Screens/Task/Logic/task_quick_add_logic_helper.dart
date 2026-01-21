import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_display_helper.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_quick_add_ui_helper.dart';

class TaskQuickAddLogicHelper {
  static Future<void> submitQuickAdd(
      BuildContext context,
      String title,
      String? categoryId,
      List<CategoryRecord> categories,
      String? selectedQuickTrackingType,
      int quickTargetNumber,
      Duration quickTargetDuration,
      int? quickTimeEstimateMinutes,
      bool quickIsRecurring,
      FrequencyConfig? quickFrequencyConfig,
      DateTime? selectedQuickDueDate,
      TimeOfDay? selectedQuickDueTime,
      TextEditingController quickUnitController,
      List<ReminderConfig> quickReminders,
      Function() onReset,
      ) async {
    if (title.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a task name')),
      );
      return;
    }
    if (categoryId == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a category')),
      );
      return;
    }
    if (selectedQuickTrackingType == null) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a tracking type')),
      );
      return;
    }
    try {
      dynamic targetValue;
      switch (selectedQuickTrackingType) {
        case 'binary':
          targetValue = null;
          break;
        case 'quantitative':
          targetValue = quickTargetNumber;
          break;
        case 'time':
          targetValue = quickTargetDuration.inMinutes;
          break;
        default:
          targetValue = null;
      }
      await createActivity(
        name: title,
        categoryId: categoryId,
        categoryName:
        categories.firstWhere((c) => c.reference.id == categoryId).name,
        trackingType: selectedQuickTrackingType!,
        target: targetValue,
        timeEstimateMinutes:
        !isQuickTimeTarget(selectedQuickTrackingType, quickTargetDuration)
            ? quickTimeEstimateMinutes
            : null,
        isRecurring: quickIsRecurring,
        userId: currentUserUid,
        dueDate: selectedQuickDueDate,
        dueTime: selectedQuickDueTime != null
            ? TimeUtils.timeOfDayToString(selectedQuickDueTime!)
            : null,
        priority: 1,
        unit: quickUnitController.text,
        specificDays: quickFrequencyConfig != null &&
            quickFrequencyConfig!.type == FrequencyType.specificDays
            ? quickFrequencyConfig!.selectedDays
            : null,
        categoryType: 'task',
        frequencyType: quickIsRecurring
            ? quickFrequencyConfig!.type.toString().split('.').last
            : null,
        everyXValue: quickIsRecurring &&
            quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? quickFrequencyConfig!.everyXValue
            : null,
        everyXPeriodType: quickIsRecurring &&
            quickFrequencyConfig!.type == FrequencyType.everyXPeriod
            ? quickFrequencyConfig!.everyXPeriodType.toString().split('.').last
            : null,
        timesPerPeriod: quickIsRecurring &&
            quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? quickFrequencyConfig!.timesPerPeriod
            : null,
        periodType: quickIsRecurring &&
            quickFrequencyConfig!.type == FrequencyType.timesPerPeriod
            ? quickFrequencyConfig!.periodType.toString().split('.').last
            : null,
        startDate: quickIsRecurring ? quickFrequencyConfig!.startDate : null,
        endDate: quickIsRecurring ? quickFrequencyConfig!.endDate : null,
        reminders: quickReminders.isNotEmpty
            ? ReminderConfigList.toMapList(quickReminders)
            : null,
      );
      onReset();
      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding task: $e')),
      );
    }
  }

  static void resetQuickAdd({
    required StateSetter setState,
    required TextEditingController quickAddController,
    required Function(String?) onTrackingTypeChanged,
    required Function(DateTime?) onDueDateChanged,
    required Function(TimeOfDay?) onDueTimeChanged,
    required Function(int?) onTimeEstimateChanged,
    required Function(bool, FrequencyConfig?) onRecurringChanged,
    required Function(List<ReminderConfig>) onRemindersChanged,
    required TextEditingController quickTargetNumberController,
    required TextEditingController quickHoursController,
    required TextEditingController quickMinutesController,
    required TextEditingController quickUnitController,
    required Function(int) onTargetNumberChanged,
    required Function(Duration) onTargetDurationChanged,
  }) {
    setState(() {
      quickAddController.clear();
      onTrackingTypeChanged('binary');
      onTargetNumberChanged(1);
      onTargetDurationChanged(const Duration(hours: 1));
      onDueDateChanged(null);
      onDueTimeChanged(null);
      onTimeEstimateChanged(null);
      onRecurringChanged(false, null);
      onRemindersChanged([]);
      quickUnitController.clear();
      quickTargetNumberController.text = '1';
      quickHoursController.text = '1';
      quickMinutesController.text = '0';
    });
  }

  static bool isQuickTimeTarget(String? trackingType, Duration targetDuration) {
    return trackingType == 'time' && targetDuration.inMinutes > 0;
  }

  static Future<void> selectQuickDueDate(
      BuildContext context,
      void Function(VoidCallback) updateState,
      DateTime? selectedQuickDueDate,
      bool quickIsRecurring,
      FrequencyConfig? quickFrequencyConfig,
      Function(DateTime?) onDueDateChanged,
      Function(bool, FrequencyConfig?) onRecurringChanged,
      ) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedQuickDueDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != selectedQuickDueDate) {
      updateState(() {
        onDueDateChanged(picked);
        if (quickIsRecurring && quickFrequencyConfig != null) {
          onRecurringChanged(
              true, quickFrequencyConfig!.copyWith(startDate: picked));
        }
      });
    }
  }

  static Future<void> selectQuickDueTime(
      BuildContext context,
      void Function(VoidCallback) updateState,
      TimeOfDay? selectedQuickDueTime,
      Function(TimeOfDay?) onDueTimeChanged,
      ) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: selectedQuickDueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null && picked != selectedQuickDueTime) {
      updateState(() {
        onDueTimeChanged(picked);
      });
    }
  }

  static Future<void> selectQuickTimeEstimate(
      BuildContext context,
      void Function(VoidCallback) updateState,
      int? quickTimeEstimateMinutes,
      Function(int?) onTimeEstimateChanged,
      ) async {
    final theme = FlutterFlowTheme.of(context);
    final result = await TaskQuickAddUIHelper.showQuickTimeEstimateSheet(
      context: context,
      theme: theme,
      initialMinutes: quickTimeEstimateMinutes,
    );
    if (!context.mounted) return;
    updateState(() {
      onTimeEstimateChanged(result);
    });
  }

  static Future<void> selectQuickReminders(
      BuildContext context,
      void Function(VoidCallback) updateState,
      List<ReminderConfig> quickReminders,
      TimeOfDay? selectedQuickDueTime,
      Function(TimeOfDay?) onDueTimeChanged,
      Function(List<ReminderConfig>) onRemindersChanged,
      ) async {
    final reminders = await ReminderConfigDialog.show(
      context: context,
      initialReminders: quickReminders,
      dueTime: selectedQuickDueTime,
      onRequestDueTime: () => selectQuickDueTime(
        context,
        updateState,
        selectedQuickDueTime,
        onDueTimeChanged,
      ),
    );
    if (reminders != null) {
      updateState(() {
        onRemindersChanged(reminders);
        if (reminders.isNotEmpty && selectedQuickDueTime == null) {
          // Auto-set due date handled by parent
        }
      });
    }
  }

  static String getQuickFrequencyDescription(FrequencyConfig? config) {
    if (config == null) return '';

    if (config.type == FrequencyType.specificDays) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final selectedDayNames = config.selectedDays
          .map((day) => days[day - 1])
          .join(', ');
      return 'Recurring on $selectedDayNames';
    }

    return FrequencyDisplayHelper.formatWithRecurringPrefix(config);
  }
}