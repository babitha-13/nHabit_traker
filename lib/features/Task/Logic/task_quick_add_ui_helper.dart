import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';

import 'package:habit_tracker/features/activity%20editor/Reminder_config/reminder_config.dart';
import 'package:habit_tracker/features/Task/UI/task_quick_add_widget_builder.dart';
import 'package:habit_tracker/features/activity%20editor/Frequency_config/frequency_config_model.dart';

class TaskQuickAddUIHelper {
  static Widget buildQuickAddWithState(
    BuildContext context,
    StateSetter setModalState,
    StateSetter setState,
    TextEditingController quickAddController,
    String? selectedQuickTrackingType,
    DateTime? selectedQuickDueDate,
    TimeOfDay? selectedQuickDueTime,
    int? quickTimeEstimateMinutes,
    bool quickIsRecurring,
    FrequencyConfig? quickFrequencyConfig,
    List<ReminderConfig> quickReminders,
    int quickTargetNumber,
    Duration quickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    void updateState(VoidCallback fn) {
      setState(fn);
      setModalState(() {}); // Trigger modal rebuild
    }

    return TaskQuickAddWidgetBuilder.buildQuickAdd(
      context,
      updateState,
      quickAddController,
      selectedQuickTrackingType,
      selectedQuickDueDate,
      selectedQuickDueTime,
      quickTimeEstimateMinutes,
      quickIsRecurring,
      quickFrequencyConfig,
      quickReminders,
      quickTargetNumber,
      quickTargetDuration,
      quickTargetNumberController,
      quickHoursController,
      quickMinutesController,
      quickUnitController,
      onTrackingTypeChanged,
      onDueDateChanged,
      onDueTimeChanged,
      onTimeEstimateChanged,
      onRecurringChanged,
      onRemindersChanged,
      onSubmit,
    );
  }

  static Widget buildQuickAdd(
    BuildContext context,
    void Function(VoidCallback) updateState,
    TextEditingController quickAddController,
    String? selectedQuickTrackingType,
    DateTime? selectedQuickDueDate,
    TimeOfDay? selectedQuickDueTime,
    int? quickTimeEstimateMinutes,
    bool quickIsRecurring,
    FrequencyConfig? quickFrequencyConfig,
    List<ReminderConfig> quickReminders,
    int quickTargetNumber,
    Duration quickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    return TaskQuickAddWidgetBuilder.buildQuickAdd(
      context,
      updateState,
      quickAddController,
      selectedQuickTrackingType,
      selectedQuickDueDate,
      selectedQuickDueTime,
      quickTimeEstimateMinutes,
      quickIsRecurring,
      quickFrequencyConfig,
      quickReminders,
      quickTargetNumber,
      quickTargetDuration,
      quickTargetNumberController,
      quickHoursController,
      quickMinutesController,
      quickUnitController,
      onTrackingTypeChanged,
      onDueDateChanged,
      onDueTimeChanged,
      onTimeEstimateChanged,
      onRecurringChanged,
      onRemindersChanged,
      onSubmit,
    );
  }

  static void showQuickAddBottomSheet(
    BuildContext context,
    StateSetter setModalState,
    StateSetter setState,
    TextEditingController quickAddController,
    String? Function() getSelectedQuickTrackingType,
    DateTime? Function() getSelectedQuickDueDate,
    TimeOfDay? Function() getSelectedQuickDueTime,
    int? Function() getQuickTimeEstimateMinutes,
    bool Function() getQuickIsRecurring,
    FrequencyConfig? Function() getQuickFrequencyConfig,
    List<ReminderConfig> Function() getQuickReminders,
    int Function() getQuickTargetNumber,
    Duration Function() getQuickTargetDuration,
    TextEditingController quickTargetNumberController,
    TextEditingController quickHoursController,
    TextEditingController quickMinutesController,
    TextEditingController quickUnitController,
    Function(String?) onTrackingTypeChanged,
    Function(DateTime?) onDueDateChanged,
    Function(TimeOfDay?) onDueTimeChanged,
    Function(int?) onTimeEstimateChanged,
    Function(bool, FrequencyConfig?) onRecurringChanged,
    Function(List<ReminderConfig>) onRemindersChanged,
    Function() onSubmit,
  ) {
    final theme = FlutterFlowTheme.of(context);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      barrierColor: Colors.transparent,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setModalState) {
          final bottomPadding = MediaQuery.of(context).padding.bottom;
          final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
          final totalBottomPadding =
              keyboardHeight > 0 ? keyboardHeight : bottomPadding;

          return Padding(
            padding: EdgeInsets.only(
              bottom: totalBottomPadding,
            ),
            child: Container(
              decoration: BoxDecoration(
                color: theme.primaryBackground,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: buildQuickAddWithState(
                    context,
                    setModalState,
                    setState,
                    quickAddController,
                    getSelectedQuickTrackingType(),
                    getSelectedQuickDueDate(),
                    getSelectedQuickDueTime(),
                    getQuickTimeEstimateMinutes(),
                    getQuickIsRecurring(),
                    getQuickFrequencyConfig(),
                    getQuickReminders(),
                    getQuickTargetNumber(),
                    getQuickTargetDuration(),
                    quickTargetNumberController,
                    quickHoursController,
                    quickMinutesController,
                    quickUnitController,
                    onTrackingTypeChanged,
                    onDueDateChanged,
                    onDueTimeChanged,
                    onTimeEstimateChanged,
                    onRecurringChanged,
                    onRemindersChanged,
                    onSubmit,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  static Future<int?> showQuickTimeEstimateSheet({
    required BuildContext context,
    required FlutterFlowTheme theme,
    required int? initialMinutes,
  }) async {
    return await showModalBottomSheet<int?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _QuickTimeEstimateSheet(
        theme: theme,
        initialMinutes: initialMinutes,
      ),
    );
  }
}

class _QuickTimeEstimateSheet extends StatefulWidget {
  final FlutterFlowTheme theme;
  final int? initialMinutes;

  const _QuickTimeEstimateSheet({
    required this.theme,
    required this.initialMinutes,
  });

  @override
  State<_QuickTimeEstimateSheet> createState() =>
      _QuickTimeEstimateSheetState();
}

class _QuickTimeEstimateSheetState extends State<_QuickTimeEstimateSheet> {
  late TextEditingController controller;

  @override
  void initState() {
    super.initState();
    controller =
        TextEditingController(text: widget.initialMinutes?.toString() ?? '');
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const presets = <int>[5, 10, 15, 20, 30, 45, 60];
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            color: widget.theme.primaryBackground,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border:
                Border.all(color: widget.theme.surfaceBorderColor, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Time estimate',
                  style: widget.theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: 'Minutes (1-600)',
                          hintStyle: TextStyle(
                            color: widget.theme.secondaryText,
                            fontSize: 14,
                          ),
                          filled: true,
                          fillColor: widget.theme.tertiary.withOpacity(0.3),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: widget.theme.surfaceBorderColor),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(
                                color: widget.theme.surfaceBorderColor),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: widget.theme.primary),
                          ),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context, null),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: presets
                      .map(
                        (m) => OutlinedButton(
                          onPressed: () => Navigator.pop(context, m),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(
                                color: widget.theme.surfaceBorderColor),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            foregroundColor: widget.theme.primaryText,
                          ),
                          child: Text('${m}m'),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () {
                      final parsed = int.tryParse(controller.text.trim());
                      if (parsed == null) {
                        Navigator.pop(context, null);
                        return;
                      }
                      Navigator.pop(context, parsed.clamp(1, 600).toInt());
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: widget.theme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
