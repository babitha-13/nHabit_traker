Enhanced Incremental Progress Calculation
Problem
The current incremental calculation only handles basic instance updates (create/update/delete). It doesn't detect changes that affect points:
•	Priority changes (affects target and earned points)
•	Due date changes (affects task target - moves in/out of "due" status)
•	Skip/reschedule actions (removes task from day's calculation)
•	Template changes (priority, frequency, duration affect target)
•	Time bonus toggle (affects earned points for time-based items)
•	Window logic changes (habits appear/disappear based on window state)
Solution
Enhance _calculateProgressIncremental() to detect what changed and recalculate accordingly. The method should:
1.	Compare old vs new instance to detect changes
2.	Recalculate contribution based on detected changes
3.	Handle edge cases (window logic, due date, time bonus)
Implementation
File: lib/Screens/Queue/queue_page.dart
1. Enhance _calculateProgressIncremental() to detect changes
Add change detection logic before calculating contributions:
Future<void> _calculateProgressIncremental({
  required ActivityInstanceRecord? oldInstance,
  required ActivityInstanceRecord? newInstance,
}) async {
  // ... existing guard logic ...
  
  // Detect what changed
  bool needsFullRecalculation = false;
  bool targetChanged = false;
  bool earnedChanged = false;
  bool isActiveChanged = false;
  
  if (oldInstance != null && newInstance != null) {
    // Priority change affects both target and earned
    if (oldInstance.templatePriority != newInstance.templatePriority) {
      targetChanged = true;
      earnedChanged = true;
    }
    
    // Due date change (for tasks) - affects isActive status
    if (oldInstance.dueDate != newInstance.dueDate) {
      isActiveChanged = true;
      targetChanged = true; // Task may move in/out of "due" status
    }
    
    // Status change affects earned points
    if (oldInstance.status != newInstance.status) {
      earnedChanged = true;
      // Skip/reschedule: status becomes "skipped" or due date moved
      if (newInstance.status == 'skipped' || 
          (oldInstance.dueDate != null && newInstance.dueDate != null &&
           !_isTaskDueToday(newInstance))) {
        targetChanged = true; // Task no longer counts toward target
      }
    }
    
    // Window state change (for habits) - affects target
    if (oldInstance.templateCategoryType == 'habit') {
      final oldInWindow = _isWithinWindow(oldInstance, DateService.currentDate);
      final newInWindow = _isWithinWindow(newInstance, DateService.currentDate);
      if (oldInWindow != newInWindow) {
        targetChanged = true;
        earnedChanged = true; // May affect earned if item appears/disappears
      }
    }
    
    // Time logged change (for time-based) - affects earned (time bonus)
    if (oldInstance.templateTrackingType == 'time' &&
        (oldInstance.accumulatedTime != newInstance.accumulatedTime ||
         oldInstance.totalTimeLogged != newInstance.totalTimeLogged)) {
      earnedChanged = true;
    }
    
    // Current value change (for quantitative) - affects earned
    if (oldInstance.currentValue != newInstance.currentValue) {
      earnedChanged = true;
    }
    
    // Template ID change - full recalculation needed
    if (oldInstance.templateId != newInstance.templateId) {
      needsFullRecalculation = true;
    }
  }
  
  // If template changed, fall back to full calculation
  if (needsFullRecalculation) {
    await _calculateProgress(optimistic: false);
    return;
  }
  
  // Calculate old contribution
  double oldTarget = 0.0;
  double oldEarned = 0.0;
  if (oldInstance != null) {
    // Only calculate if item was active (due/in-window)
    final wasActive = _wasInstanceActive(oldInstance);
    if (wasActive) {
      if (targetChanged || earnedChanged) {
        oldTarget = await _getInstanceTargetContribution(oldInstance);
        oldEarned = await _getInstanceEarnedContribution(oldInstance);
      } else {
        // No change detected, use cached values if available
        // Otherwise calculate
        oldTarget = await _getInstanceTargetContribution(oldInstance);
        oldEarned = await _getInstanceEarnedContribution(oldInstance);
      }
    }
  }
  
  // Calculate new contribution
  double newTarget = 0.0;
  double newEarned = 0.0;
  if (newInstance != null) {
    // Only calculate if item is active (due/in-window)
    final isActive = _isInstanceActive(newInstance);
    if (isActive) {
      newTarget = await _getInstanceTargetContribution(newInstance);
      newEarned = await _getInstanceEarnedContribution(newInstance);
    }
  }
  
  // Apply delta
  final updatedTarget = _dailyTarget - oldTarget + newTarget;
  final updatedEarned = _pointsEarned - oldEarned + newEarned;
  // ... rest of existing logic ...
}
2. Add helper methods for active status checking
/// Check if instance is active (counts toward today's target)
/// For tasks: due on/before today
/// For habits: within window
bool _isInstanceActive(ActivityInstanceRecord instance) {
  final today = DateService.currentDate;
  final normalizedToday = DateTime(today.year, today.month, today.day);
  
  if (instance.templateCategoryType == 'task') {
    return _isTaskDueToday(instance);
  } else if (instance.templateCategoryType == 'habit') {
    return _isWithinWindow(instance, normalizedToday);
  }
  return false;
}

/// Check if instance was active (for old instance comparison)
bool _wasInstanceActive(ActivityInstanceRecord instance) {
  return _isInstanceActive(instance); // Same logic for now
}

/// Check if task is due today (or overdue)
bool _isTaskDueToday(ActivityInstanceRecord instance) {
  if (instance.dueDate == null) return false;
  final today = DateService.currentDate;
  final normalizedToday = DateTime(today.year, today.month, today.day);
  final dueDate = DateTime(
    instance.dueDate!.year,
    instance.dueDate!.month,
    instance.dueDate!.day,
  );
  return !dueDate.isAfter(normalizedToday);
}

/// Check if habit is within window for target date
bool _isWithinWindow(ActivityInstanceRecord instance, DateTime targetDate) {
  if (instance.dueDate == null) return true;
  final dueDate = DateTime(
    instance.dueDate!.year,
    instance.dueDate!.month,
    instance.dueDate!.day,
  );
  final windowEnd = instance.windowEndDate;
  if (windowEnd != null) {
    final windowEndNormalized = DateTime(
      windowEnd.year,
      windowEnd.month,
      windowEnd.day,
    );
    return !targetDate.isBefore(dueDate) &&
        !targetDate.isAfter(windowEndNormalized);
  }
  return dueDate.isAtSameMomentAs(targetDate);
}
3. Update _getInstanceEarnedContribution() to check time bonus
Ensure time bonus is checked on every calculation:
Future<double> _getInstanceEarnedContribution(
    ActivityInstanceRecord instance) async {
  if (instance.templateCategoryType == 'essential') {
    return 0.0;
  }
  // This already checks time bonus via PointsService.calculatePointsEarned
  // which reads FFAppState.instance.timeBonusEnabled
  return await PointsService.calculatePointsEarned(instance, currentUserUid);
}
4. Handle template changes
If template is updated (priority, frequency, duration), instances may need recalculation. Add detection in _handleInstanceUpdated:
void _handleInstanceUpdated(dynamic param) {
  // ... existing code to get oldInstance ...
  
  // Check if template-related fields changed
  if (oldInstance != null && instance != null) {
    final templateFieldsChanged = 
        oldInstance.templatePriority != instance.templatePriority ||
        oldInstance.templateFrequency != instance.templateFrequency ||
        oldInstance.templateTarget != instance.templateTarget ||
        oldInstance.templateDuration != instance.templateDuration;
    
    if (templateFieldsChanged) {
      // Template fields changed - need to recalculate
      // This will be handled by _calculateProgressIncremental's change detection
    }
  }
  
  // ... rest of existing code ...
}
File: lib/Screens/Shared/Points_and_Scores/daily_points_calculator.dart
5. Ensure window logic is available
The _isWithinWindow method already exists. We'll reuse the same logic in queue_page.dart.
Edge Cases Handled
1.	Priority Change: Detected via templatePriority comparison, recalculates target and earned
2.	Due Date Change: Detected via dueDate comparison, recalculates isActive status and target
3.	Skip/Reschedule: Detected via status change to "skipped" or due date moved, removes from target
4.	Template Changes: Detected via template field changes, triggers full recalculation if templateId changes
5.	Time Bonus Toggle: Checked on every earned calculation via FFAppState.instance.timeBonusEnabled
6.	Window Logic Changes: Recalculated when habit is edited, checks _isWithinWindow for old vs new state
7.	Time Logged Changes: Detected via accumulatedTime/totalTimeLogged comparison, affects earned points
Expected Behavior
•	1-2 reads per update (same as current - only changed instance's template)
•	Accurate calculations for all change types
•	No missed updates - all point-affecting changes are detected
•	Fallback to full calculation only when template ID changes (rare)

