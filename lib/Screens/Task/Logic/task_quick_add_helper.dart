import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/activity_type_dropdown_helper.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_display_helper.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Reminder_config/reminder_config_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/activity_instance_service.dart';
import 'package:intl/intl.dart';

class TaskQuickAddHelper {
  // Build Quick Add UI with state management
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
    void updateState(VoidCallback fn) {
      setState(fn);
      setModalState(() {}); // Trigger modal rebuild
    }

    return buildQuickAdd(
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
                              onTap: () => selectQuickDueDate(
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
                              onTap: () => selectQuickDueDate(
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
                              onTap: () => selectQuickDueTime(
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
                              onTap: () => selectQuickDueTime(
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
                      if (!isQuickTimeTarget(selectedQuickTrackingType, quickTargetDuration))
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
                                onTap: () => selectQuickTimeEstimate(
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
                                onTap: () => selectQuickTimeEstimate(
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
                              onTap: () => selectQuickReminders(
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
                              onTap: () => selectQuickReminders(
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
                                        getQuickFrequencyDescription(
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

  static void showQuickAddBottomSheet(
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
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          final totalBottomPadding =
              keyboardHeight > 0 ? keyboardHeight : bottomPadding;

          return Padding(
            padding: EdgeInsets.only(
              bottom: totalBottomPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.primaryBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: buildQuickAddWithState(
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
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

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
    print('--- task_page.dart: calling createActivity (quick add task) ...');
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
      print('--- task_page.dart: createActivity completed successfully');
      onReset();
      if (context.mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      print('--- task_page.dart: createActivity failed: $e');
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
    final result = await showQuickTimeEstimateSheet(
      context: context,
      theme: theme,
      initialMinutes: quickTimeEstimateMinutes,
    );
    if (!context.mounted) return;
    updateState(() {
      onTimeEstimateChanged(result);
    });
  }

  static Future<int?> showQuickTimeEstimateSheet({
    required BuildContext context,
    required FlutterFlowTheme theme,
    required int? initialMinutes,
  }) async {
    final controller =
        TextEditingController(text: initialMinutes?.toString() ?? '');
    const presets = <int>[5, 10, 15, 20, 30, 45, 60];

    final result = await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Container(
            decoration: BoxDecoration(
              color: theme.primaryBackground,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              border: Border.all(color: theme.surfaceBorderColor, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Time estimate',
                    style: theme.titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: controller,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: 'Minutes (1–600)',
                            hintStyle: TextStyle(
                              color: theme.secondaryText,
                              fontSize: 14,
                            ),
                            filled: true,
                            fillColor: theme.tertiary.withOpacity(0.3),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: theme.surfaceBorderColor),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide:
                                  BorderSide(color: theme.surfaceBorderColor),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide(color: theme.primary),
                            ),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Clear'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: presets
                        .map(
                          (m) => OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, m),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: theme.surfaceBorderColor),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              foregroundColor: theme.primaryText,
                            ),
                            child: Text('${m}m'),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final parsed = int.tryParse(controller.text.trim());
                        if (parsed == null) {
                          Navigator.pop(ctx, null);
                          return;
                        }
                        Navigator.pop(ctx, parsed.clamp(1, 600));
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    controller.dispose();
    return result;
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
