import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
/// Helper class for task type dropdown functionality
/// Separates business logic from UI components
class TaskTypeDropdownHelper {
  /// Task type definitions with icons and labels
  static const Map<String, TaskTypeInfo> taskTypes = {
    'binary': TaskTypeInfo(
      value: 'binary',
      label: 'To-do',
      icon: Icons.task_alt,
    ),
    'quantitative': TaskTypeInfo(
      value: 'quantitative',
      label: 'Quantity',
      icon: Icons.numbers,
    ),
    'time': TaskTypeInfo(
      value: 'time',
      label: 'Duration',
      icon: Icons.access_time,
    ),
  };
  /// Get task type info by value
  static TaskTypeInfo? getTaskTypeInfo(String? value) {
    return taskTypes[value];
  }
  /// Get icon for task type value
  static IconData getIconForType(String? value) {
    return taskTypes[value]?.icon ?? Icons.task_alt;
  }
  /// Get label for task type value
  static String getLabelForType(String? value) {
    return taskTypes[value]?.label ?? 'To-do';
  }
  /// Get all task type options for dropdown
  static List<TaskTypeInfo> getAllTaskTypes() {
    return taskTypes.values.toList();
  }
  /// Validate task type value
  static bool isValidTaskType(String? value) {
    return taskTypes.containsKey(value);
  }
}
/// Data class for task type information
class TaskTypeInfo {
  final String value;
  final String label;
  final IconData icon;
  const TaskTypeInfo({
    required this.value,
    required this.label,
    required this.icon,
  });
}
/// Custom icon-based dropdown widget for task types
class IconTaskTypeDropdown extends StatelessWidget {
  final String? selectedValue;
  final ValueChanged<String?> onChanged;
  final String? tooltip;
  const IconTaskTypeDropdown({
    super.key,
    required this.selectedValue,
    required this.onChanged,
    this.tooltip,
  });
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final selectedInfo = TaskTypeDropdownHelper.getTaskTypeInfo(selectedValue);
    // Always highlight when a value is selected (including 'binary')
    final isSelected = selectedValue != null;
    
    return Container(
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.accent1.withOpacity(0.1)
            : theme.tertiary,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isSelected ? theme.accent1 : theme.surfaceBorderColor,
          width: 1,
        ),
        boxShadow: isSelected ? [
          BoxShadow(
            color: theme.accent1.withOpacity(0.2),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ] : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            // Show popup menu manually
            final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
            final Offset? offset = renderBox?.localToGlobal(Offset.zero);
            if (offset != null && renderBox != null) {
              showMenu<String>(
                context: context,
                position: RelativeRect.fromLTRB(
                  offset.dx,
                  offset.dy + renderBox.size.height,
                  offset.dx + renderBox.size.width,
                  offset.dy + renderBox.size.height + 200,
                ),
                items: TaskTypeDropdownHelper.getAllTaskTypes().map((taskType) {
                  return PopupMenuItem<String>(
                    value: taskType.value,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          taskType.icon,
                          size: 18,
                          color: selectedValue == taskType.value
                              ? theme.primary
                              : theme.secondaryText,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          taskType.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: selectedValue == taskType.value
                                ? theme.primary
                                : theme.primaryText,
                            fontWeight: selectedValue == taskType.value
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ).then((value) {
                if (value != null) {
                  onChanged(value);
                }
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.all(8),
            child: Icon(
              selectedInfo?.icon ?? Icons.task_alt,
              color: isSelected ? theme.accent1 : theme.secondary,
              size: 18,
            ),
          ),
        ),
      ),
    );
  }
}
