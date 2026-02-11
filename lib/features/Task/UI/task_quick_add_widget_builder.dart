import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/activity%20editor/activity_type_dropdown_helper.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';
import 'package:habit_tracker/features/Task/Logic/task_quick_add_logic_helper.dart';
import 'package:intl/intl.dart';

class TaskQuickAddWidgetBuilder {
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
    final theme = FlutterFlowTheme.of(context);
    final quickAddWidget = Container(
      margin: EdgeInsets.zero,
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        boxShadow: theme.neumorphicShadowsRaised,
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.tertiary.withOpacity(0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.surfaceBorderColor,
                        width: 1,
                      ),
                    ),
                    child: TextField(
                      key: ValueKey(quickAddController.hashCode),
                      controller: quickAddController,
                      style: theme.bodyMedium,
                      maxLength: 200,
                      decoration: InputDecoration(
                        hintText: 'Quick add task…',
                        hintStyle: TextStyle(
                          color: theme.secondaryText,
                          fontSize: 14,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        counterText: '',
                      ),
                      onSubmitted: (_) => onSubmit(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    gradient: theme.primaryButtonGradient,
                    borderRadius: BorderRadius.circular(theme.buttonRadius),
                    boxShadow: [
                      BoxShadow(
                        color: theme.primary.withOpacity(0.3),
                        offset: const Offset(0, 2),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(theme.buttonRadius),
                      onTap: onSubmit,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Icon(
                          Icons.send,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ...[
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    theme.surfaceBorderColor,
                    Colors.transparent,
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      IconTaskTypeDropdown(
                        selectedValue: selectedQuickTrackingType ?? 'binary',
                        onChanged: (value) {
                          updateState(() {
                            onTrackingTypeChanged(value);
                            if (value == 'binary') {
                              // Reset target values handled by parent
                            }
                          });
                        },
                        tooltip: 'Select task type',
                      ),
                      // Date icon or chip
                      if (selectedQuickDueDate == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickDueDate(
                                context,
                                updateState,
                                selectedQuickDueDate,
                                quickIsRecurring,
                                quickFrequencyConfig,
                                onDueDateChanged,
                                onRecurringChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.calendar_today_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickDueDate(
                                context,
                                updateState,
                                selectedQuickDueDate,
                                quickIsRecurring,
                                quickFrequencyConfig,
                                onDueDateChanged,
                                onRecurringChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.calendar_today,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      quickIsRecurring
                                          ? 'From ${DateFormat('MMM dd').format(selectedQuickDueDate)}'
                                          : DateFormat('MMM dd')
                                              .format(selectedQuickDueDate),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        updateState(() {
                                          onDueDateChanged(null);
                                          if (!quickIsRecurring) {
                                            onRemindersChanged([]);
                                          }
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Time icon or chip
                      if (selectedQuickDueTime == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickDueTime(
                                context,
                                updateState,
                                selectedQuickDueTime,
                                onDueTimeChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.access_time_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickDueTime(
                                context,
                                updateState,
                                selectedQuickDueTime,
                                onDueTimeChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.access_time,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      TimeUtils.formatTimeOfDayForDisplay(
                                          selectedQuickDueTime!),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        updateState(() {
                                          onDueTimeChanged(null);
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Time estimate icon/chip (always show when not time-target)
                      if (!TaskQuickAddLogicHelper.isQuickTimeTarget(
                          selectedQuickTrackingType, quickTargetDuration))
                        if (quickTimeEstimateMinutes == null)
                          Container(
                            decoration: BoxDecoration(
                              color: theme.tertiary,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: theme.surfaceBorderColor,
                                width: 1,
                              ),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => TaskQuickAddLogicHelper
                                    .selectQuickTimeEstimate(
                                  context,
                                  updateState,
                                  quickTimeEstimateMinutes,
                                  onTimeEstimateChanged,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.all(8),
                                  child: Icon(
                                    Icons.timelapse_outlined,
                                    color: theme.secondary,
                                    size: 18,
                                  ),
                                ),
                              ),
                            ),
                          )
                        else
                          Container(
                            decoration: BoxDecoration(
                              color: theme.accent1.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: theme.accent1, width: 1),
                              boxShadow: [
                                BoxShadow(
                                  color: theme.accent1.withOpacity(0.2),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(10),
                                onTap: () => TaskQuickAddLogicHelper
                                    .selectQuickTimeEstimate(
                                  context,
                                  updateState,
                                  quickTimeEstimateMinutes,
                                  onTimeEstimateChanged,
                                ),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 8),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.timelapse,
                                          size: 14, color: theme.accent1),
                                      const SizedBox(width: 6),
                                      Text(
                                        '${quickTimeEstimateMinutes}m',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.accent1,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      InkWell(
                                        onTap: () {
                                          updateState(() {
                                            onTimeEstimateChanged(null);
                                          });
                                        },
                                        child: Icon(
                                          Icons.close,
                                          size: 14,
                                          color: theme.accent1,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      // Reminder icon or chip
                      if (quickReminders.isEmpty)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickReminders(
                                context,
                                updateState,
                                quickReminders,
                                selectedQuickDueTime,
                                onDueTimeChanged,
                                onRemindersChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.notifications_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () =>
                                  TaskQuickAddLogicHelper.selectQuickReminders(
                                context,
                                updateState,
                                quickReminders,
                                selectedQuickDueTime,
                                onDueTimeChanged,
                                onRemindersChanged,
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.notifications,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Text(
                                      quickReminders.length == 1
                                          ? quickReminders.first
                                              .getDescription()
                                          : '${quickReminders.length} reminders',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: theme.accent1,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        updateState(() {
                                          onRemindersChanged([]);
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Recurring icon or chip
                      if (!quickIsRecurring || quickFrequencyConfig == null)
                        Container(
                          decoration: BoxDecoration(
                            color: theme.tertiary,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                final config = await showFrequencyConfigDialog(
                                  context: context,
                                  initialConfig: quickFrequencyConfig ??
                                      FrequencyConfig(
                                        type: FrequencyType.everyXPeriod,
                                        startDate: selectedQuickDueDate ??
                                            DateTime.now(),
                                      ),
                                );
                                if (config != null) {
                                  updateState(() {
                                    onRecurringChanged(true, config);
                                    onDueDateChanged(config.startDate);
                                  });
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  Icons.repeat_outlined,
                                  color: theme.secondary,
                                  size: 18,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          decoration: BoxDecoration(
                            color: theme.accent1.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: theme.accent1, width: 1),
                            boxShadow: [
                              BoxShadow(
                                color: theme.accent1.withOpacity(0.2),
                                offset: const Offset(0, 1),
                                blurRadius: 2,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () async {
                                final config = await showFrequencyConfigDialog(
                                  context: context,
                                  initialConfig: quickFrequencyConfig,
                                );
                                if (config != null) {
                                  updateState(() {
                                    onRecurringChanged(true, config);
                                    onDueDateChanged(config.startDate);
                                  });
                                } else {
                                  final shouldDisable = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: const Text('Disable Recurring?'),
                                      content: const Text(
                                          'Do you want to disable recurring for this task?'),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: const Text('Cancel'),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          child: const Text('Disable'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (shouldDisable == true) {
                                    updateState(() {
                                      onRecurringChanged(false, null);
                                    });
                                  }
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.repeat,
                                        size: 14, color: theme.accent1),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        TaskQuickAddLogicHelper
                                            .getQuickFrequencyDescription(
                                                quickFrequencyConfig),
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: theme.accent1,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    InkWell(
                                      onTap: () {
                                        updateState(() {
                                          onRecurringChanged(false, null);
                                        });
                                      },
                                      child: Icon(
                                        Icons.close,
                                        size: 14,
                                        color: theme.accent1,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (selectedQuickTrackingType == 'quantitative') ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.accent2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.surfaceBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primary.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.track_changes,
                              size: 16, color: theme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Target:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: quickTargetNumberController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                // Handled by parent
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Unit:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: quickUnitController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                hintText: 'e.g., pages, reps',
                                hintStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              onChanged: (value) {},
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (selectedQuickTrackingType == 'time') ...[
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: theme.accent2,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: theme.surfaceBorderColor),
                        boxShadow: [
                          BoxShadow(
                            color: theme.primary.withOpacity(0.1),
                            offset: const Offset(0, 1),
                            blurRadius: 3,
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer, size: 16, color: theme.primary),
                          const SizedBox(width: 8),
                          Text(
                            'Target Duration:',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: quickHoursController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                labelText: 'Hours',
                                labelStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                // Handled by parent
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextFormField(
                              controller: quickMinutesController,
                              style: theme.bodyMedium,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.surfaceBorderColor),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide(
                                      color: theme.accent1, width: 2),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                labelText: 'Minutes',
                                labelStyle:
                                    TextStyle(color: theme.secondaryText),
                                isDense: true,
                                filled: true,
                                fillColor: theme.secondaryBackground,
                              ),
                              keyboardType: TextInputType.number,
                              onChanged: (value) {
                                // Handled by parent
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
    return quickAddWidget;
  }
}
