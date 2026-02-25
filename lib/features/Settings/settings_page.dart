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
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => _showEffortModeInfoDialog(context, theme),
                icon: Icon(Icons.info_outline, color: theme.primary, size: 20),
                label: Text(
                  'How Effort Mode works (examples)',
                  style: theme.bodySmall.override(
                    color: theme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEffortModeInfoDialog(BuildContext context, FlutterFlowTheme theme) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            'Effort Mode Details',
            style: theme.titleMedium.override(
              fontWeight: FontWeight.w700,
            ),
          ),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Effort Mode ON:',
                    style: theme.bodyMedium.override(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Points increase with time spent for binary and time activities. '
                    'After the first 30 minutes, each extra 30-minute block earns additional points. However, additional points, exhibit diminishing returns.',
                    style: theme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Examples for a 1-star activity:\n'
                    '- 30m logged -> 1.0 pt\n'
                    '- 60m logged -> 1.7 pts\n'
                    '- 90m logged -> ~2.2 pts\n'
                    '- Quantity activities are still based on quantity vs target.',
                    style: theme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Effort Mode OFF:',
                    style: theme.bodyMedium.override(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Points are completion-based, not duration-based.',
                    style: theme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Examples for a 1-star activity:\n'
                    '- 30m and 2h give the same points if completion status is the same\n'
                    '- Quantity remains based on quantity progress.',
                    style: theme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
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
