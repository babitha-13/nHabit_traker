import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
/// Helper class for task frequency/recurring functionality
/// Separates business logic from UI components
class TaskFrequencyHelper {
  /// Schedule options for recurring tasks
  static const List<String> scheduleOptions = ['daily', 'weekly', 'monthly'];
  /// Week days for selection (Monday = 1, Sunday = 7)
  static const List<String> weekDays = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  /// Short week day labels for chips
  static const List<String> weekDayShort = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun'
  ];
  /// Get display label for schedule option
  static String getScheduleLabel(String schedule) {
    switch (schedule) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      default:
        return 'Daily';
    }
  }
  /// Get frequency input label based on schedule
  static String getFrequencyLabel(String schedule) {
    switch (schedule) {
      case 'weekly':
        return 'Times per week';
      case 'monthly':
        return 'Times per month';
      default:
        return 'Frequency';
    }
  }
  /// Check if frequency input should be shown
  static bool shouldShowFrequencyInput(String? schedule) {
    return schedule == 'weekly' || schedule == 'monthly';
  }
  /// Check if day selection should be shown
  static bool shouldShowDaySelection(String? schedule) {
    return schedule == 'weekly';
  }
  /// Validate frequency value based on schedule
  static bool isValidFrequency(String schedule, int frequency) {
    if (frequency <= 0) return false;
    switch (schedule) {
      case 'weekly':
        return frequency <= 7; // Max 7 times per week
      case 'monthly':
        return frequency <= 31; // Max 31 times per month
      default:
        return true;
    }
  }
  /// Validate selected days for weekly schedule
  static bool isValidDaySelection(String schedule, List<int> selectedDays) {
    if (schedule != 'weekly') return true;
    return selectedDays.isNotEmpty && selectedDays.length <= 7;
  }
  /// Get weekday index (1-7) from list index (0-6)
  static int getWeekdayIndex(int listIndex) {
    return listIndex + 1; // Monday = 1, Sunday = 7
  }
  /// Get list index (0-6) from weekday index (1-7)
  static int getListIndex(int weekdayIndex) {
    return weekdayIndex - 1;
  }
  /// Check if a specific day is selected
  static bool isDaySelected(List<int> selectedDays, int dayIndex) {
    return selectedDays.contains(getWeekdayIndex(dayIndex));
  }
  /// Toggle day selection
  static List<int> toggleDay(List<int> selectedDays, int dayIndex) {
    final weekdayIndex = getWeekdayIndex(dayIndex);
    final newList = List<int>.from(selectedDays);
    if (newList.contains(weekdayIndex)) {
      newList.remove(weekdayIndex);
    } else {
      newList.add(weekdayIndex);
    }
    return newList..sort();
  }
  /// Get default frequency for schedule type
  static int getDefaultFrequency(String schedule) {
    switch (schedule) {
      case 'weekly':
        return 3; // 3 times per week
      case 'monthly':
        return 4; // 4 times per month
      default:
        return 1;
    }
  }
  /// Format selected days for display
  static String formatSelectedDays(List<int> selectedDays) {
    if (selectedDays.isEmpty) return 'No days selected';
    final dayNames =
        selectedDays.map((index) => weekDayShort[getListIndex(index)]).toList();
    if (dayNames.length <= 3) {
      return dayNames.join(', ');
    } else {
      return '${dayNames.take(2).join(', ')} +${dayNames.length - 2} more';
    }
  }
}
/// Custom dropdown widget for schedule selection
class ScheduleDropdown extends StatelessWidget {
  final String? selectedSchedule;
  final ValueChanged<String?> onChanged;
  final String? tooltip;
  const ScheduleDropdown({
    super.key,
    required this.selectedSchedule,
    required this.onChanged,
    this.tooltip,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.alternate,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: DropdownButtonFormField<String>(
        value: selectedSchedule,
        decoration: const InputDecoration(
          labelText: 'Schedule',
          labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          isDense: true,
        ),
        items: TaskFrequencyHelper.scheduleOptions.map((schedule) {
          return DropdownMenuItem<String>(
            value: schedule,
            child: Text(
              TaskFrequencyHelper.getScheduleLabel(schedule),
              style: const TextStyle(fontSize: 11),
            ),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
/// Custom widget for day selection chips
class DaySelectionChips extends StatelessWidget {
  final List<int> selectedDays;
  final ValueChanged<List<int>> onChanged;
  const DaySelectionChips({
    super.key,
    required this.selectedDays,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Days of week:',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: theme.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: List.generate(7, (index) {
            final isSelected =
                TaskFrequencyHelper.isDaySelected(selectedDays, index);
            return FilterChip(
              label: Text(
                TaskFrequencyHelper.weekDayShort[index],
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? Colors.white : theme.primaryText,
                ),
              ),
              selected: isSelected,
              selectedColor: theme.primary,
              backgroundColor: theme.secondaryBackground,
              side: BorderSide(
                color: isSelected ? theme.primary : theme.alternate,
                width: 1,
              ),
              onSelected: (selected) {
                final newDays =
                    TaskFrequencyHelper.toggleDay(selectedDays, index);
                onChanged(newDays);
              },
            );
          }),
        ),
      ],
    );
  }
}
/// Custom widget for frequency input
class FrequencyInput extends StatelessWidget {
  final String? schedule;
  final int frequency;
  final ValueChanged<int> onChanged;
  const FrequencyInput({
    super.key,
    required this.schedule,
    required this.frequency,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: frequency.toString(),
      decoration: InputDecoration(
        labelText: schedule != null
            ? TaskFrequencyHelper.getFrequencyLabel(schedule!)
            : 'Frequency',
        labelStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 11),
      keyboardType: TextInputType.number,
      onChanged: (value) {
        final newFrequency = int.tryParse(value) ?? 1;
        if (schedule != null &&
            TaskFrequencyHelper.isValidFrequency(schedule!, newFrequency)) {
          onChanged(newFrequency);
        }
      },
    );
  }
}
