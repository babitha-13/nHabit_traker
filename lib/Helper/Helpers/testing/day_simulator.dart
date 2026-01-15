import 'dart:async';
import 'package:habit_tracker/Screens/CatchUp/day_end_processor.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Day Simulator for testing day-end processing and time progression
/// Allows you to simulate multiple days of habit/task completion
class DaySimulator {
  static DateTime _simulatedDate = DateTime.now();
  static bool _isSimulationMode = false;
  static Timer? _simulationTimer;

  /// Get the current simulated date
  static DateTime get simulatedDate => _simulatedDate;

  /// Check if we're in simulation mode
  static bool get isSimulationMode => _isSimulationMode;

  /// Start simulation mode with a specific date
  static void startSimulation({DateTime? startDate}) {
    _simulatedDate = startDate ?? DateTime.now();
    _isSimulationMode = true;
  }

  /// Stop simulation mode and return to real time
  static void stopSimulation() {
    _isSimulationMode = false;
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }

  /// Fast forward to the next day and trigger day-end processing
  static Future<void> advanceToNextDay() async {
    if (!_isSimulationMode) {
      throw Exception('Not in simulation mode. Call startSimulation() first.');
    }
    final currentUser = currentUserUid;
    if (currentUser.isEmpty) {
      throw Exception('No authenticated user');
    }

    // Process day-end for current simulated date
    await DayEndProcessor.processDayEnd(
      userId: currentUser,
      targetDate: _simulatedDate,
    );
    // Advance to next day
    _simulatedDate = _simulatedDate.add(const Duration(days: 1));
    // Generate new instances for the new day
    await _generateNewInstancesForDay(currentUser, _simulatedDate);
  }

  /// Fast forward multiple days at once
  static Future<void> advanceDays(int days) async {
    for (int i = 0; i < days; i++) {
      await advanceToNextDay();
    }
  }

  /// Simulate a complete day with various completion scenarios
  static Future<void> simulateDay({
    required String userId,
    required DateTime date,
    List<DaySimulationScenario> scenarios = const [],
  }) async {
    // Get all habit instances for this day
    final habitInstances =
        await ActivityInstanceRecord.collectionForUser(userId)
            .where('templateCategoryType', isEqualTo: 'habit')
            .where('belongsToDate', isEqualTo: date)
            .where('dayState', isEqualTo: 'open')
            .get()
            .then((snapshot) => snapshot.docs
                .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
                .toList());
    // Apply scenarios
    for (final scenario in scenarios) {
      await _applyScenario(habitInstances, scenario);
    }
    // Process day-end
    await DayEndProcessor.processDayEnd(userId: userId, targetDate: date);
  }

  /// Apply a specific scenario to habit instances
  static Future<void> _applyScenario(
    List<ActivityInstanceRecord> instances,
    DaySimulationScenario scenario,
  ) async {
    for (final instance in instances) {
      if (scenario.shouldApply(instance)) {
        await _applyScenarioToInstance(instance, scenario);
      }
    }
  }

  /// Apply scenario to a specific instance
  static Future<void> _applyScenarioToInstance(
    ActivityInstanceRecord instance,
    DaySimulationScenario scenario,
  ) async {
    final updates = <String, dynamic>{};
    switch (scenario.type) {
      case ScenarioType.complete:
        updates['status'] = 'completed';
        updates['currentValue'] = 1; // Simplified for testing
        break;
      case ScenarioType.partial:
        final target = 1; // Simplified for testing
        final partialValue = (target * scenario.partialPercentage).round();
        updates['status'] = 'pending';
        updates['currentValue'] = partialValue;
        break;
      case ScenarioType.skip:
        updates['status'] = 'skipped';
        updates['currentValue'] = 0;
        break;
      case ScenarioType.noChange:
        // Keep as is
        break;
    }
    if (updates.isNotEmpty) {
      updates['lastUpdated'] = DateTime.now();
      await instance.reference.update(updates);
    }
  }

  /// Generate new instances for a specific day
  static Future<void> _generateNewInstancesForDay(
      String userId, DateTime date) async {
    // This would typically be handled by your instance generation service
    // For now, we'll just log that it should happen
  }

  /// Get simulation status
  static Map<String, dynamic> getStatus() {
    return {
      'isSimulationMode': _isSimulationMode,
      'simulatedDate': _simulatedDate.toIso8601String(),
      'realDate': DateTime.now().toIso8601String(),
    };
  }

  /// Reset simulation to current real date
  static void resetToRealTime() {
    _simulatedDate = DateTime.now();
    _isSimulationMode = false;
    _simulationTimer?.cancel();
    _simulationTimer = null;
  }
}

/// Scenario for simulating different completion patterns
class DaySimulationScenario {
  final ScenarioType type;
  final double partialPercentage; // 0.0 to 1.0 for partial completion
  final String? habitNameFilter; // Apply only to habits with this name
  final String? categoryFilter; // Apply only to habits in this category
  final int? maxInstances; // Apply to max N instances
  const DaySimulationScenario({
    required this.type,
    this.partialPercentage = 0.5,
    this.habitNameFilter,
    this.categoryFilter,
    this.maxInstances,
  });

  /// Check if this scenario should apply to the given instance
  bool shouldApply(ActivityInstanceRecord instance) {
    if (habitNameFilter != null &&
        !instance.templateName.contains(habitNameFilter!)) {
      return false;
    }
    if (categoryFilter != null &&
        instance.templateCategoryName != categoryFilter) {
      return false;
    }
    return true;
  }
}

/// Types of completion scenarios
enum ScenarioType {
  complete, // Fully complete the habit
  partial, // Partially complete (e.g., 6/8 glasses)
  skip, // Skip the habit entirely
  noChange, // Leave as is (pending)
}

/// Predefined scenario sets for common testing patterns
class SimulationScenarios {
  /// Perfect day - all habits completed
  static const List<DaySimulationScenario> perfectDay = [
    DaySimulationScenario(type: ScenarioType.complete),
  ];

  /// Good day - most habits completed, some partial
  static const List<DaySimulationScenario> goodDay = [
    DaySimulationScenario(type: ScenarioType.complete, maxInstances: 3),
    DaySimulationScenario(
        type: ScenarioType.partial, partialPercentage: 0.7, maxInstances: 2),
  ];

  /// Mixed day - some completed, some partial, some skipped
  static const List<DaySimulationScenario> mixedDay = [
    DaySimulationScenario(type: ScenarioType.complete, maxInstances: 2),
    DaySimulationScenario(
        type: ScenarioType.partial, partialPercentage: 0.6, maxInstances: 2),
    DaySimulationScenario(type: ScenarioType.skip, maxInstances: 1),
  ];

  /// Bad day - mostly skipped or partial
  static const List<DaySimulationScenario> badDay = [
    DaySimulationScenario(
        type: ScenarioType.partial, partialPercentage: 0.3, maxInstances: 3),
    DaySimulationScenario(type: ScenarioType.skip, maxInstances: 2),
  ];

  /// Lazy day - everything skipped
  static const List<DaySimulationScenario> lazyDay = [
    DaySimulationScenario(type: ScenarioType.skip),
  ];
}

/// Testing utilities for the day simulator
class DaySimulatorTesting {
  /// Run a complete week simulation with different daily patterns
  static Future<void> simulateWeek({
    required String userId,
    DateTime? startDate,
  }) async {
    final start = startDate ?? DateTime.now().subtract(const Duration(days: 7));
    // Day 1: Perfect day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start,
      scenarios: SimulationScenarios.perfectDay,
    );
    // Day 2: Good day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 1)),
      scenarios: SimulationScenarios.goodDay,
    );
    // Day 3: Mixed day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 2)),
      scenarios: SimulationScenarios.mixedDay,
    );
    // Day 4: Bad day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 3)),
      scenarios: SimulationScenarios.badDay,
    );
    // Day 5: Lazy day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 4)),
      scenarios: SimulationScenarios.lazyDay,
    );
    // Day 6: Good day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 5)),
      scenarios: SimulationScenarios.goodDay,
    );
    // Day 7: Perfect day
    await DaySimulator.simulateDay(
      userId: userId,
      date: start.add(const Duration(days: 6)),
      scenarios: SimulationScenarios.perfectDay,
    );
  }

  /// Test day-end processing with various scenarios
  static Future<void> testDayEndScenarios({
    required String userId,
    DateTime? testDate,
  }) async {
    final date = testDate ?? DateTime.now().subtract(const Duration(days: 1));
    // Test 1: Perfect completion
    await DaySimulator.simulateDay(
      userId: userId,
      date: date,
      scenarios: SimulationScenarios.perfectDay,
    );
    // Test 2: Partial completion
    await DaySimulator.simulateDay(
      userId: userId,
      date: date.add(const Duration(days: 1)),
      scenarios: SimulationScenarios.mixedDay,
    );
    // Test 3: All skipped
    await DaySimulator.simulateDay(
      userId: userId,
      date: date.add(const Duration(days: 2)),
      scenarios: SimulationScenarios.lazyDay,
    );
  }

  /// Get progress data for analysis
  static Future<Map<String, dynamic>> getProgressAnalysis({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final progressRecords = await DailyProgressRecord.collectionForUser(userId)
        .where('date', isGreaterThanOrEqualTo: startDate)
        .where('date', isLessThanOrEqualTo: endDate)
        .orderBy('date')
        .get()
        .then((snapshot) => snapshot.docs
            .map((doc) => DailyProgressRecord.fromSnapshot(doc))
            .toList());
    if (progressRecords.isEmpty) {
      return {'error': 'No progress data found'};
    }
    final totalDays = progressRecords.length;
    final totalTarget =
        progressRecords.fold(0.0, (sum, record) => sum + record.targetPoints);
    final totalEarned =
        progressRecords.fold(0.0, (sum, record) => sum + record.earnedPoints);
    final averagePercentage = progressRecords.fold(
            0.0, (sum, record) => sum + record.completionPercentage) /
        totalDays;
    final perfectDays =
        progressRecords.where((r) => r.completionPercentage >= 100).length;
    final goodDays =
        progressRecords.where((r) => r.completionPercentage >= 70).length;
    final badDays =
        progressRecords.where((r) => r.completionPercentage < 50).length;
    return {
      'totalDays': totalDays,
      'totalTarget': totalTarget,
      'totalEarned': totalEarned,
      'averagePercentage': averagePercentage,
      'perfectDays': perfectDays,
      'goodDays': goodDays,
      'badDays': badDays,
      'dailyBreakdown': progressRecords
          .map((r) => {
                'date': r.date?.toIso8601String(),
                'percentage': r.completionPercentage,
                'target': r.targetPoints,
                'earned': r.earnedPoints,
                'habitsCompleted': r.completedHabits,
                'totalHabits': r.totalHabits,
              })
          .toList(),
    };
  }
}
