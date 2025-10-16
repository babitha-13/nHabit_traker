import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent expansion state for collapsible sections across pages
/// Implements accordion behavior where only one section can be expanded at a time
class ExpansionStateManager {
  static final ExpansionStateManager _instance =
      ExpansionStateManager._internal();
  factory ExpansionStateManager() => _instance;
  ExpansionStateManager._internal();

  // State keys for each page
  static const String _habitsKey = 'habits_expanded_section';
  static const String _queueKey = 'queue_expanded_section';
  static const String _taskKey = 'task_expanded_section';
  static const String _weeklyKey = 'weekly_expanded_section';

  /// Get the currently expanded section for Habits page
  /// Returns null if no section is expanded (all collapsed)
  Future<String?> getHabitsExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_habitsKey);
  }

  /// Set the expanded section for Habits page
  /// Pass null to collapse all sections
  Future<void> setHabitsExpandedSection(String? sectionName) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionName == null) {
      await prefs.remove(_habitsKey);
    } else {
      await prefs.setString(_habitsKey, sectionName);
    }
  }

  /// Get the currently expanded section for Queue page
  /// Returns "Today" as default if no saved state
  Future<String?> getQueueExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_queueKey) ?? 'Today';
  }

  /// Set the expanded section for Queue page
  /// Prevents collapsing "Today" section
  Future<void> setQueueExpandedSection(String? sectionName) async {
    // Always keep "Today" expanded for Queue page
    if (sectionName == null || sectionName.isEmpty) {
      sectionName = 'Today';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_queueKey, sectionName);
  }

  /// Get the currently expanded section for Task page
  /// Returns "Today" as default if no saved state
  Future<String?> getTaskExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_taskKey) ?? 'Today';
  }

  /// Set the expanded section for Task page
  /// Prevents collapsing "Today" section
  Future<void> setTaskExpandedSection(String? sectionName) async {
    // Always keep "Today" expanded for Task page
    if (sectionName == null || sectionName.isEmpty) {
      sectionName = 'Today';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_taskKey, sectionName);
  }

  /// Get the currently expanded section for Weekly view
  /// Returns null if no section is expanded (all collapsed)
  Future<String?> getWeeklyExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_weeklyKey);
  }

  /// Set the expanded section for Weekly view
  /// Pass null to collapse all sections
  Future<void> setWeeklyExpandedSection(String? sectionName) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionName == null) {
      await prefs.remove(_weeklyKey);
    } else {
      await prefs.setString(_weeklyKey, sectionName);
    }
  }

  /// Clear all expansion states (useful for testing or reset)
  Future<void> clearAllStates() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_habitsKey);
    await prefs.remove(_queueKey);
    await prefs.remove(_taskKey);
    await prefs.remove(_weeklyKey);
  }
}
