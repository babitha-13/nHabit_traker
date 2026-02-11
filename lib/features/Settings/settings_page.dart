import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/app_state.dart';
import 'package:habit_tracker/features/Settings/notification_settings_page.dart';
import 'package:habit_tracker/features/Settings/calendar_settings_page.dart';

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
              Icon(Icons.chevron_right, color: Colors.grey),
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
                'ON: points reward time spent (30-min blocks). OFF: points follow your targets.',
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
                          ? 'Effort Mode is ON. Binary and time-based activities award more points for more time spent (in 30-min blocks). Quantity activities still score by quantity.'
                          : 'Effort Mode is OFF. Binary is completion-based, time-based scores vs your time target, and quantity scores vs your quantity target. Logged time is still recorded.',
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
              Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}
