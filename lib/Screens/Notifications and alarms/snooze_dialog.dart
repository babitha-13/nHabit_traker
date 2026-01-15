import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/reminder_scheduler.dart';

/// Dialog for selecting snooze duration
class SnoozeDialog {
  /// Show the snooze dialog
  static Future<void> show({
    required BuildContext context,
    required String reminderId,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => _SnoozeDialogContent(reminderId: reminderId),
    );
  }
}

class _SnoozeDialogContent extends StatelessWidget {
  final String reminderId;

  const _SnoozeDialogContent({required this.reminderId});

  final List<Map<String, dynamic>> _snoozeOptions = const [
    {'label': '15 minutes', 'minutes': 15},
    {'label': '30 minutes', 'minutes': 30},
    {'label': '1 hour', 'minutes': 60},
    {'label': '2 hours', 'minutes': 120},
    {'label': '1 day', 'minutes': 1440},
  ];

  void _handleSnooze(BuildContext context, int minutes) async {
    try {
      await ReminderScheduler.snoozeReminder(
        reminderId: reminderId,
        durationMinutes: minutes,
      );
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Reminder snoozed for ${_snoozeOptions.firstWhere((opt) => opt['minutes'] == minutes)['label']}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error snoozing reminder: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Snooze Reminder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: _snoozeOptions.map((option) {
          return ListTile(
            title: Text(option['label'] as String),
            onTap: () => _handleSnooze(context, option['minutes'] as int),
          );
        }).toList(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
