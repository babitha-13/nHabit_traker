import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Sort type enum constants
class QueueSortType {
  static const String none = 'none';
  static const String points = 'points';
  static const String time = 'time';
  static const String urgency = 'urgency';
  // Legacy support for old 'dueDate' type (maps to 'urgency')
  static const String dueDate = 'urgency';
}

/// Sort direction enum constants
class QueueSortDirection {
  static const String asc = 'asc';
  static const String desc = 'desc';
}

/// Sort state data class
class QueueSortState {
  final String sortType; // 'none', 'points', 'time', 'urgency'
  final String sortDirection; // 'asc', 'desc'

  QueueSortState({
    String? sortType,
    String? sortDirection,
  })  : sortType = sortType ?? QueueSortType.none,
        sortDirection = _getDefaultDirection(
          sortType ?? QueueSortType.none,
          sortDirection,
        );

  /// Get the default direction based on sort type
  /// Points: always descending, Time and Urgency: always ascending
  static String _getDefaultDirection(String sortType, String? providedDirection) {
    if (sortType == QueueSortType.points) {
      return QueueSortDirection.desc;
    } else if (sortType == QueueSortType.time || sortType == QueueSortType.urgency) {
      return QueueSortDirection.asc;
    }
    // Legacy support: map old 'dueDate' to 'urgency' direction
    if (sortType == 'dueDate') {
      return QueueSortDirection.asc;
    }
    // For 'none' or unknown types, use provided direction or default to desc
    return providedDirection ?? QueueSortDirection.desc;
  }

  bool get isActive => sortType != QueueSortType.none;

  Map<String, dynamic> toJson() {
    return {
      'sortType': sortType,
      'sortDirection': sortDirection,
    };
  }

  factory QueueSortState.fromJson(Map<String, dynamic> json) {
    String? sortType = json['sortType'] as String? ?? QueueSortType.none;
    // Migrate old 'dueDate' to 'urgency' for backward compatibility
    if (sortType == 'dueDate') {
      sortType = QueueSortType.urgency;
    }
    final providedDirection = json['sortDirection'] as String?;
    return QueueSortState(
      sortType: sortType,
      sortDirection: providedDirection,
    );
  }
}

/// Manages persistent sort state for the queue page
/// Stores sort type and direction preferences
class QueueSortStateManager {
  static final QueueSortStateManager _instance =
      QueueSortStateManager._internal();
  factory QueueSortStateManager() => _instance;
  QueueSortStateManager._internal();

  static const String _sortKey = 'queue_sort_state';

  /// Get the current sort state
  Future<QueueSortState> getSortState() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_sortKey);
    if (storedValue == null) {
      return QueueSortState(); // Default: no sort
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(storedValue);
      return QueueSortState.fromJson(decoded);
    } catch (e) {
      return QueueSortState(); // Return default on error
    }
  }

  // Expose sort type constants for convenience
  static String get sortTypeNone => QueueSortType.none;
  static String get sortTypePoints => QueueSortType.points;
  static String get sortTypeTime => QueueSortType.time;
  static String get sortTypeUrgency => QueueSortType.urgency;
  static String get sortDirectionAsc => QueueSortDirection.asc;
  static String get sortDirectionDesc => QueueSortDirection.desc;

  /// Set the sort state
  Future<void> setSortState(QueueSortState state) async {
    final prefs = await SharedPreferences.getInstance();
    if (!state.isActive) {
      // Clear sort if none selected
      await prefs.remove(_sortKey);
    } else {
      await prefs.setString(_sortKey, jsonEncode(state.toJson()));
    }
  }

  /// Clear the sort state
  Future<void> clearSortState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sortKey);
  }
}

