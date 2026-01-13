import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/notification_preferences_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/Engagement%20Notifications/daily_notification_scheduler.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/notification_service.dart';
import 'package:habit_tracker/Screens/Notifications%20and%20alarms/Engagement%20Notifications/engagement_reminder_scheduler.dart';
import 'package:habit_tracker/main.dart';

/// Settings page for managing notification preferences
class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  TimeOfDay _wakeUpTime = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _sleepTime = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay? _calculatedMorningTime;
  TimeOfDay? _calculatedEveningTime;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        setState(() {
          _isLoading = false;
        });
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

        // Calculate notification times for display
        _calculatedMorningTime =
            NotificationPreferencesService.calculateMorningNotificationTime(
                _wakeUpTime);
        _calculatedEveningTime =
            NotificationPreferencesService.calculateEveningNotificationTime(
                _sleepTime);

        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading preferences: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _savePreferences() async {
    try {
      if (!mounted) return;
      setState(() {
        _isSaving = true;
      });

      final userId = users.uid;
      if (userId == null || userId.isEmpty) {
        if (mounted) {
          setState(() {
            _isSaving = false;
          });
        }
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

      // Reschedule notifications with new preferences
      await DailyNotificationScheduler.rescheduleAllDailyNotifications(userId);
      await EngagementReminderScheduler.cancelEngagementReminders(userId);
      await EngagementReminderScheduler.checkAndScheduleEngagementReminder(
          userId);

      // Recalculate notification times for display
      if (mounted) {
        setState(() {
          _calculatedMorningTime =
              NotificationPreferencesService.calculateMorningNotificationTime(
                  _wakeUpTime);
          _calculatedEveningTime =
              NotificationPreferencesService.calculateEveningNotificationTime(
                  _sleepTime);
          _isSaving = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving preferences: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _testNotification() async {
    try {
      await NotificationService.showImmediate(
        id: 'test_notification',
        title: 'Test Notification',
        body:
            'This is a test notification to verify your settings are working!',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Test notification sent!'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error sending test notification: $e'),
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
        _calculatedMorningTime =
            NotificationPreferencesService.calculateMorningNotificationTime(
                _wakeUpTime);
      });
      await _savePreferences();
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
        _calculatedEveningTime =
            NotificationPreferencesService.calculateEveningNotificationTime(
                _sleepTime);
      });
      await _savePreferences();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Settings'),
        backgroundColor: theme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.notifications_active,
                        color: theme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Manage Your Notifications',
                          style: theme.headlineSmall.override(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Customize when and how you receive reminders',
                    style: theme.bodyMedium,
                  ),
                  const SizedBox(height: 32),
                  // Wake up time section
                  _buildWakeSleepTimeCard(
                    theme: theme,
                    label: 'Wake Up Time',
                    description: 'What time do you wake up?',
                    time: _wakeUpTime,
                    onTimeSelected: _selectWakeUpTime,
                    calculatedTime: _calculatedMorningTime,
                    calculatedLabel: 'Morning notification',
                    calculatedDescription: 'Sent 1 hour after you wake up',
                  ),
                  const SizedBox(height: 16),
                  // Sleep time section
                  _buildWakeSleepTimeCard(
                    theme: theme,
                    label: 'Sleep Time',
                    description: 'What time do you go to sleep?',
                    time: _sleepTime,
                    onTimeSelected: _selectSleepTime,
                    calculatedTime: _calculatedEveningTime,
                    calculatedLabel: 'Evening notification',
                    calculatedDescription: 'Sent 1 hour before you sleep',
                  ),
                  const SizedBox(height: 32),
                  // Test notification button
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _testNotification,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Test Notification'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Changes are saved automatically.',
                    style: theme.bodySmall.override(
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildWakeSleepTimeCard({
    required FlutterFlowTheme theme,
    required String label,
    required String description,
    required TimeOfDay time,
    required VoidCallback onTimeSelected,
    required TimeOfDay? calculatedTime,
    required String calculatedLabel,
    required String calculatedDescription,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: theme.titleMedium.override(
                fontFamily: 'Outfit',
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: theme.bodySmall,
            ),
            const SizedBox(height: 16),
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
                  color: Colors.grey.shade50,
                ),
                child: Row(
                  children: [
                    Icon(Icons.access_time, color: theme.primary),
                    const SizedBox(width: 12),
                    Text(
                      TimeUtils.formatTimeOfDayForDisplay(time),
                      style: theme.bodyLarge.override(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.arrow_drop_down, color: Colors.grey),
                  ],
                ),
              ),
            ),
            if (calculatedTime != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            calculatedLabel,
                            style: theme.bodySmall.override(
                              fontWeight: FontWeight.w600,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${TimeUtils.formatTimeOfDayForDisplay(calculatedTime)} - $calculatedDescription',
                            style: theme.bodySmall.override(
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
