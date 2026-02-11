import 'package:flutter/material.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/activity_type_dropdown_helper.dart';
import 'package:intl/intl.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';
import 'activity_editor_helper_service.dart';
import 'activity_editor_frequency_service.dart';
import 'activity_editor_datetime_service.dart';
import 'activity_editor_reminder_service.dart';
import 'activity_editor_save_service.dart';
import 'activity_editor_category_service.dart';

/// Service for building UI widgets
class ActivityEditorUIBuildersService {
  /// Build the main dialog widget
  static Widget build(ActivityEditorDialogState state, BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final title = state.widget.activity == null
        ? (ActivityEditorHelperService.isEssential(state)
            ? 'Create Essential'
            : state.widget.isHabit
                ? 'Create Habit'
                : 'Create Task')
        : (ActivityEditorHelperService.isEssential(state)
            ? 'Edit Essential'
            : state.widget.isHabit
                ? 'Edit Habit'
                : 'Edit Task');

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradient,
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
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                buildTextField(state, theme, state.titleController, 'Name'),
                const SizedBox(height: 12),
                buildCategoryDropdown(state, theme),
                const SizedBox(height: 12),
                buildTextField(state, theme, state.descriptionController,
                    'Description (optional)',
                    maxLines: 2),
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Hide tracking type for essentials (always binary)
                    if (!ActivityEditorHelperService.isEssential(state))
                      buildTaskTypeField(state, theme),
                    if (!ActivityEditorHelperService.isEssential(state) &&
                        (state.selectedTrackingType == 'quantitative' ||
                            state.selectedTrackingType == 'time')) ...[
                      const SizedBox(height: 12),
                      buildTrackingDetails(state, theme),
                    ],
                    const SizedBox(height: 12),
                    buildFrequencyField(state, theme),
                    // Hide due date for essentials (only due time)
                    if (!ActivityEditorHelperService.isRecurring(state) &&
                        !state.widget.isHabit &&
                        !ActivityEditorHelperService.isEssential(state)) ...[
                      const SizedBox(height: 12),
                      buildDueDateField(state, theme),
                    ],
                    const SizedBox(height: 12),
                    buildDueTimeField(state, theme),
                    // Hide reminders for essentials
                    if (!ActivityEditorHelperService.isEssential(state)) ...[
                      const SizedBox(height: 12),
                      buildReminderField(state, theme),
                    ],
                    // Show time estimate field for all activities (not time-target)
                    if (!ActivityEditorHelperService.isTimeTarget(state)) ...[
                      const SizedBox(height: 12),
                      buildTimeEstimateField(state, theme),
                    ],
                  ],
                ),
                // Hide priority for essentials
                if (!ActivityEditorHelperService.isEssential(state)) ...[
                  const SizedBox(height: 12),
                  buildPrioritySlider(state, theme),
                ],
                Container(
                  height: 1,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        theme.surfaceBorderColor,
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                buildActionButtons(state, theme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build text field widget
  static Widget buildTextField(ActivityEditorDialogState state,
      FlutterFlowTheme theme, TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: TextField(
        controller: controller,
        style: theme.bodyMedium,
        maxLines: maxLines,
        maxLength: maxLines == 1 ? 200 : 500,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(
            color: theme.secondaryText,
            fontSize: 14,
          ),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
          counterText: '',
        ),
      ),
    );
  }

  /// Build category dropdown widget
  static Widget buildCategoryDropdown(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    // Use a key to force rebuild when categories or selected category changes
    final categories = ActivityEditorHelperService.getCategories(state);
    final dropdownKey = ValueKey(
        'category_dropdown_${categories.length}_${state.selectedCategoryId}');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: DropdownButtonFormField<String>(
        key: dropdownKey,
        value: ActivityEditorHelperService.getValidCategoryId(state),
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
        dropdownColor: theme.secondaryBackground,
        style: theme.bodySmall,
        hint: Text('Select Category',
            style: TextStyle(color: theme.secondaryText)),
        items: [
          ...categories.map(
            (c) => DropdownMenuItem(
              value: c.reference.id,
              child: Text(
                c.name,
                style: theme.bodySmall,
              ),
            ),
          ),
          DropdownMenuItem(
            value: ActivityEditorHelperService.createNewCategoryValue,
            child: const Row(
              children: [
                Icon(Icons.add, size: 16),
                SizedBox(width: 8),
                Text(
                  'Create New Category...',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
        onChanged: state.isLoadingCategories
            ? null
            : (v) {
                if (v == ActivityEditorHelperService.createNewCategoryValue) {
                  ActivityEditorCategoryService.showCreateCategoryDialog(state);
                } else if (state.mounted) {
                  state.setState(() => state.selectedCategoryId = v);
                }
              },
        menuMaxHeight: 260,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  /// Build task type field widget
  static Widget buildTaskTypeField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    final taskTypes = ActivityTypeDropdownHelper.getAllTaskTypes();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: theme.tertiary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: DropdownButtonFormField<String>(
        value: state.selectedTrackingType ?? 'binary',
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        isExpanded: true,
        icon: Icon(Icons.keyboard_arrow_down, color: theme.secondaryText),
        dropdownColor: theme.secondaryBackground,
        style: theme.bodySmall,
        items: taskTypes
            .map(
              (t) => DropdownMenuItem<String>(
                value: t.value,
                child: Row(
                  children: [
                    Icon(t.icon, size: 16, color: theme.secondaryText),
                    const SizedBox(width: 8),
                    Text(
                      t.label,
                      style: theme.bodySmall,
                    ),
                  ],
                ),
              ),
            )
            .toList(),
        onChanged: (value) {
          state.setState(() {
            state.selectedTrackingType = value;
            if (value == 'binary') {
              state.targetNumber = 1;
              state.targetDuration = const Duration(hours: 1);
              state.unitController.clear();
            }
          });
        },
        menuMaxHeight: 220,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  /// Build tracking details widget
  static Widget buildTrackingDetails(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.accent2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.surfaceBorderColor),
      ),
      child: state.selectedTrackingType == 'quantitative'
          ? Row(
              children: [
                Text('Target:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue: state.targetNumber.toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: inputDecoration(theme),
                  onChanged: (v) {
                    state.setState(() {
                      state.targetNumber = int.tryParse(v) ?? 1;
                    });
                  },
                )),
                const SizedBox(width: 8),
                Text('Unit:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  controller: state.unitController,
                  style: theme.bodyMedium,
                  decoration: inputDecoration(theme, hint: 'e.g. pages'),
                  onChanged: (v) {
                    state.setState(() {
                      state.unit = v;
                    });
                  },
                )),
              ],
            )
          : Row(
              children: [
                Text('Duration:',
                    style: theme.bodySmall.override(
                        color: theme.primary, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue: state.targetDuration.inHours.toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: inputDecoration(theme, label: 'Hrs'),
                  onChanged: (v) {
                    final h = int.tryParse(v) ?? 0;
                    state.setState(() => state.targetDuration = Duration(
                        hours: h,
                        minutes: state.targetDuration.inMinutes % 60));
                  },
                )),
                const SizedBox(width: 8),
                Expanded(
                    child: TextFormField(
                  initialValue:
                      (state.targetDuration.inMinutes % 60).toString(),
                  keyboardType: TextInputType.number,
                  style: theme.bodyMedium,
                  decoration: inputDecoration(theme, label: 'Min'),
                  onChanged: (v) {
                    final m = int.tryParse(v) ?? 0;
                    state.setState(() => state.targetDuration = Duration(
                        hours: state.targetDuration.inHours, minutes: m));
                  },
                )),
              ],
            ),
    );
  }

  /// Build time estimate field widget
  static Widget buildTimeEstimateField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    final hintText = state.defaultTimeEstimateMinutes != null
        ? '${state.defaultTimeEstimateMinutes!} mins (default)'
        : 'Leave empty to use default';

    return InputDecorator(
      decoration: InputDecoration(
        labelText: 'Time Estimate',
        labelStyle: TextStyle(color: theme.secondaryText),
        filled: true,
        fillColor: theme.tertiary.withOpacity(0.4),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: theme.surfaceBorderColor),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      child: Row(
        children: [
          Icon(Icons.timelapse, size: 20, color: theme.secondaryText),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: state.timeEstimateMinutes?.toString() ?? '',
              keyboardType: TextInputType.number,
              style: theme.bodyMedium,
              decoration: InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: hintText,
                hintStyle: theme.bodySmall.override(
                  color: theme.secondaryText.withOpacity(0.65),
                ),
              ),
              onChanged: (v) {
                state.setState(() {
                  state.timeEstimateMinutes =
                      v.isEmpty ? null : int.tryParse(v);
                });
              },
            ),
          ),
          if (state.timeEstimateMinutes != null)
            IconButton(
              icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () =>
                  state.setState(() => state.timeEstimateMinutes = null),
            ),
        ],
      ),
    );
  }

  /// Input decoration helper
  static InputDecoration inputDecoration(FlutterFlowTheme theme,
      {String? hint, String? label, TextStyle? hintStyle}) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      filled: true,
      fillColor: theme.secondaryBackground,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: theme.surfaceBorderColor)),
      hintText: hint,
      hintStyle: hintStyle,
      labelText: label,
    );
  }

  /// Build frequency field widget
  static Widget buildFrequencyField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    String displayText;
    if (ActivityEditorHelperService.isEssential(state)) {
      // Essentials: show "Manual only" if frequency disabled
      displayText = state.frequencyEnabled && state.frequencyConfig != null
          ? ActivityEditorFrequencyService.formatFrequencySummary(state)
          : "Manual only (won't auto-schedule)";
    } else {
      displayText = ActivityEditorHelperService.isRecurring(state)
          ? ActivityEditorFrequencyService.formatFrequencySummary(state)
          : 'One-time task';
    }
    return InkWell(
      onTap: () =>
          ActivityEditorFrequencyService.handleOpenFrequencyConfig(state),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor, width: 1),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                displayText,
                style: theme.bodyMedium.override(
                  color: (ActivityEditorHelperService.isEssential(state) &&
                              !state.frequencyEnabled) ||
                          (!ActivityEditorHelperService.isEssential(state) &&
                              !ActivityEditorHelperService.isRecurring(state))
                      ? theme.secondaryText
                      : theme.primaryText,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if ((ActivityEditorHelperService.isRecurring(state) &&
                    !state.widget.isHabit &&
                    !ActivityEditorHelperService.isEssential(state)) ||
                (ActivityEditorHelperService.isEssential(state) &&
                    state.frequencyEnabled))
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    ActivityEditorFrequencyService.clearFrequency(state),
              ),
            const SizedBox(width: 6),
            Icon(Icons.keyboard_arrow_down,
                color: theme.secondaryText, size: 20),
          ],
        ),
      ),
    );
  }

  /// Build due date field widget
  static Widget buildDueDateField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    final label = state.dueDate != null
        ? DateFormat('MMM dd, yyyy').format(state.dueDate!)
        : 'Set due date';
    return InkWell(
      onTap: () => ActivityEditorDateTimeService.pickDueDate(state),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Date',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (state.dueDate != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => state.setState(() => state.dueDate = null),
              ),
          ],
        ),
      ),
    );
  }

  /// Build due time field widget
  static Widget buildDueTimeField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    final label = state.selectedDueTime != null
        ? state.selectedDueTime!.format(state.context)
        : 'Set due time';
    return InkWell(
      onTap: () => ActivityEditorDateTimeService.pickDueTime(state),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Due Time',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.access_time, size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (state.selectedDueTime != null)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () =>
                    state.setState(() => state.selectedDueTime = null),
              ),
          ],
        ),
      ),
    );
  }

  /// Build reminder field widget
  static Widget buildReminderField(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    final label = ActivityEditorReminderService.reminderSummary(state);
    return InkWell(
      onTap: () => ActivityEditorReminderService.openReminderDialog(state),
      borderRadius: BorderRadius.circular(10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: 'Reminders',
          labelStyle: TextStyle(color: theme.secondaryText),
          filled: true,
          fillColor: theme.tertiary.withOpacity(0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: theme.surfaceBorderColor),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        ),
        child: Row(
          children: [
            Icon(Icons.notifications_none,
                size: 20, color: theme.secondaryText),
            const SizedBox(width: 12),
            Expanded(child: Text(label, style: theme.bodyMedium)),
            if (state.reminders.isNotEmpty)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: theme.secondaryText),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => state.setState(() => state.reminders = []),
              ),
          ],
        ),
      ),
    );
  }

  /// Build priority slider widget
  static Widget buildPrioritySlider(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: Row(
        children: [
          Text('Priority:', style: theme.bodyMedium),
          const SizedBox(width: 12),
          Expanded(
            child: Slider(
              value: state.priority.toDouble(),
              min: 1.0,
              max: 3.0,
              divisions: 2,
              label: state.priority.toString(),
              activeColor: theme.primary,
              inactiveColor: theme.secondaryText.withOpacity(0.3),
              onChanged: (value) =>
                  state.setState(() => state.priority = value.round()),
            ),
          ),
        ],
      ),
    );
  }

  /// Build action buttons widget
  static Widget buildActionButtons(
      ActivityEditorDialogState state, FlutterFlowTheme theme) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          onPressed: state.isSaving
              ? null
              : () {
                  // Defer pop to next frame to avoid Navigator lock conflicts
                  Future.microtask(() {
                    if (state.mounted) {
                      Navigator.of(state.context).pop(false);
                    }
                  });
                },
          child: Text('Cancel', style: theme.bodyMedium),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            gradient: theme.primaryButtonGradient,
            borderRadius: BorderRadius.circular(theme.buttonRadius),
          ),
          child: ElevatedButton(
            onPressed: state.isSaving
                ? null
                : () => ActivityEditorSaveService.save(state),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              shadowColor: Colors.transparent,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: state.isSaving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2))
                : Text('Save',
                    style: theme.bodyMedium.override(
                        color: Colors.white, fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }
}
