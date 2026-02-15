import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/app_state.dart';
import 'package:habit_tracker/features/Settings/notification_settings_page.dart';
import 'package:habit_tracker/features/Settings/calendar_settings_page.dart';
import 'package:habit_tracker/features/Testing/simple_testing_page.dart';

/// Main settings page for managing app preferences
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _timeBonusEnabled = false;

  @override
  void initState() {
    super.initState();
    _timeBonusEnabled = FFAppState.instance.timeBonusEnabled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: theme.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.settings,
                  color: theme.primary,
                  size: 32,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'App Settings',
                    style: theme.headlineSmall.override(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Points System Settings Section
            _buildPointsSystemCard(theme),
            const SizedBox(height: 16),
            // Calendar Settings Navigation
            _buildCalendarSettingsCard(theme),
            const SizedBox(height: 16),
            // Notification Settings Navigation
            _buildNotificationSettingsCard(theme),
            const SizedBox(height: 16),
            // Developer Tools (Testing Page)
            _buildDeveloperToolsCard(theme),
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

  Widget _buildDeveloperToolsCard(FlutterFlowTheme theme) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const SimpleTestingPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.build_circle, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Developer Tools',
                      style: theme.titleMedium.override(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Cleanup duplicates and test time travel',
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCalendarSettingsCard(FlutterFlowTheme theme) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CalendarSettingsPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.calendar_today, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Calendar Settings',
                      style: theme.titleMedium.override(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage default time logging and duration',
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPointsSystemCard(FlutterFlowTheme theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.stars, color: theme.primary),
                const SizedBox(width: 12),
                Text(
                  'Points System',
                  style: theme.titleMedium.override(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Time bonus points switch
            SwitchListTile(
              title: Text(
                'Effort Mode (Time Bonus)',
                style: theme.bodyMedium.override(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                _timeBonusEnabled
                    ? 'Effort Mode ON: long duration activities get more points, with diminishing returns.'
                    : 'Effort Mode OFF: points depend on completion status, not duration.',
                style: theme.bodySmall,
              ),
              value: _timeBonusEnabled,
              onChanged: (value) {
                setState(() {
                  _timeBonusEnabled = value;
                });
                FFAppState.instance.timeBonusEnabled = value;
              },
            ),
            const SizedBox(height: 12),
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
                    child: Text(
                      _timeBonusEnabled
                          ? 'Effort Mode ON:\n'
                              'Long duration activities get more points than short duration activities (less than one hour). Even binary activities get more points if time is recorded and it takes more than half an hour.\n'
                              'Ex: A 30 mins task gets 1 point, and a 1 hr task gets 1.7 points. However additional points exhibit diminishing returns.\n\n'
                              'Diminishing returns:\n'
                              'If priority is one, the first half hour gets 1 full point. But the next half an hour gets 0.7 points and the next 0.5 points. Returns are not proportional to avoid over-focusing on the same activity the entire day.'
                          : 'Effort Mode OFF:\n'
                              'Points are defined by completion status and not dependent on duration.\n'
                              'Ex: A 30 min task and a 2 hr task both get 1 point if priority is 1.',
                      style: theme.bodySmall.override(
                        color: Colors.blue.shade700,
                      ),
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

  Widget _buildNotificationSettingsCard(FlutterFlowTheme theme) {
    return Card(
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const NotificationSettingsPage(),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.notifications_active, color: theme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notification Settings',
                      style: theme.titleMedium.override(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Manage wake up time, sleep time, and reminders',
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
