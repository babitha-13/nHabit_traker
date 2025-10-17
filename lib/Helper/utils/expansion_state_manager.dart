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

  // App session tracking
  static const String _appSessionKey = 'app_session_id';
  static const String _lastSessionKey = 'last_app_session_id';

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

  /// Set the expanded section for Queue page
  /// Allows collapsing "Pending" section but defaults to "Pending" on new sessions
  Future<void> setQueueExpandedSection(String? sectionName) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionName == null) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setString(_queueKey, sectionName);
    }
  }

  /// Set the expanded section for Task page
  /// Allows collapsing "Today" section but defaults to "Today" on new sessions
  Future<void> setTaskExpandedSection(String? sectionName) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionName == null) {
      await prefs.remove(_taskKey);
    } else {
      await prefs.setString(_taskKey, sectionName);
    }
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

  /// Check if this is a new app session (app restart)
  Future<bool> isNewAppSession() async {
    final prefs = await SharedPreferences.getInstance();
    final currentSession = prefs.getString(_appSessionKey);
    final lastSession = prefs.getString(_lastSessionKey);

    if (currentSession == null || lastSession == null) {
      // First time or no previous session
      await _initializeAppSession();
      return true;
    }

    if (currentSession != lastSession) {
      // New session detected
      await prefs.setString(_lastSessionKey, currentSession);
      return true;
    }

    return false;
  }

  /// Initialize app session
  Future<void> _initializeAppSession() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    await prefs.setString(_appSessionKey, sessionId);
    await prefs.setString(_lastSessionKey, sessionId);
  }

  /// Get the currently expanded section for Queue page
  /// Returns "Pending" as default if no saved state or new app session
  Future<String?> getQueueExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();

    if (isNewSession) {
      // New app session - return default
      return 'Pending';
    }

    return prefs.getString(_queueKey) ?? 'Pending';
  }

  /// Get the currently expanded section for Task page
  /// Returns "Today" as default if no saved state or new app session
  Future<String?> getTaskExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();

    if (isNewSession) {
      // New app session - return default
      return 'Today';
    }

    return prefs.getString(_taskKey) ?? 'Today';
  }

  /// Get the currently expanded section for Habits page
  /// Returns first category as default if no saved state or new app session
  Future<String?> getHabitsExpandedSection() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();

    if (isNewSession) {
      // New app session - return null (will be handled by page logic)
      return null;
    }

    return prefs.getString(_habitsKey);
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
