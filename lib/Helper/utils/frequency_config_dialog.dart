import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/frequency_config_widget.dart';

/// Frequency configuration data model
class FrequencyConfig {
  final FrequencyType type;
  final List<int> selectedDays; // 1-7 for days of week
  final int timesPerPeriod; // For "X times per period"
  final int everyXValue; // For "Every X days/weeks/months"
  final PeriodType periodType; // weeks, months, year
  final PeriodType everyXPeriodType; // days, weeks, months
  final DateTime startDate;
  final DateTime? endDate;
  FrequencyConfig({
    required this.type,
    this.selectedDays = const [],
    this.timesPerPeriod = 1,
    this.everyXValue = 1,
    this.periodType = PeriodType.weeks,
    this.everyXPeriodType = PeriodType.days,
    DateTime? startDate,
    this.endDate,
  }) : startDate = startDate ?? DateTime.now();
  @override
  String toString() {
    return 'FrequencyConfig(type: $type, selectedDays: $selectedDays, timesPerPeriod: $timesPerPeriod, everyXValue: $everyXValue, periodType: $periodType, everyXPeriodType: $everyXPeriodType, startDate: $startDate, endDate: $endDate)';
  }

  FrequencyConfig copyWith({
    FrequencyType? type,
    List<int>? selectedDays,
    int? timesPerPeriod,
    int? everyXValue,
    PeriodType? periodType,
    PeriodType? everyXPeriodType,
    DateTime? startDate,
    DateTime? endDate,
    bool? endDateSet,
  }) {
    return FrequencyConfig(
      type: type ?? this.type,
      selectedDays: selectedDays ?? this.selectedDays,
      timesPerPeriod: timesPerPeriod ?? this.timesPerPeriod,
      everyXValue: everyXValue ?? this.everyXValue,
      periodType: periodType ?? this.periodType,
      everyXPeriodType: everyXPeriodType ?? this.everyXPeriodType,
      startDate: startDate ?? this.startDate,
      endDate: endDateSet == true ? endDate : (endDate ?? this.endDate),
    );
  }
}

enum FrequencyType {
  daily,
  specificDays,
  timesPerPeriod,
  everyXPeriod,
}

enum PeriodType {
  days,
  weeks,
  months,
  year,
}

/// Dialog for configuring task/habit frequency
class FrequencyConfigDialog extends StatefulWidget {
  final FrequencyConfig initialConfig;
  const FrequencyConfigDialog({
    super.key,
    required this.initialConfig,
  });
  @override
  State<FrequencyConfigDialog> createState() => _FrequencyConfigDialogState();
}

class _FrequencyConfigDialogState extends State<FrequencyConfigDialog> {
  late FrequencyConfig _config;
  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(FrequencyConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
  }

  void _save() {
    Navigator.pop(context, _config);
  }

  void _cancel() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.surfaceBorderColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Frequency Configuration',
                      style: theme.titleLarge.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _cancel,
                    icon: Icon(Icons.close, color: theme.secondaryText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SingleChildScrollView(
                  child: FrequencyConfigWidget(
                    initialConfig: _config,
                    onChanged: _updateConfig,
                  ),
                ),
              ),
            ),
            // Action buttons
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                side: BorderSide(color: theme.surfaceBorderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.secondaryText),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
                elevation: 0,
              ),
              child: Text(
                'Save',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show the frequency configuration dialog
Future<FrequencyConfig?> showFrequencyConfigDialog({
  required BuildContext context,
  FrequencyConfig? initialConfig,
}) async {
  return await showDialog<FrequencyConfig>(
    context: context,
    barrierDismissible: false,
    builder: (context) => FrequencyConfigDialog(
      initialConfig:
          initialConfig ?? FrequencyConfig(type: FrequencyType.everyXPeriod),
    ),
  );
}
