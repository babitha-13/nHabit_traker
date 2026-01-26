import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/manual_time_log_helper.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_preview_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_datetime_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_save_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_helper_service.dart';
import 'package:habit_tracker/Screens/Shared/Manual Time Log/Services/manual_time_log_search_service.dart';

/// Service for building UI widgets
class ManualTimeLogUIBuildersService {
  /// Build the main widget
  static Widget build(ManualTimeLogModalState state, BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final isEditMode = state.widget.editMetadata != null;
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final hasKeyboard = keyboardInset > 0;

    // When keyboard is shown, we want the container to be pushed up by keyboardInset.
    // When keyboard is not shown, we want it to respect the bottom safe area.
    final containerBottomPadding = hasKeyboard ? keyboardInset : bottomSafeArea;

    // This padding is inside the scrollable area or at the bottom of the content.
    final contentBottomPadding = hasKeyboard ? 8.0 : 12.0;

    return WillPopScope(
      onWillPop: () => ManualTimeLogHelperService.onWillPop(state),
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: EdgeInsets.only(
            bottom: containerBottomPadding,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: Colors.grey[200], height: 1),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: contentBottomPadding),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Activity Type Selector
                        Row(
                          children: [
                            buildTypeChip(state, 'Task', 'task', theme),
                            const SizedBox(width: 8),
                            buildTypeChip(state, 'Habit', 'habit', theme),
                            const SizedBox(width: 8),
                            buildTypeChip(state, 'essential', 'essential', theme),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Activity Input with Overlay Dropdown
                        Container(
                          key: state.textFieldKey,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(minHeight: 42),
                          decoration: BoxDecoration(
                            color: theme.tertiary.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: theme.surfaceBorderColor,
                              width: 1,
                            ),
                          ),
                          child: TextField(
                            controller: state.activityController,
                            focusNode: state.activityFocusNode,
                            style: theme.bodyMedium,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: state.selectedType == 'habit'
                                  ? 'Search existing habit...'
                                  : 'Create New or Search...',
                              hintStyle: TextStyle(
                                color: theme.secondaryText,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(vertical: 10),
                              icon: const Icon(Icons.search,
                                  size: 20, color: Colors.grey),
                              suffixIcon: state.activityController.text.isNotEmpty
                                  ? IconButton(
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.clear, size: 16),
                                      onPressed: () {
                                        state.activityController.clear();
                                        state.setState(() {
                                          state.selectedTemplate = null;
                                          ManualTimeLogHelperService.updateDefaultCategory(state);
                                        });
                                        ManualTimeLogSearchService.removeOverlay(state);
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Category Dropdown
                        buildCategoryDropdown(state, theme),

                        const SizedBox(height: 10),

                        // Time Pickers Row
                        Row(
                          children: [
                            Expanded(
                              child: InkWell(
                                onTap: () => ManualTimeLogDateTimeService.pickStartTime(state),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 12),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time,
                                          size: 18, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat.jm().format(state.startTime),
                                        style: theme.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.arrow_forward,
                                  size: 16, color: Colors.grey),
                            ),
                            Expanded(
                              child: InkWell(
                                onTap: () => ManualTimeLogDateTimeService.pickEndTime(state),
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 12, horizontal: 12),
                                  decoration: BoxDecoration(
                                    border:
                                        Border.all(color: Colors.grey.shade300),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.access_time_filled,
                                          size: 18, color: Colors.grey),
                                      const SizedBox(width: 8),
                                      Text(
                                        DateFormat.jm().format(state.endTime),
                                        style: theme.bodyMedium.copyWith(
                                            fontWeight: FontWeight.w600),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        // Completion Controls (conditional based on tracking type)
                        if (state.selectedTemplate != null) ...[
                          buildCompletionControls(state, theme),
                          const SizedBox(height: 12),
                        ],

                        const SizedBox(height: 6),

                        // Submit Button (and delete when editing)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: state.isLoading ? null : () => ManualTimeLogSaveService.saveEntry(state),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primary,
                                  foregroundColor: Colors.white,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 16),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  elevation: 0,
                                ),
                                child: state.isLoading
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2),
                                      )
                                    : Text(
                                        isEditMode
                                            ? 'Update Entry'
                                            : 'Log Time Entry',
                                        style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold),
                                      ),
                              ),
                            ),
                            if (isEditMode) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                padding: const EdgeInsets.all(8),
                                constraints: const BoxConstraints(),
                                icon: const Icon(Icons.delete),
                                color: Colors.red,
                                tooltip: 'Delete entry',
                                onPressed: state.isLoading ? null : () => ManualTimeLogSaveService.deleteEntry(state),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Build type chip widget
  static Widget buildTypeChip(ManualTimeLogModalState state, String label, String value, FlutterFlowTheme theme) {
    final isSelected = state.selectedType == value;
    Color color;
    if (value == 'habit') {
      color = Colors.orange;
    } else if (value == 'essential') {
      color = Colors.grey;
    } else {
      color = theme.primary; // Task
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => ManualTimeLogPreviewService.selectType(state, value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : Colors.grey.shade300,
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey.shade600,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Build category dropdown widget
  static Widget buildCategoryDropdown(ManualTimeLogModalState state, FlutterFlowTheme theme) {
    // If habit is selected, we usually don't allow changing category for existing ones
    final isLocked = state.selectedTemplate != null;

    final filteredCategories = isLocked
        ? <CategoryRecord>[]
        : state.allCategories
            .where((category) => category.categoryType == state.selectedType)
            .toList();
    final dropdownCategories =
        filteredCategories.isNotEmpty ? filteredCategories : state.allCategories;

    // Ensure the selected category exists in the dropdown items
    // If not, set it to null to avoid assertion errors
    CategoryRecord? validSelectedCategory = state.selectedCategory;
    if (!isLocked &&
        validSelectedCategory != null &&
        dropdownCategories.isNotEmpty) {
      final existsInItems = dropdownCategories.any((category) =>
          category.reference.id == validSelectedCategory!.reference.id);
      if (!existsInItems) {
        validSelectedCategory = null;
      }
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: isLocked ? Colors.grey[100] : theme.tertiary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<CategoryRecord>(
          value: validSelectedCategory,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            icon: Icon(Icons.category, size: 20, color: Colors.grey),
          ),
          hint: Text('Select Category', style: theme.bodySmall),
          isExpanded: true,
          style: theme.bodyMedium,
          disabledHint: state.selectedCategory != null
              ? Text(state.selectedCategory!.name, style: theme.bodyMedium)
              : null,
          items: isLocked
              ? null
              : dropdownCategories.map((category) {
                  Color categoryColor;
                  try {
                    categoryColor = Color(
                        int.parse(category.color.replaceFirst('#', '0xFF')));
                  } catch (e) {
                    categoryColor = theme.primary;
                  }
                  return DropdownMenuItem<CategoryRecord>(
                    value: category,
                    child: Row(
                      children: [
                        Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(category.name),
                      ],
                    ),
                  );
                }).toList(),
          onChanged: isLocked
              ? null
              : (value) {
                  state.setState(() {
                    state.selectedCategory = value;
                  });
                },
        ),
      ),
    );
  }

  /// Build completion controls widget
  static Widget buildCompletionControls(ManualTimeLogModalState state, FlutterFlowTheme theme) {
    if (state.selectedTemplate == null) return const SizedBox.shrink();

    final trackingType = state.selectedTemplate!.trackingType;

    // Binary tasks: Show checkbox
    if (trackingType == 'binary') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor),
        ),
        child: Row(
          children: [
            Checkbox(
              value: state.markAsComplete,
              onChanged: (value) {
                state.setState(() {
                  state.markAsComplete = value ?? false;
                });
              },
              activeColor: theme.primary,
            ),
            Expanded(
              child: Text(
                'Mark as complete',
                style: theme.bodyMedium,
              ),
            ),
          ],
        ),
      );
    }

    // Quantity tasks: Show stepper
    if (trackingType == 'qty') {
      final target = state.selectedTemplate!.target;
      final unit = state.selectedTemplate!.unit;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.tertiary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: theme.surfaceBorderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quantity Progress',
              style: theme.bodySmall.copyWith(
                color: theme.secondaryText,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () {
                    state.setState(() {
                      if (state.quantityValue > 0) state.quantityValue--;
                    });
                  },
                  color: theme.primary,
                ),
                Expanded(
                  child: Text(
                    '${state.quantityValue}${target != null ? ' / $target' : ''} $unit',
                    textAlign: TextAlign.center,
                    style: theme.titleMedium.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () {
                    state.setState(() {
                      state.quantityValue++;
                    });
                  },
                  color: theme.primary,
                ),
              ],
            ),
          ],
        ),
      );
    }

    // Time duration tasks: Show info text only if target is set (> 0)
    if (trackingType == 'time') {
      final target = state.selectedTemplate!.target;
      final targetMinutes =
          target is int ? target : (target is double ? target.toInt() : 0);

      // Only show completion message if target is set (greater than 0)
      if (targetMinutes > 0) {
        final hours = targetMinutes ~/ 60;
        final minutes = targetMinutes % 60;
        final targetStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Will auto-complete if total time reaches $targetStr',
                  style: theme.bodySmall.copyWith(
                    color: Colors.blue.shade700,
                  ),
                ),
              ),
            ],
          ),
        );
      }
      // If no target, don't show any completion message
      return const SizedBox.shrink();
    }

    // essential or unknown: No controls
    return const SizedBox.shrink();
  }
}
