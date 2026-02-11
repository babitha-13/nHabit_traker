import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Queue/Queue_filter/queue_filter_state_manager.dart';

/// Business logic for queue filter state management
class QueueFilterLogic {
  /// Initialize filter state based on loaded categories and current filter
  static QueueFilterState initializeFilterState({
    required QueueFilterState currentFilter,
    required List<CategoryRecord> categories,
  }) {
    final habitCategories =
        categories.where((c) => c.categoryType == 'habit').toList();
    final taskCategories =
        categories.where((c) => c.categoryType == 'task').toList();
    final allHabitNames = habitCategories.map((cat) => cat.name).toSet();
    final allTaskNames = taskCategories.map((cat) => cat.name).toSet();

    // If no filter is set, initialize with all categories
    if (!currentFilter.hasAnyFilter) {
      return QueueFilterState(
        allTasks: true,
        allHabits: true,
        selectedHabitCategoryNames: allHabitNames,
        selectedTaskCategoryNames: allTaskNames,
      );
    }

    // If filter exists but category lists are empty, populate them
    var updatedFilter = currentFilter;
    if (currentFilter.allHabits &&
        currentFilter.selectedHabitCategoryNames.isEmpty &&
        habitCategories.isNotEmpty) {
      updatedFilter = QueueFilterState(
        allTasks: updatedFilter.allTasks,
        allHabits: updatedFilter.allHabits,
        selectedHabitCategoryNames: allHabitNames,
        selectedTaskCategoryNames: updatedFilter.selectedTaskCategoryNames,
      );
    }
    if (updatedFilter.allTasks &&
        updatedFilter.selectedTaskCategoryNames.isEmpty &&
        taskCategories.isNotEmpty) {
      updatedFilter = QueueFilterState(
        allTasks: updatedFilter.allTasks,
        allHabits: updatedFilter.allHabits,
        selectedHabitCategoryNames: updatedFilter.selectedHabitCategoryNames,
        selectedTaskCategoryNames: allTaskNames,
      );
    }

    return updatedFilter;
  }

  /// Determine if filter state should be saved or cleared
  static Future<void> handleFilterStateChange({
    required QueueFilterState newFilter,
    required List<CategoryRecord> categories,
  }) async {
    final habitCategories = categories
        .where((c) => c.categoryType == 'habit')
        .map((c) => c.name)
        .toSet();
    final taskCategories = categories
        .where((c) => c.categoryType == 'task')
        .map((c) => c.name)
        .toSet();

    final allHabitsSelected = habitCategories.isEmpty ||
        (habitCategories.length ==
                newFilter.selectedHabitCategoryNames.length &&
            habitCategories.every(
                (name) => newFilter.selectedHabitCategoryNames.contains(name)));
    final allTasksSelected = taskCategories.isEmpty ||
        (taskCategories.length == newFilter.selectedTaskCategoryNames.length &&
            taskCategories.every(
                (name) => newFilter.selectedTaskCategoryNames.contains(name)));

    if (allHabitsSelected && allTasksSelected) {
      // Default state - clear stored filter
      await QueueFilterStateManager().clearFilterState();
    } else {
      // Not default - save the filter state
      await QueueFilterStateManager().setFilterState(newFilter);
    }
  }
}
