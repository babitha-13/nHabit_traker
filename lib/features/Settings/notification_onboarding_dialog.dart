import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/notification_preferences_service.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/features/Notifications%20and%20alarms/Engagement%20Notifications/daily_notification_scheduler.dart';
import 'package:habit_tracker/main.dart';

/// Onboarding dialog for collecting user notification preferences
/// Similar structure to GoalOnboardingDialog
class NotificationOnboardingDialog extends StatefulWidget {
  const NotificationOnboardingDialog({super.key});

  @override
  State<NotificationOnboardingDialog> createState() =>
      _NotificationOnboardingDialogState();
}

class _NotificationOnboardingDialogState
    extends State<NotificationOnboardingDialog> {
  bool _isSaving = false;
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 0);

  @override
  void initState() {
    super.initState();
    _loadExistingPreferences();
  }

  Future<void> _loadExistingPreferences() async {
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }
      final prefs =
          await NotificationPreferencesService.getUserNotificationPreferences(
              userId);
      setState(() {
        final wakeUpTimeString = prefs['wake_up_time'] as String?;
        if (wakeUpTimeString != null && wakeUpTimeString.isNotEmpty) {
          final time = TimeUtils.stringToTimeOfDay(wakeUpTimeString);
          if (time != null) {
            _wakeUpTime = time;
          }
        }
        final sleepTimeString = prefs['sleep_time'] as String?;
        if (sleepTimeString != null && sleepTimeString.isNotEmpty) {
          final time = TimeUtils.stringToTimeOfDay(sleepTimeString);
          if (time != null) {
            _sleepTime = time;
          }
        }
      });
    } catch (e) {
      // Use defaults if loading fails
    }
  }

  Future<void> _savePreferences() async {
    setState(() {
      _isSaving = true;
    });
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        return;
      }

      final preferences = {
        'wake_up_time': TimeUtils.timeOfDayToString(_wakeUpTime),
        'sleep_time': TimeUtils.timeOfDayToString(_sleepTime),
        'morning_reminder_enabled': true, // Always enabled
        'evening_reminder_enabled': true, // Always enabled
        'engagement_reminder_enabled': true,
      };

      await NotificationPreferencesService.updateNotificationPreferences(
          userId, preferences);
      await NotificationPreferencesService.markNotificationOnboardingCompleted(
          userId);

      // Reschedule notifications with new preferences
      await DailyNotificationScheduler.rescheduleAllDailyNotifications(userId);

      setState(() {
        _isSaving = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notification preferences saved! 🔔'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving preferences. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _selectWakeUpTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _wakeUpTime,
    );
    if (picked != null) {
      setState(() {
        _wakeUpTime = picked;
      });
    }
  }

  Future<void> _selectSleepTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _sleepTime,
    );
    if (picked != null) {
      setState(() {
        _sleepTime = picked;
      });
    }
  }

  Future<void> _skip() async {
    try {
      final userId = users.uid;
      if (userId != null && userId.isNotEmpty) {
        // Mark as completed with defaults
        await NotificationPreferencesService
            .markNotificationOnboardingCompleted(userId);
        // Schedule with defaults
        await DailyNotificationScheduler.rescheduleAllDailyNotifications(
            userId);
      }
      Navigator.of(context).pop();
    } catch (e) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.notifications_active,
                  color: theme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Set Up Notifications 🔔',
                    style: theme.headlineSmall.override(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Content
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Help us personalize your notifications by telling us about your sleep schedule.',
                      style: theme.bodyMedium,
                    ),
                    const SizedBox(height: 24),
                    // Wake up time section
                    _buildTimePickerSection(
                      label: 'What time do you wake up?',
                      time: _wakeUpTime,
                      onTimeSelected: _selectWakeUpTime,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Morning notification will be sent 1 hour after you wake up',
                      style: theme.bodySmall.override(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                    const SizedBox(height: 24),
                    // Sleep time section
                    _buildTimePickerSection(
                      label: 'What time do you go to sleep?',
                      time: _sleepTime,
                      onTimeSelected: _selectSleepTime,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Evening notification will be sent 1 hour before you sleep',
                      style: theme.bodySmall.override(
                        color: Colors.grey.shade600,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                TextButton(
                  onPressed: _isSaving ? null : _skip,
                  child: const Text('Skip'),
                ),
                ElevatedButton(
                  onPressed: _isSaving ? null : _savePreferences,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerSection({
    required String label,
    required TimeOfDay time,
    required VoidCallback onTimeSelected,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.titleMedium.override(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: onTimeSelected,
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.access_time, color: theme.primary),
                const SizedBox(width: 12),
                Text(
                  TimeUtils.formatTimeOfDayForDisplay(time),
                  style: theme.bodyLarge,
                ),
                const Spacer(),
                Icon(Icons.arrow_drop_down, color: Colors.grey),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
