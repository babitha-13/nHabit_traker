import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_widget.dart';

/// Routine-only wrapper around the shared `FrequencyConfigWidget`.
///
/// Routines only support:
/// - "Every X period"  (maps to routine frequencyType = 'every_x')
/// - "Specific days"   (maps to routine frequencyType = 'specific_days')
///
/// Routines do NOT store date-range, so the date-range UI is hidden.
class RoutineRepeatEditor extends StatefulWidget {
  final String? frequencyType; // 'every_x' | 'specific_days' | null
  final int everyXValue;
  final String? everyXPeriodType; // 'day' | 'week' | 'month'
  final List<int> specificDays; // 1-7
  final Function(String?, int, String?, List<int>) onConfigChanged;

  const RoutineRepeatEditor({
    super.key,
    this.frequencyType,
    this.everyXValue = 1,
    this.everyXPeriodType,
    this.specificDays = const [],
    required this.onConfigChanged,
  });

  @override
  State<RoutineRepeatEditor> createState() => _RoutineRepeatEditorState();
}

class _RoutineRepeatEditorState extends State<RoutineRepeatEditor> {
  bool _enabled = false;
  late FrequencyConfig _config;

  @override
  void initState() {
    super.initState();
    _enabled = widget.frequencyType != null;
    _config = _toFrequencyConfig(
      frequencyType: widget.frequencyType,
      everyXValue: widget.everyXValue,
      everyXPeriodType: widget.everyXPeriodType,
      specificDays: widget.specificDays,
    );
    // Defer initial sync to avoid parent setState during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _notify();
    });
  }

  PeriodType _periodFromRoutine(String? value) {
    switch (value) {
      case 'week':
        return PeriodType.weeks;
      case 'month':
        return PeriodType.months;
      case 'day':
      default:
        return PeriodType.days;
    }
  }

  String _periodToRoutine(PeriodType value) {
    switch (value) {
      case PeriodType.weeks:
        return 'week';
      case PeriodType.months:
        return 'month';
      case PeriodType.days:
      default:
        return 'day';
    }
  }

  FrequencyConfig _toFrequencyConfig({
    required String? frequencyType,
    required int everyXValue,
    required String? everyXPeriodType,
    required List<int> specificDays,
  }) {
    if (frequencyType == 'specific_days') {
      final days =
          specificDays.isNotEmpty ? specificDays : <int>[1, 2, 3, 4, 5, 6, 7];
      return FrequencyConfig(
        type: FrequencyType.specificDays,
        selectedDays: List<int>.from(days)..sort(),
        everyXValue: 1,
        everyXPeriodType: PeriodType.days,
      );
    }
    // Default to Every X.
    return FrequencyConfig(
      type: FrequencyType.everyXPeriod,
      everyXValue: everyXValue < 1 ? 1 : everyXValue,
      everyXPeriodType: _periodFromRoutine(everyXPeriodType),
    );
  }

  void _notify() {
    if (!_enabled) {
      widget.onConfigChanged(null, 1, null, const []);
      return;
    }
    if (_config.type == FrequencyType.specificDays) {
      widget.onConfigChanged(
        'specific_days',
        1,
        null,
        List<int>.from(_config.selectedDays)..sort(),
      );
      return;
    }
    // Every X period
    widget.onConfigChanged(
      'every_x',
      _config.everyXValue < 1 ? 1 : _config.everyXValue,
      _periodToRoutine(_config.everyXPeriodType),
      const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () {
            setState(() => _enabled = false);
            _notify();
          },
          child: Row(
            children: [
              Radio<bool>(
                value: false,
                groupValue: _enabled,
                onChanged: (_) {
                  setState(() => _enabled = false);
                  _notify();
                },
                activeColor: theme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('No repeat', style: theme.bodyMedium),
                    Text(
                      'Reminders will not recur',
                      style:
                          theme.bodySmall.override(color: theme.secondaryText),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        InkWell(
          onTap: () {
            setState(() => _enabled = true);
            _notify();
          },
          child: Row(
            children: [
              Radio<bool>(
                value: true,
                groupValue: _enabled,
                onChanged: (_) {
                  setState(() => _enabled = true);
                  _notify();
                },
                activeColor: theme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              const SizedBox(width: 6),
              Expanded(child: Text('Repeat', style: theme.bodyMedium)),
            ],
          ),
        ),
        if (_enabled) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: FrequencyConfigWidget(
              initialConfig: _config,
              onChanged: (cfg) {
                setState(() => _config = cfg);
                _notify();
              },
              allowedTypes: const {
                FrequencyType.everyXPeriod,
                FrequencyType.specificDays,
              },
              showDateRange: false,
            ),
          ),
        ],
      ],
    );
  }
}
