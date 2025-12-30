import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/reminder_config.dart';
import 'package:habit_tracker/Screens/Shared/reminder_config_editor.dart';
import 'package:habit_tracker/Screens/Routine/widgets/routine_repeat_editor.dart';

/// Combined dialog for configuring routine reminders and repeat settings
class RoutineReminderSettingsDialog extends StatefulWidget {
  final TimeOfDay? dueTime;
  final List<ReminderConfig> initialReminders;
  final String? initialFrequencyType;
  final int initialEveryXValue;
  final String? initialEveryXPeriodType;
  final List<int> initialSpecificDays;

  const RoutineReminderSettingsDialog({
    super.key,
    this.dueTime,
    this.initialReminders = const [],
    this.initialFrequencyType,
    this.initialEveryXValue = 1,
    this.initialEveryXPeriodType,
    this.initialSpecificDays = const [],
  });

  static Future<RoutineReminderSettingsResult?> show({
    required BuildContext context,
    TimeOfDay? dueTime,
    List<ReminderConfig>? initialReminders,
    String? initialFrequencyType,
    int? initialEveryXValue,
    String? initialEveryXPeriodType,
    List<int>? initialSpecificDays,
  }) async {
    final result = await showDialog<RoutineReminderSettingsResult>(
      context: context,
      builder: (context) => RoutineReminderSettingsDialog(
        dueTime: dueTime,
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
  State<RoutineReminderSettingsDialog> createState() =>
      _RoutineReminderSettingsDialogState();
}

class _RoutineReminderSettingsDialogState
    extends State<RoutineReminderSettingsDialog> {
  late List<ReminderConfig> _reminders;
  String? _frequencyType;
  int _everyXValue = 1;
  String? _everyXPeriodType;
  List<int> _specificDays = [];

  @override
  void initState() {
    super.initState();
    _reminders = List.from(widget.initialReminders);
    _frequencyType = widget.initialFrequencyType;
    _everyXValue = widget.initialEveryXValue;
    _everyXPeriodType = widget.initialEveryXPeriodType ?? 'day';
    _specificDays = List.from(widget.initialSpecificDays);
  }

  void _save() {
    // If there are no reminders, repeat settings are not applicable.
    if (_reminders.isEmpty) {
      Navigator.of(context).pop(RoutineReminderSettingsResult(
        reminders: const [],
        frequencyType: null,
        everyXValue: 1,
        everyXPeriodType: null,
        specificDays: const [],
        remindersEnabled: false,
      ));
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

    Navigator.of(context).pop(RoutineReminderSettingsResult(
      reminders: _reminders,
      frequencyType: _frequencyType,
      everyXValue: _everyXValue,
      everyXPeriodType: _everyXPeriodType,
      specificDays: _frequencyType == 'specific_days' ? _specificDays : [],
      remindersEnabled: _reminders.isNotEmpty,
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
                      'Reminder Settings',
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
                    Text('Reminders', style: theme.titleMedium),
                    const SizedBox(height: 8),
                    ReminderConfigEditor(
                      reminders: _reminders,
                      dueTime: widget.dueTime,
                      onRemindersChanged: (reminders) {
                        setState(() {
                          _reminders = reminders;
                          // If reminders are removed, repeat options no longer apply.
                          if (_reminders.isEmpty) {
                            _frequencyType = null;
                            _everyXValue = 1;
                            _everyXPeriodType = 'day';
                            _specificDays = [];
                          }
                        });
                      },
                    ),
                    if (_reminders.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Divider(),
                      const SizedBox(height: 20),
                      Text('Repeat', style: theme.titleMedium),
                      const SizedBox(height: 8),
                      RoutineRepeatEditor(
                        frequencyType: _frequencyType,
                        everyXValue: _everyXValue,
                        everyXPeriodType: _everyXPeriodType,
                        specificDays: _specificDays,
                        onConfigChanged: (frequencyType, everyXValue,
                            everyXPeriodType, specificDays) {
                          setState(() {
                            _frequencyType = frequencyType;
                            _everyXValue = everyXValue;
                            _everyXPeriodType = everyXPeriodType;
                            _specificDays = specificDays;
                          });
                        },
                      ),
                    ],
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
}

/// Configuration result from routine reminder settings dialog
class RoutineReminderSettingsResult {
  final List<ReminderConfig> reminders;
  final String? frequencyType; // 'every_x' or 'specific_days'
  final int everyXValue;
  final String? everyXPeriodType; // 'day', 'week', 'month'
  final List<int> specificDays; // 1-7
  final bool remindersEnabled;

  RoutineReminderSettingsResult({
    this.reminders = const [],
    this.frequencyType,
    this.everyXValue = 1,
    this.everyXPeriodType,
    this.specificDays = const [],
    this.remindersEnabled = false,
  });
}

