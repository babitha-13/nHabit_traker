import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Settings/notification_settings_page.dart';
import 'package:habit_tracker/main.dart';

/// Main settings page for managing app preferences
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  int _defaultDurationMinutes = 10;
  bool _enableDefaultEstimates = true;
  bool _enableActivityEstimates = false;

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

      final prefs = await TimeLoggingPreferencesService.getPreferences(userId);

      setState(() {
        _defaultDurationMinutes = prefs.defaultDurationMinutes;
        _enableDefaultEstimates = prefs.enableDefaultEstimates;
        _enableActivityEstimates = prefs.enableActivityEstimates;
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

  Future<void> _persistPreferences() async {
    final userId = users.uid;
    if (userId == null || userId.isEmpty) return;

    if (mounted) setState(() => _isSaving = true);

    try {
      await TimeLoggingPreferencesService.updatePreferences(
        userId,
        defaultDurationMinutes: _defaultDurationMinutes,
        enableDefaultEstimates: _enableDefaultEstimates,
        enableActivityEstimates: _enableActivityEstimates,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving preferences: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
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
                  // Time Logging Settings Section
                  _buildTimeLoggingCard(theme),
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

  Widget _buildTimeLoggingCard(FlutterFlowTheme theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.timer, color: theme.primary),
                const SizedBox(width: 12),
                Text(
                  'Time Logging',
                  style: theme.titleMedium.override(
                    fontFamily: 'Outfit',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Enable default time estimates switch
            SwitchListTile(
              title: Text(
                'Enable default time estimates',
                style: theme.bodyMedium.override(
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: Text(
                'Automatically log time for binary and quantity activities without time targets',
                style: theme.bodySmall,
              ),
              value: _enableDefaultEstimates,
              onChanged: (value) {
                setState(() {
                  _enableDefaultEstimates = value;
                  if (!value) {
                    // If disabling default estimates, also disable activity estimates
                    _enableActivityEstimates = false;
                  }
                });
                _persistPreferences();
              },
            ),
            // Default duration slider (only shown/enabled when default estimates is ON)
            if (_enableDefaultEstimates) ...[
              const SizedBox(height: 16),
              Text(
                'Default Duration',
                style: theme.bodyMedium.override(
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _defaultDurationMinutes.toDouble(),
                      min: 5,
                      max: 60,
                      divisions: 11, // 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
                      label: '$_defaultDurationMinutes minutes',
                      onChanged: (value) {
                        setState(() {
                          _defaultDurationMinutes = value.round();
                        });
                      },
                      onChangeEnd: (_) => _persistPreferences(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                      color: Colors.grey.shade50,
                    ),
                    child: Text(
                      '$_defaultDurationMinutes min',
                      style: theme.bodyLarge.override(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Range: 5 - 60 minutes',
                style: theme.bodySmall.override(
                  color: Colors.grey.shade600,
                ),
              ),
            ],
            // Enable activity-wise estimates switch (only shown when default estimates is ON)
            if (_enableDefaultEstimates) ...[
              const SizedBox(height: 16),
              SwitchListTile(
                title: Text(
                  'Enable activity-wise time estimates',
                  style: theme.bodyMedium.override(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                subtitle: Text(
                  'Set custom time estimates for individual activities',
                  style: theme.bodySmall,
                ),
                value: _enableActivityEstimates,
                onChanged: (value) {
                  setState(() {
                    _enableActivityEstimates = value;
                  });
                  _persistPreferences();
                },
              ),
            ],
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
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _enableDefaultEstimates
                          ? 'When you complete an activity without a time target, it will be logged with the default duration (or custom estimate if set) in your calendar.'
                          : 'Time estimates are disabled. Only manually logged time will be recorded.',
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

