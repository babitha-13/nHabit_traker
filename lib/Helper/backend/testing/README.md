# Day Simulator Testing Guide

## Overview

The Day Simulator allows you to test day-end processing and time progression without waiting for actual day changes. This is essential for testing the dual boundary system for habits vs tasks.

## Quick Start

### 1. Add Testing Page to Your App

Add the testing page to your app navigation:

```dart
// In your main navigation or routing
Navigator.push(
  context,
  MaterialPageRoute(builder: (context) => const TestingPage()),
);
```

### 2. Basic Testing Workflow

1. **Start Simulation Mode**
   - Click "Start Simulation" in the Day Simulator UI
   - This puts the app in testing mode

2. **Create Test Data**
   - Go to your app and create some habits with different frequencies
   - Create some tasks with various due dates
   - Set up different categories and priorities

3. **Simulate Day Completion**
   - Use the scenario buttons (Perfect Day, Good Day, Mixed Day, etc.)
   - Or manually complete/skip habits in your app

4. **Advance to Next Day**
   - Click "Next Day" to trigger day-end processing
   - This simulates midnight and processes all open habits

5. **Check Results**
   - Navigate to your Progress page to see generated historical data
   - Check the Queue page to see how habits vs tasks are handled

## Testing Scenarios

### Perfect Day
- All habits completed fully
- Tests maximum performance tracking

### Good Day  
- Most habits completed, some partial
- Tests mixed completion scenarios

### Mixed Day
- Some completed, some partial, some skipped
- Tests realistic user behavior

### Bad Day
- Mostly partial or skipped habits
- Tests low performance scenarios

### Lazy Day
- Everything skipped
- Tests zero performance tracking

## Advanced Testing

### Week Simulation
```dart
// Simulate a complete week with different daily patterns
await DaySimulatorTesting.simulateWeek(userId: userId);
```

### Custom Scenarios
```dart
// Create custom completion patterns
final scenarios = [
  DaySimulationScenario(
    type: ScenarioType.complete,
    habitNameFilter: 'Workout', // Only apply to workout habits
  ),
  DaySimulationScenario(
    type: ScenarioType.partial,
    partialPercentage: 0.6, // 60% completion
    maxInstances: 2, // Apply to max 2 habits
  ),
];

await DaySimulator.simulateDay(
  userId: userId,
  date: DateTime.now(),
  scenarios: scenarios,
);
```

### Progress Analysis
```dart
// Get detailed analysis of simulation results
final analysis = await DaySimulatorTesting.getProgressAnalysis(
  userId: userId,
  startDate: DateTime.now().subtract(const Duration(days: 7)),
  endDate: DateTime.now(),
);

print('Average performance: ${analysis['averagePercentage']}%');
print('Perfect days: ${analysis['perfectDays']}');
```

## What to Test

### 1. Day-End Processing
- ✅ Habits auto-close at day-end
- ✅ Incomplete habits marked as 'skipped'
- ✅ Partial progress preserved (e.g., 6/8 glasses)
- ✅ DailyProgressRecord generated correctly

### 2. Queue Page Behavior
- ✅ Habits only show for today (dayState = 'open')
- ✅ Tasks show in Overdue section when past due
- ✅ Day-end countdown works correctly
- ✅ Recent completions section populated

### 3. Progress Page Analytics
- ✅ Calendar heatmap shows correct data
- ✅ 7-day trend chart displays properly
- ✅ Average calculations are accurate
- ✅ Historical data is immutable

### 4. Historical Editing
- ✅ Can edit past 30 days of habit data
- ✅ Completion status changes work
- ✅ Progress value updates work
- ✅ DailyProgressRecord recalculates

### 5. Dual Boundary System
- ✅ Habits are time-bound (belong to specific day)
- ✅ Tasks are deadline-based (can be completed late)
- ✅ Different UI handling for each type
- ✅ Correct overdue behavior

## Troubleshooting

### Common Issues

1. **"No authenticated user" error**
   - Make sure you're logged in to the app
   - Check that `currentUserUid` returns a valid user ID

2. **Simulation not advancing**
   - Ensure you're in simulation mode
   - Check that habits exist for the current day
   - Verify day-end processing completed successfully

3. **Progress data not showing**
   - Run day-end processing for the dates you're checking
   - Ensure habits were created before the simulation date
   - Check that DailyProgressRecord was generated

### Debug Information

```dart
// Check simulation status
final status = DaySimulator.getStatus();
print('Simulation mode: ${status['isSimulationMode']}');
print('Simulated date: ${status['simulatedDate']}');

// Check background scheduler status
final schedulerStatus = BackgroundScheduler.getStatus();
print('Scheduler processing: ${schedulerStatus['isProcessing']}');
```

## Integration Notes

- The Day Simulator only affects testing - it doesn't interfere with real app usage
- Simulation mode is automatically disabled when you stop the app
- All simulation data is real Firestore data, so be careful in production
- Use the testing page only in development environments

## Next Steps

1. Test all the scenarios mentioned above
2. Verify the dual boundary system works correctly
3. Check that historical data is accurate
4. Ensure UI updates reflect the new behavior
5. Test edge cases (timezone changes, late completions, etc.)

The Day Simulator provides a comprehensive testing environment for validating the entire habit vs task dual boundary system!
