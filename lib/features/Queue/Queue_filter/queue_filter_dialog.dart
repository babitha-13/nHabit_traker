import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Queue/Queue_filter/queue_filter_state_manager.dart'
    show QueueFilterState;

Widget buildFilterButton({
  required BuildContext context,
  required QueueFilterState currentFilter,
  required List<CategoryRecord> categories,
  required Function(QueueFilterState) onFilterChanged,
  required bool isDefaultFilterState,
  required int excludedCategoryCount,
}) {
  final theme = FlutterFlowTheme.of(context);
  final isFilterActive = !isDefaultFilterState;

  return Stack(
    clipBehavior: Clip.none,
    children: [
      Container(
        decoration: BoxDecoration(
          color: isFilterActive
              ? theme.primary.withOpacity(0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isFilterActive
              ? Border.all(
                  color: theme.primary.withOpacity(0.4),
                  width: 1.5,
                )
              : null,
        ),
        child: IconButton(
          icon: Icon(
            Icons.filter_list,
            color: isFilterActive ? theme.primary : theme.secondaryText,
          ),
          onPressed: () async {
            final result = await showQueueFilterDialog(
              context: context,
              categories: categories,
              initialFilter: currentFilter,
            );
            if (result != null) {
              onFilterChanged(result);
            }
          },
          tooltip: 'Filter',
        ),
      ),
      if (excludedCategoryCount > 0)
        Positioned(
          right: 4,
          top: 4,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.primaryBackground,
                width: 1.5,
              ),
            ),
            constraints: const BoxConstraints(
              minWidth: 18,
              minHeight: 18,
            ),
            child: Center(
              child: Text(
                excludedCategoryCount > 99 ? '99+' : '$excludedCategoryCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
    ],
  );
}

/// Dialog for filtering queue items by type and categories
class QueueFilterDialog extends StatefulWidget {
  final List<CategoryRecord> categories;
  final QueueFilterState initialFilter;

  const QueueFilterDialog({
    super.key,
    required this.categories,
    required this.initialFilter,
  });

  @override
  State<QueueFilterDialog> createState() => _QueueFilterDialogState();
}

class _QueueFilterDialogState extends State<QueueFilterDialog> {
  late bool _allTasks;
  late bool _allHabits;
  late Set<String> _selectedHabitCategoryNames;
  late Set<String> _selectedTaskCategoryNames;

  @override
  void initState() {
    super.initState();
    _selectedHabitCategoryNames =
        Set<String>.from(widget.initialFilter.selectedHabitCategoryNames);
    _selectedTaskCategoryNames =
        Set<String>.from(widget.initialFilter.selectedTaskCategoryNames);

    // Sync "All Habits" and "All Tasks" with actual category selections
    // If all categories are selected, mark the "All" checkbox as checked
    final allHabitNames = _habitCategories.map((cat) => cat.name).toSet();
    final allTaskNames = _taskCategories.map((cat) => cat.name).toSet();

    _allHabits = widget.initialFilter.allHabits ||
        (allHabitNames.isNotEmpty &&
            _selectedHabitCategoryNames.length == allHabitNames.length &&
            allHabitNames
                .every((name) => _selectedHabitCategoryNames.contains(name)));

    _allTasks = widget.initialFilter.allTasks ||
        (allTaskNames.isNotEmpty &&
            _selectedTaskCategoryNames.length == allTaskNames.length &&
            allTaskNames
                .every((name) => _selectedTaskCategoryNames.contains(name)));

    // IMPORTANT: If allHabits/allTasks is true but selectedHabitCategoryNames is empty,
    // populate it with all category names so that when user unchecks one category,
    // the remaining categories are still in the set
    if (_allHabits &&
        _selectedHabitCategoryNames.isEmpty &&
        allHabitNames.isNotEmpty) {
      _selectedHabitCategoryNames = Set<String>.from(allHabitNames);
    }
    if (_allTasks &&
        _selectedTaskCategoryNames.isEmpty &&
        allTaskNames.isNotEmpty) {
      _selectedTaskCategoryNames = Set<String>.from(allTaskNames);
    }
  }

  List<CategoryRecord> get _habitCategories {
    return widget.categories
        .where((cat) => cat.categoryType == 'habit')
        .toList();
  }

  List<CategoryRecord> get _taskCategories {
    return widget.categories
        .where((cat) => cat.categoryType == 'task')
        .toList();
  }

  /// Check if all habit categories are selected
  bool get _allHabitCategoriesSelected {
    if (_habitCategories.isEmpty) return false;
    return _habitCategories
        .every((cat) => _selectedHabitCategoryNames.contains(cat.name));
  }

  /// Check if some (but not all) habit categories are selected
  bool get _someHabitCategoriesSelected {
    if (_habitCategories.isEmpty) return false;
    return _selectedHabitCategoryNames.isNotEmpty &&
        !_allHabitCategoriesSelected;
  }

  /// Check if all task categories are selected
  bool get _allTaskCategoriesSelected {
    if (_taskCategories.isEmpty) return false;
    return _taskCategories
        .every((cat) => _selectedTaskCategoryNames.contains(cat.name));
  }

  /// Check if some (but not all) task categories are selected
  bool get _someTaskCategoriesSelected {
    if (_taskCategories.isEmpty) return false;
    return _selectedTaskCategoryNames.isNotEmpty && !_allTaskCategoriesSelected;
  }

  /// Toggle "All Habits" - checks/unchecks all habit categories
  /// Handles tristate: null (indeterminate) -> true, true -> false, false -> true
  void _toggleAllHabits(bool? value) {
    setState(() {
      if (value == true) {
        // Check all habit categories
        _allHabits = true;
        final allHabitNames = _habitCategories.map((cat) => cat.name).toSet();
        _selectedHabitCategoryNames = Set<String>.from(allHabitNames);
      } else {
        // Uncheck all habit categories (whether coming from checked or indeterminate)
        _allHabits = false;
        _selectedHabitCategoryNames.clear();
      }
    });
  }

  /// Toggle "All Tasks" - checks/unchecks all task categories
  /// Handles tristate: null (indeterminate) -> true, true -> false, false -> true
  void _toggleAllTasks(bool? value) {
    setState(() {
      if (value == true) {
        // Check all task categories
        _allTasks = true;
        final allTaskNames = _taskCategories.map((cat) => cat.name).toSet();
        _selectedTaskCategoryNames = Set<String>.from(allTaskNames);
      } else {
        // Uncheck all task categories (whether coming from checked or indeterminate)
        _allTasks = false;
        _selectedTaskCategoryNames.clear();
      }
    });
  }

  /// Toggle a habit category - updates "All Habits" if needed
  void _toggleHabitCategory(String categoryName) {
    setState(() {
      if (_selectedHabitCategoryNames.contains(categoryName)) {
        _selectedHabitCategoryNames.remove(categoryName);
        // If "All Habits" was checked, uncheck it when any category is unchecked
        if (_allHabits) {
          _allHabits = false;
          // When transitioning from "all" to "partial", ensure remaining categories are in the set
          // This handles the case where _selectedHabitCategoryNames might have been empty
          final allHabitNames = _habitCategories.map((cat) => cat.name).toSet();
          // Add all categories except the one being removed
          _selectedHabitCategoryNames =
              allHabitNames.where((name) => name != categoryName).toSet();
        }
        // Note: _allHabits stays false when some categories remain selected (partial selection)
      } else {
        _selectedHabitCategoryNames.add(categoryName);
        // If all habit categories are now selected, check "All Habits"
        if (_allHabitCategoriesSelected) {
          _allHabits = true;
        }
        // Note: _allHabits stays false when not all categories are selected (partial selection)
      }
    });
  }

  /// Toggle a task category - updates "All Tasks" if needed
  void _toggleTaskCategory(String categoryName) {
    setState(() {
      if (_selectedTaskCategoryNames.contains(categoryName)) {
        _selectedTaskCategoryNames.remove(categoryName);
        // If "All Tasks" was checked, uncheck it when any category is unchecked
        if (_allTasks) {
          _allTasks = false;
          // When transitioning from "all" to "partial", ensure remaining categories are in the set
          // This handles the case where _selectedTaskCategoryNames might have been empty
          final allTaskNames = _taskCategories.map((cat) => cat.name).toSet();
          // Add all categories except the one being removed
          _selectedTaskCategoryNames =
              allTaskNames.where((name) => name != categoryName).toSet();
        }
        // Note: _allTasks stays false when some categories remain selected (partial selection)
      } else {
        _selectedTaskCategoryNames.add(categoryName);
        // If all task categories are now selected, check "All Tasks"
        if (_allTaskCategoriesSelected) {
          _allTasks = true;
        }
        // Note: _allTasks stays false when not all categories are selected (partial selection)
      }
    });
  }

  void _applyFilter() {
    // Ensure selected sets are populated when "All" checkboxes are checked
    // This prevents issues where allHabits/allTasks is true but selected sets are empty
    Set<String> habitNames = Set<String>.from(_selectedHabitCategoryNames);
    Set<String> taskNames = Set<String>.from(_selectedTaskCategoryNames);
    bool allHabitsFlag = _allHabits;
    bool allTasksFlag = _allTasks;

    if (_allHabits && habitNames.isEmpty) {
      // If "All Habits" is checked but set is empty, populate it with all habit categories
      habitNames = _habitCategories.map((cat) => cat.name).toSet();
    }

    if (_allTasks && taskNames.isEmpty) {
      // If "All Tasks" is checked but set is empty, populate it with all task categories
      taskNames = _taskCategories.map((cat) => cat.name).toSet();
    }

    // If sets are empty, clear the flags to ensure consistency
    // Filtering is based purely on selected category names, not on flags
    if (habitNames.isEmpty) {
      allHabitsFlag = false;
    }
    if (taskNames.isEmpty) {
      allTasksFlag = false;
    }

    final filter = QueueFilterState(
      allTasks: allTasksFlag,
      allHabits: allHabitsFlag,
      selectedHabitCategoryNames: habitNames,
      selectedTaskCategoryNames: taskNames,
    );
    Navigator.of(context).pop(filter);
  }

  void _clearFilter() {
    setState(() {
      // Reset to default state: all categories selected
      final allHabitNames = _habitCategories.map((cat) => cat.name).toSet();
      final allTaskNames = _taskCategories.map((cat) => cat.name).toSet();
      _allTasks = true;
      _allHabits = true;
      _selectedHabitCategoryNames = Set<String>.from(allHabitNames);
      _selectedTaskCategoryNames = Set<String>.from(allTaskNames);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.secondaryText.withOpacity(0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Filter Queue',
                    style: theme.titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilter,
                    child: Text(
                      'Clear',
                      style: TextStyle(color: theme.primary),
                    ),
                  ),
                ],
              ),
            ),
            // Content
            Flexible(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Habits section
                    if (_habitCategories.isNotEmpty) ...[
                      // Habits parent checkbox (tristate for partial selection)
                      CheckboxListTile(
                        title: Text(
                          'Habits',
                          style: theme.bodyMedium.override(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: _allHabitCategoriesSelected
                            ? true
                            : (_someHabitCategoriesSelected ? null : false),
                        tristate: true,
                        onChanged: _toggleAllHabits,
                        contentPadding: EdgeInsets.zero,
                      ),
                      // Habit categories (indented)
                      ..._habitCategories.map((category) {
                        final isSelected =
                            _selectedHabitCategoryNames.contains(category.name);
                        return Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: CheckboxListTile(
                            title: Text(
                              category.name,
                              style: theme.bodyMedium,
                            ),
                            value: isSelected,
                            onChanged: (_) =>
                                _toggleHabitCategory(category.name),
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(int.parse(
                                    category.color.replaceFirst('#', '0xFF'))),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 16),
                    ],
                    // Tasks section
                    if (_taskCategories.isNotEmpty) ...[
                      // Tasks parent checkbox (tristate for partial selection)
                      CheckboxListTile(
                        title: Text(
                          'Tasks',
                          style: theme.bodyMedium.override(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        value: _allTaskCategoriesSelected
                            ? true
                            : (_someTaskCategoriesSelected ? null : false),
                        tristate: true,
                        onChanged: _toggleAllTasks,
                        contentPadding: EdgeInsets.zero,
                      ),
                      // Task categories (indented)
                      ..._taskCategories.map((category) {
                        final isSelected =
                            _selectedTaskCategoryNames.contains(category.name);
                        return Padding(
                          padding: const EdgeInsets.only(left: 24),
                          child: CheckboxListTile(
                            title: Text(
                              category.name,
                              style: theme.bodyMedium,
                            ),
                            value: isSelected,
                            onChanged: (_) =>
                                _toggleTaskCategory(category.name),
                            contentPadding: EdgeInsets.zero,
                            secondary: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: Color(int.parse(
                                    category.color.replaceFirst('#', '0xFF'))),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        );
                      }),
                    ],
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
            // Action buttons
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: theme.surfaceBorderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(theme.buttonRadius),
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
                      onPressed: _applyFilter,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(theme.buttonRadius),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(color: Colors.white),
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
}

/// Helper function to show the filter dialog
Future<QueueFilterState?> showQueueFilterDialog({
  required BuildContext context,
  required List<CategoryRecord> categories,
  required QueueFilterState initialFilter,
}) async {
  return await showModalBottomSheet<QueueFilterState>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => QueueFilterDialog(
      categories: categories,
      initialFilter: initialFilter,
    ),
  );
}
