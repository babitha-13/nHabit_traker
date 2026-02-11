import 'package:flutter/material.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/main.dart';

/// Settings page for managing calendar time logging preferences
class CalendarSettingsPage extends StatefulWidget {
  const CalendarSettingsPage({super.key});

  @override
  State<CalendarSettingsPage> createState() => _CalendarSettingsPageState();
}

class _CalendarSettingsPageState extends State<CalendarSettingsPage> {
  bool _isLoading = true;
  bool _isSaving = false;
  int _defaultDurationMinutes = 10;
  bool _enableDefaultEstimates = true;

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

      await TimeLoggingPreferencesService.updatePreferences(
        userId,
        defaultDurationMinutes: _defaultDurationMinutes,
        enableDefaultEstimates: _enableDefaultEstimates,
      );

      if (mounted) {
        setState(() {
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

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calendar Settings'),
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
                        Icons.calendar_today,
                        color: theme.primary,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Calendar Settings',
                          style: theme.headlineSmall.override(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 32),
                  // Time Logging Settings Card
                  _buildTimeLoggingCard(theme),
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
            // Enable default time logging switch with tooltip
            Row(
              children: [
                Expanded(
                  child: SwitchListTile(
                    title: Text(
                      'Enable default time logging',
                      style: theme.bodyMedium.override(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      'Automatically creates time blocks in the planning calendar and adds time blocks when activities are completed with a default duration',
                      style: theme.bodySmall,
                    ),
                    value: _enableDefaultEstimates,
                    onChanged: (value) {
                      setState(() {
                        _enableDefaultEstimates = value;
                      });
                      _savePreferences();
                    },
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                Tooltip(
                  message:
                      'Applicable for all quantity and binary tasks. Time duration tasks use the logged time. Activity-wise time estimates will override default duration, and any actual time logged will override both default duration and activity-based time estimate.',
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.grey.shade600,
                    size: 20,
                  ),
                ),
              ],
            ),
            // Default duration slider (only shown/enabled when default estimates is ON)
            if (_enableDefaultEstimates) ...[
              const SizedBox(height: 16),
              Text(
                'Default duration of time blocks',
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
                      divisions:
                          11, // 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55, 60
                      label: '$_defaultDurationMinutes minutes',
                      onChanged: (value) {
                        setState(() {
                          _defaultDurationMinutes = value.round();
                        });
                      },
                      onChangeEnd: (_) => _savePreferences(),
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
          ],
        ),
      ),
    );
  }
}
