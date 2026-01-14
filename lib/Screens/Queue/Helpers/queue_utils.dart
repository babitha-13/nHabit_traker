import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/time_utils.dart';
import 'package:habit_tracker/Screens/Habits/window_display_helper.dart';
import 'package:habit_tracker/Screens/Progress/Point_system_helper/points_service.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_sort_state_manager.dart';
import 'package:intl/intl.dart';
import 'package:collection/collection.dart';

/// Utility functions for queue page
class QueueUtils {
  /// Check if instance is due today or overdue
  static bool isTodayOrOverdue(ActivityInstanceRecord instance) {
    if (instance.dueDate == null) return true; // No due date = today
    final today = DateService.todayStart;
    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);
    // For habits: include if today is within the window [dueDate, windowEndDate]
    if (instance.templateCategoryType == 'habit') {
      final windowEnd = instance.windowEndDate;
      if (windowEnd != null) {
        // Today should be >= dueDate AND <= windowEnd
        final isWithinWindow = !today.isBefore(dueDate) &&
            !today.isAfter(
                DateTime(windowEnd.year, windowEnd.month, windowEnd.day));
        return isWithinWindow;
      }
      // Fallback to due date check if no window
      final isDueToday = dueDate.isAtSameMomentAs(today);
      return isDueToday;
    }
    // For tasks: only if due today or overdue
    final isTodayOrOverdue =
        dueDate.isAtSameMomentAs(today) || dueDate.isBefore(today);
    return isTodayOrOverdue;
  }

  /// Check if instance is completed
  static bool isInstanceCompleted(ActivityInstanceRecord instance) {
    return instance.status == 'completed' || instance.status == 'skipped';
  }

  /// Parse time string (HH:mm) to minutes since midnight
  /// Returns null if parsing fails
  static int? parseTimeToMinutes(String? timeStr) {
    if (timeStr == null) return null;
    final timeValues = timeStr.split(':');
    if (timeValues.length != 2) return null;
    final hour = int.tryParse(timeValues[0]);
    final minute = int.tryParse(timeValues[1]);
    if (hour == null || minute == null) return null;
    return hour * 60 + minute;
  }

  /// Compare two time strings (HH:mm format)
  /// Returns: -1 if timeA < timeB, 0 if equal, 1 if timeA > timeB
  /// Items without time are considered "larger" (go to end)
  static int compareTimes(String? timeA, String? timeB) {
    if (timeA == null && timeB == null) return 0;
    if (timeA == null) return 1; // A has no time, put it after B
    if (timeB == null) return -1; // B has no time, put it after A

    final timeAInt = parseTimeToMinutes(timeA);
    final timeBInt = parseTimeToMinutes(timeB);

    if (timeAInt == null && timeBInt == null) return 0;
    if (timeAInt == null) return 1;
    if (timeBInt == null) return -1;

    // Always ascending for time
    return timeAInt.compareTo(timeBInt);
  }

  /// Check if two filter states are equal
  static bool filtersEqual(QueueFilterState? a, QueueFilterState? b) {
    if (a == null || b == null) return a == b;
    return a.allTasks == b.allTasks &&
        a.allHabits == b.allHabits &&
        setsEqual(a.selectedHabitCategoryNames, b.selectedHabitCategoryNames) &&
        setsEqual(a.selectedTaskCategoryNames, b.selectedTaskCategoryNames);
  }

  /// Check if two sort states are equal
  static bool sortsEqual(QueueSortState? a, QueueSortState? b) {
    if (a == null || b == null) return a == b;
    return a.sortType == b.sortType;
  }

  /// Check if two sets are equal
  static bool setsEqual<T>(Set<T> a, Set<T> b) {
    if (a.length != b.length) return false;
    return a.every((item) => b.contains(item));
  }

  /// Get subtitle for an item based on bucket key
  static String getSubtitle(ActivityInstanceRecord item, String bucketKey) {
    if (bucketKey == 'Completed') {
      // For completed habits with completion windows, show next window info
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getNextWindowStartSubtitle(item);
      }
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      final subtitle =
          'Completed • ${item.templateCategoryName} • Due: $dueStr$timeStr';
      return subtitle;
    }
    if (bucketKey == 'Skipped/Snoozed') {
      // For skipped/snoozed habits with completion windows, show next window info
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getNextWindowStartSubtitle(item);
      }
      String statusText;
      // Check if item is snoozed first
      if (item.snoozedUntil != null &&
          DateTime.now().isBefore(item.snoozedUntil!)) {
        statusText = 'Snoozed';
      } else if (item.status == 'skipped') {
        statusText = 'Skipped';
      } else {
        statusText = 'Unknown';
      }
      final due = item.dueDate;
      final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      final subtitle =
          '$statusText • ${item.templateCategoryName} • Due: $dueStr$timeStr';
      return subtitle;
    }
    if (bucketKey == 'Pending') {
      // For habits with completion windows, show when window ends
      if (item.templateCategoryType == 'habit' &&
          WindowDisplayHelper.hasCompletionWindow(item)) {
        return WindowDisplayHelper.getWindowEndSubtitle(item);
      }
      // Show category name + due time if available
      String subtitle = item.templateCategoryName;
      if (item.hasDueTime()) {
        subtitle += ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}';
      }
      return subtitle;
    }
    final dueDate = item.dueDate;
    if (dueDate != null) {
      final formattedDate = DateFormat.MMMd().format(dueDate);
      final timeStr = item.hasDueTime()
          ? ' @ ${TimeUtils.formatTimeForDisplay(item.dueTime)}'
          : '';
      return '$formattedDate$timeStr • ${item.templateCategoryName}';
    }
    return item.templateCategoryName;
  }

  /// Get today's date
  static DateTime todayDate() {
    return DateService.todayStart;
  }

  /// Check if two dates are the same day
  static bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  /// Get category color for an instance
  static String getCategoryColor(
      ActivityInstanceRecord instance, List<CategoryRecord> categories) {
    final category = categories
        .firstWhereOrNull((c) => c.name == instance.templateCategoryName);
    return category?.color ?? '#000000';
  }

  /// Get sort points for an instance
  static double getSortPointsForInstance(ActivityInstanceRecord instance) {
    final points = PointsService.calculateDailyTarget(instance);
    if (points > 0) {
      return points;
    }
    return instance.templatePriority.toDouble();
  }

  /// Check if filter is in default state (all categories selected)
  static bool isDefaultFilterState(
      QueueFilterState currentFilter, List<CategoryRecord> categories) {
    if (categories.isEmpty) return true; // No categories = default state

    final habitCategories = categories
        .where((c) => c.categoryType == 'habit')
        .map((c) => c.name)
        .toSet();
    final taskCategories = categories
        .where((c) => c.categoryType == 'task')
        .map((c) => c.name)
        .toSet();

    // Check if all habit categories are selected
    final allHabitsSelected = habitCategories.isEmpty ||
        (habitCategories.length ==
                currentFilter.selectedHabitCategoryNames.length &&
            habitCategories.every((name) =>
                currentFilter.selectedHabitCategoryNames.contains(name)));

    // Check if all task categories are selected
    final allTasksSelected = taskCategories.isEmpty ||
        (taskCategories.length ==
                currentFilter.selectedTaskCategoryNames.length &&
            taskCategories.every((name) =>
                currentFilter.selectedTaskCategoryNames.contains(name)));

    return allHabitsSelected && allTasksSelected;
  }

  /// Count the number of excluded categories (not selected)
  static int getExcludedCategoryCount(
      QueueFilterState currentFilter, List<CategoryRecord> categories) {
    if (categories.isEmpty) return 0;

    final habitCategories = categories
        .where((c) => c.categoryType == 'habit')
        .map((c) => c.name)
        .toSet();
    final taskCategories = categories
        .where((c) => c.categoryType == 'task')
        .map((c) => c.name)
        .toSet();

    final excludedHabits = habitCategories.length -
        currentFilter.selectedHabitCategoryNames.length;
    final excludedTasks =
        taskCategories.length - currentFilter.selectedTaskCategoryNames.length;

    return excludedHabits + excludedTasks;
  }

  /// Apply filter logic to instances
  static List<ActivityInstanceRecord> applyFilters(
      List<ActivityInstanceRecord> instances,
      QueueFilterState currentFilter,
      bool isDefaultFilterState) {
    // If in default state (all categories selected), show all items (no filtering)
    if (isDefaultFilterState) {
      return instances;
    }

    // Check if any categories are actually selected
    final hasSelectedHabits =
        currentFilter.selectedHabitCategoryNames.isNotEmpty;
    final hasSelectedTasks = currentFilter.selectedTaskCategoryNames.isNotEmpty;

    // If filter was applied but no categories are selected, show nothing
    // (This handles the case where user explicitly unchecks everything)
    if (!hasSelectedHabits && !hasSelectedTasks) {
      return []; // Nothing selected, show nothing
    }

    // Filter based ONLY on which sub-items (categories) are checked
    // "All Habits" and "All Tasks" checkboxes only control checking/unchecking of sub-items,
    // they don't directly affect filtering - filtering is purely based on selected category names
    return instances.where((instance) {
      // Skip instances with empty category name (shouldn't happen, but safety check)
      if (instance.templateCategoryName.isEmpty) {
        return false;
      }
      // Check habits
      if (instance.templateCategoryType == 'habit' &&
          hasSelectedHabits &&
          currentFilter.selectedHabitCategoryNames
              .contains(instance.templateCategoryName)) {
        return true;
      }
      // Check tasks
      if (instance.templateCategoryType == 'task' &&
          hasSelectedTasks &&
          currentFilter.selectedTaskCategoryNames
              .contains(instance.templateCategoryName)) {
        return true;
      }
      return false;
    }).toList();
  }

  /// Sort items within a section based on sort state
  static List<ActivityInstanceRecord> sortSectionItems(
      List<ActivityInstanceRecord> items,
      String sectionKey,
      Set<String> expandedSections,
      QueueSortState currentSort,
      List<CategoryRecord> categories) {
    // Only sort expanded sections
    if (!expandedSections.contains(sectionKey) || !currentSort.isActive) {
      return items;
    }

    final sortedItems = List<ActivityInstanceRecord>.from(items);

    if (currentSort.sortType == QueueSortType.points) {
      // Sort by daily target points (with priority fallback) - descending
      sortedItems.sort((a, b) {
        final pointsA = getSortPointsForInstance(a);
        final pointsB = getSortPointsForInstance(b);

        final comparison = pointsB.compareTo(pointsA);
        if (comparison != 0) {
          return comparison;
        }
        // Stable fallback: alphabetical by name
        return a.templateName.toLowerCase().compareTo(
              b.templateName.toLowerCase(),
            );
      });
    } else if (currentSort.sortType == QueueSortType.time) {
      // Sort by time only - date-agnostic, always ascending (earliest time first)
      sortedItems.sort((a, b) {
        final timeA = a.dueTime;
        final timeB = b.dueTime;

        // Items with time come first, sorted by time
        // Items without time go to the end
        if (timeA == null && timeB == null) return 0;
        if (timeA == null) return 1; // A has no time, put it after B
        if (timeB == null) return -1; // B has no time, put it after A

        // Both have time - parse and compare
        final timeAInt = parseTimeToMinutes(timeA);
        final timeBInt = parseTimeToMinutes(timeB);

        if (timeAInt == null && timeBInt == null) return 0;
        if (timeAInt == null) return 1;
        if (timeBInt == null) return -1;

        // Always ascending for time
        return timeAInt.compareTo(timeBInt);
      });
    } else if (currentSort.sortType == QueueSortType.urgency) {
      // Sort by urgency - date (deadline) then time, always ascending (most urgent first)
      sortedItems.sort((a, b) {
        // For habits with windows, use windowEndDate (deadline)
        // For tasks and habits without windows, use dueDate
        DateTime? dateA;
        DateTime? dateB;

        if (WindowDisplayHelper.hasCompletionWindow(a)) {
          dateA = a.windowEndDate;
        } else {
          dateA = a.dueDate;
        }

        if (WindowDisplayHelper.hasCompletionWindow(b)) {
          dateB = b.windowEndDate;
        } else {
          dateB = b.dueDate;
        }

        // Handle null dates (put them at the end)
        if (dateA == null && dateB == null) {
          // Both have no date, compare by time
          return compareTimes(a.dueTime, b.dueTime);
        }
        if (dateA == null) return 1; // A has no date, put it after B
        if (dateB == null) return -1; // B has no date, put it after A

        // Compare dates - always ascending (earliest deadline first)
        int dateComparison = dateA.compareTo(dateB);
        if (dateComparison != 0) {
          return dateComparison;
        }

        // If dates are equal, compare times
        return compareTimes(a.dueTime, b.dueTime);
      });
    }

    return sortedItems;
  }
}
