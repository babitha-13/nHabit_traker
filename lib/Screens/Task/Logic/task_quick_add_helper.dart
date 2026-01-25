import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_quick_add_logic_helper.dart';
import 'package:habit_tracker/Screens/Task/Logic/task_quick_add_ui_helper.dart';

class TaskQuickAddHelper {
  // Delegate to UI Helper
  static Widget buildQuickAddWithState(
    BuildContext context,
    StateSetter setModalState,
    StateSetter setState,
    TextEditingController quickAddController,
    String? selectedQuickTrackingType,
    DateTime? selectedQuickDueDate,
    TimeOfDay? selectedQuickDueTime,
    int? quickTimeEstimateMinutes,
    bool quickIsRecurring,
    FrequencyConfig? quickFrequencyConfig,
    List<ReminderConfig> quickReminders,
    int quickTargetNumber,
    Duration quickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    return TaskQuickAddUIHelper.buildQuickAddWithState(
      context,
      setModalState,
      setState,
      quickAddController,
      selectedQuickTrackingType,
      selectedQuickDueDate,
      selectedQuickDueTime,
      quickTimeEstimateMinutes,
      quickIsRecurring,
      quickFrequencyConfig,
      quickReminders,
      quickTargetNumber,
      quickTargetDuration,
      quickTargetNumberController,
      quickHoursController,
      quickMinutesController,
      quickUnitController,
      onTrackingTypeChanged,
      onDueDateChanged,
      onDueTimeChanged,
      onTimeEstimateChanged,
      onRecurringChanged,
      onRemindersChanged,
      onSubmit,
    );
  }

  static Widget buildQuickAdd(
    BuildContext context,
    void Function(VoidCallback) updateState,
    TextEditingController quickAddController,
    String? selectedQuickTrackingType,
    DateTime? selectedQuickDueDate,
    TimeOfDay? selectedQuickDueTime,
    int? quickTimeEstimateMinutes,
    bool quickIsRecurring,
    FrequencyConfig? quickFrequencyConfig,
    List<ReminderConfig> quickReminders,
    int quickTargetNumber,
    Duration quickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    return TaskQuickAddUIHelper.buildQuickAdd(
      context,
      updateState,
      quickAddController,
      selectedQuickTrackingType,
      selectedQuickDueDate,
      selectedQuickDueTime,
      quickTimeEstimateMinutes,
      quickIsRecurring,
      quickFrequencyConfig,
      quickReminders,
      quickTargetNumber,
      quickTargetDuration,
      quickTargetNumberController,
      quickHoursController,
      quickMinutesController,
      quickUnitController,
      onTrackingTypeChanged,
      onDueDateChanged,
      onDueTimeChanged,
      onTimeEstimateChanged,
      onRecurringChanged,
      onRemindersChanged,
      onSubmit,
    );
  }

  static void showQuickAddBottomSheet(
    BuildContext context,
    StateSetter setModalState,
    StateSetter setState,
    TextEditingController quickAddController,
    String? Function() getSelectedQuickTrackingType,
    DateTime? Function() getSelectedQuickDueDate,
    TimeOfDay? Function() getSelectedQuickDueTime,
    int? Function() getQuickTimeEstimateMinutes,
    bool Function() getQuickIsRecurring,
    FrequencyConfig? Function() getQuickFrequencyConfig,
    List<ReminderConfig> Function() getQuickReminders,
    int Function() getQuickTargetNumber,
    Duration Function() getQuickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    TaskQuickAddUIHelper.showQuickAddBottomSheet(
      context,
      setModalState,
      setState,
      quickAddController,
      getSelectedQuickTrackingType,
      getSelectedQuickDueDate,
      getSelectedQuickDueTime,
      getQuickTimeEstimateMinutes,
      getQuickIsRecurring,
      getQuickFrequencyConfig,
      getQuickReminders,
      getQuickTargetNumber,
      getQuickTargetDuration,
      quickTargetNumberController,
      quickHoursController,
      quickMinutesController,
      quickUnitController,
      onTrackingTypeChanged,
      onDueDateChanged,
      onDueTimeChanged,
      onTimeEstimateChanged,
      onRecurringChanged,
      onRemindersChanged,
      onSubmit,
    );
  }

  // Delegate to Routine Main page Helper
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
    return TaskQuickAddLogicHelper.submitQuickAdd(
      context,
      title,
      categoryId,
      categories,
      selectedQuickTrackingType,
      quickTargetNumber,
      quickTargetDuration,
      quickTimeEstimateMinutes,
      quickIsRecurring,
      quickFrequencyConfig,
      selectedQuickDueDate,
      selectedQuickDueTime,
      quickUnitController,
      quickReminders,
      onReset,
    );
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
    TaskQuickAddLogicHelper.resetQuickAdd(
      setState: setState,
      quickAddController: quickAddController,
      onTrackingTypeChanged: onTrackingTypeChanged,
      onDueDateChanged: onDueDateChanged,
      onDueTimeChanged: onDueTimeChanged,
      onTimeEstimateChanged: onTimeEstimateChanged,
      onRecurringChanged: onRecurringChanged,
      onRemindersChanged: onRemindersChanged,
      quickTargetNumberController: quickTargetNumberController,
      quickHoursController: quickHoursController,
      quickMinutesController: quickMinutesController,
      quickUnitController: quickUnitController,
      onTargetNumberChanged: onTargetNumberChanged,
      onTargetDurationChanged: onTargetDurationChanged,
    );
  }

  static bool isQuickTimeTarget(String? trackingType, Duration targetDuration) {
    return TaskQuickAddLogicHelper.isQuickTimeTarget(
        trackingType, targetDuration);
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
    return TaskQuickAddLogicHelper.selectQuickDueDate(
      context,
      updateState,
      selectedQuickDueDate,
      quickIsRecurring,
      quickFrequencyConfig,
      onDueDateChanged,
      onRecurringChanged,
    );
  }

  static Future<void> selectQuickDueTime(
    BuildContext context,
    void Function(VoidCallback) updateState,
    TimeOfDay? selectedQuickDueTime,
    Function(TimeOfDay?) onDueTimeChanged,
  ) async {
    return TaskQuickAddLogicHelper.selectQuickDueTime(
      context,
      updateState,
      selectedQuickDueTime,
      onDueTimeChanged,
    );
  }

  static Future<void> selectQuickTimeEstimate(
    BuildContext context,
    void Function(VoidCallback) updateState,
    int? quickTimeEstimateMinutes,
    Function(int?) onTimeEstimateChanged,
  ) async {
    return TaskQuickAddLogicHelper.selectQuickTimeEstimate(
      context,
      updateState,
      quickTimeEstimateMinutes,
      onTimeEstimateChanged,
    );
  }

  static Future<int?> showQuickTimeEstimateSheet({
    required BuildContext context,
    required FlutterFlowTheme theme,
    required int? initialMinutes,
  }) async {
    return TaskQuickAddUIHelper.showQuickTimeEstimateSheet(
      context: context,
      theme: theme,
      initialMinutes: initialMinutes,
    );
  }

  static Future<void> selectQuickReminders(
    BuildContext context,
    void Function(VoidCallback) updateState,
    List<ReminderConfig> quickReminders,
    TimeOfDay? selectedQuickDueTime,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
  ) async {
    return TaskQuickAddLogicHelper.selectQuickReminders(
      context,
      updateState,
      quickReminders,
      selectedQuickDueTime,
      onDueTimeChanged,
      onRemindersChanged,
    );
  }

  static String getQuickFrequencyDescription(FrequencyConfig? config) {
    return TaskQuickAddLogicHelper.getQuickFrequencyDescription(config);
  }
}
