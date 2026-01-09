import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'package:habit_tracker/Screens/Routine/dialogs/routine_reminder_settings_dialog.dart';
import 'package:habit_tracker/Screens/Routine/dialogs/routine_reminder_dialog.dart';

/// Widget section for routine reminder configuration
class RoutineReminderSection extends StatelessWidget {
  final TimeOfDay? dueTime;
  final Function(TimeOfDay?) onDueTimeChanged;
  final List<ReminderConfig> reminders;
  final String? frequencyType;
  final int everyXValue;
  final String? everyXPeriodType;
  final List<int> specificDays;
  final bool remindersEnabled;
  final Function(RoutineReminderConfig) onConfigChanged;

  const RoutineReminderSection({
    super.key,
    this.dueTime,
    required this.onDueTimeChanged,
    this.reminders = const [],
    this.frequencyType,
    this.everyXValue = 1,
    this.everyXPeriodType,
    this.specificDays = const [],
    this.remindersEnabled = false,
    required this.onConfigChanged,
  });

  String _reminderSummary() {
    if (reminders.isEmpty) return '+ Add Reminder';
    if (reminders.length == 1) return reminders.first.getDescription();
    return '${reminders.length} reminders';
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    // Match Habits/Tasks editor field visuals (compact InputDecorator rows)
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDueTimeField(context, theme),
          const SizedBox(height: 10),
          _buildReminderField(context, theme),
        ],
      ),
    );
  }

  Widget _buildDueTimeField(BuildContext context, FlutterFlowTheme theme) {
    final label = dueTime != null ? dueTime!.format(context) : 'Set due time';
    return InkWell(
      onTap: () => _selectDueTime(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Time',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (dueTime != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => onDueTimeChanged(null),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReminderField(BuildContext context, FlutterFlowTheme theme) {
    final label = _reminderSummary();
    return InkWell(
      onTap: () => _showReminderDialog(context),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Reminders',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none,
                size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (reminders.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: _clearReminders,
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectDueTime(BuildContext context) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: dueTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null) {
      onDueTimeChanged(picked);
    }
  }

  void _clearReminders() {
    final config = RoutineReminderConfig(
      startTime: dueTime,
      reminders: const [],
      frequencyType: frequencyType,
      everyXValue: everyXValue,
      everyXPeriodType: everyXPeriodType,
      specificDays: specificDays,
      remindersEnabled: false,
    );
    onConfigChanged(config);
  }

  Future<void> _showReminderDialog(BuildContext context) async {
    final result = await RoutineReminderSettingsDialog.show(
      context: context,
      dueTime: dueTime,
      initialReminders: reminders,
      initialFrequencyType: frequencyType,
      initialEveryXValue: everyXValue,
      initialEveryXPeriodType: everyXPeriodType,
      initialSpecificDays: specificDays,
    );

    if (result != null) {
      // Convert to RoutineReminderConfig for backward compatibility
      // Note: dueTime is handled separately via onDueTimeChanged, so we pass current dueTime
      final config = RoutineReminderConfig(
        startTime: dueTime, // Keep dueTime as startTime in config for compatibility
        reminders: result.reminders,
        frequencyType: result.frequencyType,
        everyXValue: result.everyXValue,
        everyXPeriodType: result.everyXPeriodType,
        specificDays: result.specificDays,
        remindersEnabled: result.remindersEnabled,
      );
      onConfigChanged(config);
    }
  }
}

