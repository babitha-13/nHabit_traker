import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Filter state data class
class QueueFilterState {
  final bool allTasks;
  final bool allHabits;
  final Set<String> selectedHabitCategoryNames;
  final Set<String> selectedTaskCategoryNames;

  QueueFilterState({
    this.allTasks = false,
    this.allHabits = false,
    this.selectedHabitCategoryNames = const {},
    this.selectedTaskCategoryNames = const {},
  });

  bool get hasAnyFilter {
    return allTasks ||
        allHabits ||
        selectedHabitCategoryNames.isNotEmpty ||
        selectedTaskCategoryNames.isNotEmpty;
  }

  Map<String, dynamic> toJson() {
    return {
      'allTasks': allTasks,
      'allHabits': allHabits,
      'selectedHabitCategoryNames': selectedHabitCategoryNames.toList(),
      'selectedTaskCategoryNames': selectedTaskCategoryNames.toList(),
    };
  }

  factory QueueFilterState.fromJson(Map<String, dynamic> json) {
    return QueueFilterState(
      allTasks: json['allTasks'] as bool? ?? false,
      allHabits: json['allHabits'] as bool? ?? false,
      selectedHabitCategoryNames: (json['selectedHabitCategoryNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          {},
      selectedTaskCategoryNames: (json['selectedTaskCategoryNames'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toSet() ??
          {},
    );
  }
}

/// Manages persistent filter state for the queue page
/// Stores filter selections: allTasks, allHabits, and specific category names
class QueueFilterStateManager {
  static final QueueFilterStateManager _instance =
      QueueFilterStateManager._internal();
  factory QueueFilterStateManager() => _instance;
  QueueFilterStateManager._internal();

  static const String _filterKey = 'queue_filter_state';

  /// Get the current filter state
  Future<QueueFilterState> getFilterState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_filterKey);
    if (storedValue == null) {
      return QueueFilterState(); // Default: no filters
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(storedValue);
      return QueueFilterState.fromJson(decoded);
    } catch (e) {
      return QueueFilterState(); // Return default on error
    }
  }

  /// Set the filter state
  Future<void> setFilterState(QueueFilterState state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!state.hasAnyFilter) {
      // Clear filter if nothing is selected
      await prefs.remove(_filterKey);
    } else {
      await prefs.setString(_filterKey, jsonEncode(state.toJson()));
    }
  }

  /// Clear the filter state
  Future<void> clearFilterState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_filterKey);
  }
}

