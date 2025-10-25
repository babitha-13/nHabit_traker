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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Frequency Configuration',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: theme.primaryText,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _cancel,
                  icon: Icon(Icons.close, color: theme.secondaryText),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Scrollable content
            Flexible(
              child: SingleChildScrollView(
                child: FrequencyConfigWidget(
                  initialConfig: _config,
                  onChanged: _updateConfig,
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }
  Widget _buildActionButtons(FlutterFlowTheme theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _cancel,
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
              side: BorderSide(color: theme.alternate),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'Save',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ),
      ],
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
