import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Helper/utils/reminder_config_dialog.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';

/// Dialog for configuring routine reminders (start time + reminders + repeat)
class RoutineReminderDialog extends StatefulWidget {
  final TimeOfDay? initialStartTime;
  final List<ReminderConfig> initialReminders;
  final String? initialFrequencyType; // 'every_x' or 'specific_days'
  final int initialEveryXValue;
  final String? initialEveryXPeriodType; // 'day', 'week', 'month'
  final List<int> initialSpecificDays; // 1-7

  const RoutineReminderDialog({
    super.key,
    this.initialStartTime,
    this.initialReminders = const [],
    this.initialFrequencyType,
    this.initialEveryXValue = 1,
    this.initialEveryXPeriodType,
    this.initialSpecificDays = const [],
  });

  static Future<RoutineReminderConfig?> show({
    required BuildContext context,
    TimeOfDay? initialStartTime,
    List<ReminderConfig>? initialReminders,
    String? initialFrequencyType,
    int? initialEveryXValue,
    String? initialEveryXPeriodType,
    List<int>? initialSpecificDays,
  }) async {
    final result = await showDialog<RoutineReminderConfig>(
      context: context,
      builder: (context) => RoutineReminderDialog(
        initialStartTime: initialStartTime,
        initialReminders: initialReminders ?? [],
        initialFrequencyType: initialFrequencyType,
        initialEveryXValue: initialEveryXValue ?? 1,
        initialEveryXPeriodType: initialEveryXPeriodType,
        initialSpecificDays: initialSpecificDays ?? [],
      ),
    );
    return result;
  }

  @override
  State<RoutineReminderDialog> createState() => _RoutineReminderDialogState();
}

class _RoutineReminderDialogState extends State<RoutineReminderDialog> {
  TimeOfDay? _startTime;
  List<ReminderConfig> _reminders = [];
  String? _frequencyType; // 'every_x' or 'specific_days'
  int _everyXValue = 1;
  String? _everyXPeriodType; // 'day', 'week', 'month'
  List<int> _specificDays = [];

  @override
  void initState() {
    super.initState();
    _startTime = widget.initialStartTime;
    _reminders = List.from(widget.initialReminders);
    _frequencyType = widget.initialFrequencyType;
    _everyXValue = widget.initialEveryXValue;
    _everyXPeriodType = widget.initialEveryXPeriodType ?? 'day';
    _specificDays = List.from(widget.initialSpecificDays);
  }

  Future<void> _selectStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime ?? TimeUtils.getCurrentTime(),
    );
    if (picked != null) {
      setState(() {
        _startTime = picked;
      });
    }
  }

  Future<void> _editReminders() async {
    if (_startTime == null) {
      // Request start time first
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please set start time first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final reminders = await ReminderConfigDialog.show(
      context: context,
      initialReminders: _reminders,
      dueTime: _startTime,
    );

    if (reminders != null) {
      setState(() {
        _reminders = reminders;
      });
    }
  }

  void _setFrequencyType(String? type) {
    setState(() {
      _frequencyType = type;
      if (type == 'every_x' && _everyXPeriodType == null) {
        _everyXPeriodType = 'day';
      }
      if (type == 'specific_days' && _specificDays.isEmpty) {
        // Default to all days if none selected
        _specificDays = [1, 2, 3, 4, 5, 6, 7];
      }
    });
  }

  void _toggleDay(int day) {
    setState(() {
      if (_specificDays.contains(day)) {
        _specificDays.remove(day);
      } else {
        _specificDays.add(day);
        _specificDays.sort();
      }
    });
  }

  void _save() {
    if (_startTime == null && _reminders.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Start time is required when reminders are set'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_frequencyType == 'specific_days' && _specificDays.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one day'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (_frequencyType == 'every_x' && _everyXValue < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Period value must be at least 1'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    Navigator.of(context).pop(RoutineReminderConfig(
      startTime: _startTime,
      reminders: _reminders,
      frequencyType: _frequencyType,
      everyXValue: _everyXValue,
      everyXPeriodType: _everyXPeriodType,
      specificDays: _frequencyType == 'specific_days' ? _specificDays : [],
      remindersEnabled: _reminders.isNotEmpty && _startTime != null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: theme.surfaceBorderColor),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Routine Reminders',
                      style: theme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Start time picker
                    _buildStartTimePicker(theme),
                    const SizedBox(height: 24),
                    // Reminders section
                    _buildRemindersSection(theme),
                    const SizedBox(height: 24),
                    // Repeat section
                    _buildRepeatSection(theme),
                  ],
                ),
              ),
            ),
            // Footer
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: theme.surfaceBorderColor),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('Cancel', style: theme.bodyMedium),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStartTimePicker(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Start Time',
          style: theme.titleMedium,
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _selectStartTime,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.secondaryBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.surfaceBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: theme.primary),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _startTime != null
                        ? TimeUtils.formatTimeOfDayForDisplay(_startTime!)
                        : 'Tap to set start time',
                    style: theme.bodyLarge,
                  ),
                ),
                if (_startTime != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () {
                      setState(() {
                        _startTime = null;
                        if (_reminders.isNotEmpty) {
                          _reminders = [];
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRemindersSection(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Reminders',
                style: theme.titleMedium,
              ),
            ),
            TextButton.icon(
              onPressed: _reminders.isNotEmpty || _startTime != null
                  ? _editReminders
                  : null,
              icon: const Icon(Icons.edit, size: 18),
              label: Text(_reminders.isEmpty ? 'Add Reminders' : 'Edit'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_reminders.isEmpty)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.tertiary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.surfaceBorderColor),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 18, color: theme.secondaryText),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _startTime == null
                        ? 'Set start time first to add reminders'
                        : 'No reminders set',
                    style: theme.bodyMedium.override(
                      color: theme.secondaryText,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          ..._reminders.map((reminder) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.secondaryBackground,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: theme.surfaceBorderColor),
                ),
                child: Row(
                  children: [
                    Icon(
                      reminder.type == 'alarm'
                          ? Icons.alarm
                          : Icons.notifications,
                      size: 18,
                      color: theme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        reminder.getDescription(),
                        style: theme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )),
      ],
    );
  }

  Widget _buildRepeatSection(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Repeat',
          style: theme.titleMedium,
        ),
        const SizedBox(height: 12),
        // Radio options
        _buildRadioOption(
          theme,
          null,
          'No repeat',
          'Reminders will not recur',
        ),
        _buildRadioOption(
          theme,
          'every_x',
          'Every X days/weeks/months',
          null,
        ),
        if (_frequencyType == 'every_x') ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _buildEveryXInput(theme),
          ),
        ],
        _buildRadioOption(
          theme,
          'specific_days',
          'Specific days of week',
          null,
        ),
        if (_frequencyType == 'specific_days') ...[
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: _buildDaySelection(theme),
          ),
        ],
      ],
    );
  }

  Widget _buildRadioOption(
    FlutterFlowTheme theme,
    String? value,
    String title,
    String? subtitle,
  ) {
    return InkWell(
      onTap: () => _setFrequencyType(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Radio<String?>(
              value: value,
              groupValue: _frequencyType,
              onChanged: (v) => _setFrequencyType(v),
              activeColor: theme.primary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.bodyLarge),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: theme.bodySmall.override(
                        color: theme.secondaryText,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEveryXInput(FlutterFlowTheme theme) {
    return Row(
      children: [
        Text('Every', style: theme.bodyMedium),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: TextFormField(
            initialValue: _everyXValue.toString(),
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            style: theme.bodyMedium,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: theme.surfaceBorderColor),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
            ),
            onChanged: (value) {
              final num = int.tryParse(value) ?? 1;
              setState(() {
                _everyXValue = num > 0 ? num : 1;
              });
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildPeriodTypeDropdown(theme),
        ),
      ],
    );
  }

  Widget _buildPeriodTypeDropdown(FlutterFlowTheme theme) {
    const options = ['day', 'week', 'month'];
    return DropdownButtonFormField<String>(
      value: _everyXPeriodType ?? 'day',
      decoration: InputDecoration(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.surfaceBorderColor),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      items: options.map((opt) {
        return DropdownMenuItem(
          value: opt,
          child: Text(opt),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() {
            _everyXPeriodType = value;
          });
        }
      },
    );
  }

  Widget _buildDaySelection(FlutterFlowTheme theme) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(7, (index) {
        final dayIndex = index + 1; // 1-7
        final isSelected = _specificDays.contains(dayIndex);
        return FilterChip(
          label: Text(days[index]),
          selected: isSelected,
          onSelected: (_) => _toggleDay(dayIndex),
          selectedColor: theme.primary,
          backgroundColor: theme.secondaryBackground,
          side: BorderSide(
            color: isSelected ? theme.primary : theme.surfaceBorderColor,
            width: 1,
          ),
        );
      }),
    );
  }
}

/// Configuration result from routine reminder dialog
class RoutineReminderConfig {
  final TimeOfDay? startTime;
  final List<ReminderConfig> reminders;
  final String? frequencyType; // 'every_x' or 'specific_days'
  final int everyXValue;
  final String? everyXPeriodType; // 'day', 'week', 'month'
  final List<int> specificDays; // 1-7
  final bool remindersEnabled;

  RoutineReminderConfig({
    this.startTime,
    this.reminders = const [],
    this.frequencyType,
    this.everyXValue = 1,
    this.everyXPeriodType,
    this.specificDays = const [],
    this.remindersEnabled = false,
  });
}

