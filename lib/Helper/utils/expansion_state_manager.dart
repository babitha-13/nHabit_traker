import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Manages persistent expansion state for collapsible sections across pages
/// Supports multiple sections being expanded independently
class ExpansionStateManager {
  static final ExpansionStateManager _instance =
      ExpansionStateManager._internal();
  factory ExpansionStateManager() => _instance;
  ExpansionStateManager._internal();
  
  // State keys for each page
  static const String _habitsKey = 'habits_expanded_sections';
  static const String _queueKey = 'queue_expanded_sections';
  static const String _taskKey = 'task_expanded_sections';
  static const String _weeklyKey = 'weekly_expanded_sections';
  
  // App session tracking
  static const String _appSessionKey = 'app_session_id';
  static const String _lastSessionKey = 'last_app_session_id';
  
  /// Set the expanded sections for Habits page
  Future<void> setHabitsExpandedSections(Set<String> sectionNames) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionNames.isEmpty) {
      await prefs.remove(_habitsKey);
    } else {
      await prefs.setString(_habitsKey, jsonEncode(sectionNames.toList()));
    }
  }
  
  /// Set the expanded sections for Queue page
  Future<void> setQueueExpandedSections(Set<String> sectionNames) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionNames.isEmpty) {
      await prefs.remove(_queueKey);
    } else {
      await prefs.setString(_queueKey, jsonEncode(sectionNames.toList()));
    }
  }
  
  /// Set the expanded sections for Task page
  Future<void> setTaskExpandedSections(Set<String> sectionNames) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionNames.isEmpty) {
      await prefs.remove(_taskKey);
    } else {
      await prefs.setString(_taskKey, jsonEncode(sectionNames.toList()));
    }
  }
  
  /// Get the currently expanded sections for Weekly view
  /// Returns empty set if no sections are expanded
  Future<Set<String>> getWeeklyExpandedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final storedValue = prefs.getString(_weeklyKey);
    if (storedValue == null) {
      return {};
    }
    try {
      final List<dynamic> decoded = jsonDecode(storedValue);
      return decoded.cast<String>().toSet();
    } catch (e) {
      return {};
    }
  }
  
  /// Set the expanded sections for Weekly view
  Future<void> setWeeklyExpandedSections(Set<String> sectionNames) async {
    final prefs = await SharedPreferences.getInstance();
    if (sectionNames.isEmpty) {
      await prefs.remove(_weeklyKey);
    } else {
      await prefs.setString(_weeklyKey, jsonEncode(sectionNames.toList()));
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
  
  /// Get the currently expanded sections for Queue page
  /// Returns default sections if no saved state or new app session
  Future<Set<String>> getQueueExpandedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();
    
    if (isNewSession) {
      // New app session - return default (empty or specific sections as needed)
      return {};
    }
    
    final storedValue = prefs.getString(_queueKey);
    if (storedValue == null) {
      return {};
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(storedValue);
      return decoded.cast<String>().toSet();
    } catch (e) {
      return {};
    }
  }
  
  /// Get the currently expanded sections for Task page
  /// Returns {"Overdue", "Today"} as default on new app session
  Future<Set<String>> getTaskExpandedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();
    
    if (isNewSession) {
      // New app session - return Overdue and Today as default
      return {'Overdue', 'Today'};
    }
    
    final storedValue = prefs.getString(_taskKey);
    if (storedValue == null) {
      // No saved state - use defaults
      return {'Overdue', 'Today'};
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(storedValue);
      return decoded.cast<String>().toSet();
    } catch (e) {
      return {'Overdue', 'Today'};
    }
  }
  
  /// Get the currently expanded sections for Habits page
  /// Returns empty set on new app session (will be handled by page logic)
  Future<Set<String>> getHabitsExpandedSections() async {
    final prefs = await SharedPreferences.getInstance();
    final isNewSession = await isNewAppSession();
    
    if (isNewSession) {
      // New app session - return empty (will be handled by page logic)
      return {};
    }
    
    final storedValue = prefs.getString(_habitsKey);
    if (storedValue == null) {
      return {};
    }
    
    try {
      final List<dynamic> decoded = jsonDecode(storedValue);
      return decoded.cast<String>().toSet();
    } catch (e) {
      return {};
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
