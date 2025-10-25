<!-- 49daa280-07b0-4709-b00e-be4fac8b51dc 06b256e1-0597-44a5-8fa8-21cd590d027e -->
# Habit Completion Window System

## Overview

Replace the current day-based habit system with a window-based system where each habit instance has a completion window based on its frequency.

## Core Logic

### Window Calculation

```dart
// "Every X days" → Window = X days
everyXValue = 3, everyXPeriodType = "days"
→ windowDuration = 3 days

// "X times per period" → Window = periodDays / X (rounded)
timesPerPeriod = 3, periodType = "weeks" (7 days)
→ windowDuration = 7 / 3 = 2.33... → round(2.33) = 2 days

// "Every day" → Window = 1 day
everyXValue = 1, everyXPeriodType = "days"
→ windowDuration = 1 day
```

### Instance Creation

```dart
belongsToDate: Start of the window (when instance created)
windowEndDate: belongsToDate + windowDuration - 1

Example "3 times per week":
Instance 1: Mon-Wed (2 days window)
Instance 2: Wed-Fri (2 days window)  
Instance 3: Fri-Mon (2 days window, wraps to next week)
```

### State Transitions

```
DAY 1-2 (within window):
 - status = 'pending'
 - User can complete anytime
 - If completed → status = 'completed', generate next instance

END OF WINDOW (windowEndDate):
 - If status still 'pending' → change to 'skipped'
 - Preserve currentValue (e.g., 6/8 glasses)
 - Generate next instance with:
  - belongsToDate = windowEndDate + 1
  - windowEndDate = belongsToDate + windowDuration - 1
```

## Implementation Changes

### 1. Update Schema (activity_instance_record.dart)

Add window fields to ActivityInstanceRecord:

```dart
DateTime? windowEndDate;    // End of completion window
int? windowDuration;        // Duration in days (cached from template)
```

### 2. Modify DayEndProcessor (day_end_processor.dart)

Change from "close all open habits at day-end" to "close habits whose window expired":

```dart
static Future<void> processDayEnd({required String userId, DateTime? targetDate}) {
  final processDate = targetDate ?? DateTime.now();
  
  // Query habit instances where windowEndDate < processDate AND status = 'pending'
  final expiredInstances = await ActivityInstanceRecord.collectionForUser(userId)
    .where('templateCategoryType', isEqualTo: 'habit')
    .where('status', isEqualTo: 'pending')
    .where('windowEndDate', isLessThan: processDate)
    .get();
  
  for (instance in expiredInstances) {
    // Mark as skipped (preserve currentValue)
    await instance.reference.update({
      'status': 'skipped',
      'skippedAt': DateTime.now(),
    });
    
    // Generate next instance
    await _generateNextInstance(instance, userId);
  }
  
  // Create DailyProgressRecord for completed/skipped habits
  await _createDailyProgressRecord(userId, processDate);
}
```

### 3. Add Window Generation Logic

Create helper to generate next instance after completion or skip:

```dart
Future<void> _generateNextInstance(ActivityInstanceRecord instance, String userId) {
  final template = await ActivityRecord.collectionForUser(userId).doc(instance.templateId).get();
  
  // Calculate next window start = current windowEndDate + 1
  final nextBelongsToDate = instance.windowEndDate!.add(Duration(days: 1));
  final nextWindowEndDate = nextBelongsToDate.add(Duration(days: instance.windowDuration! - 1));
  
  await createActivityInstance(
    templateId: instance.templateId,
    dueDate: nextBelongsToDate,  // dueDate = start of window
    template: template,
    userId: userId,
    windowEndDate: nextWindowEndDate,
    windowDuration: instance.windowDuration,
  );
}
```

### 4. Update Instance Creation (activity_instance_service.dart)

When creating instances, calculate window:

```dart
static Future<DocumentReference> createActivityInstance({
  required String templateId,
  required DateTime dueDate,
  required ActivityRecord template,
  String? userId,
}) {
  // Calculate window duration from template
  int windowDuration;
  if (template.frequencyType == 'everyX') {
    windowDuration = template.everyXValue ?? 1;
  } else if (template.frequencyType == 'timesPerPeriod') {
    final periodDays = _periodTypeToDays(template.periodType);
    windowDuration = (periodDays / template.timesPerPeriod!).round();
  } else {
    windowDuration = 1; // default daily
  }
  
  final windowEndDate = dueDate.add(Duration(days: windowDuration - 1));
  
  final instanceData = createActivityInstanceRecordData(
    // ... existing fields ...
    windowEndDate: windowEndDate,
    windowDuration: windowDuration,
    belongsToDate: dueDate,  // Start of window
  );
}
```

### 5. Update Completion Logic (activity_instance_service.dart)

When user completes habit, generate next instance:

```dart
static Future<void> completeActivityInstance({
  required String instanceId,
  dynamic finalValue,
  String? userId,
}) {
  // Update current instance
  await instanceRef.update({
    'status': 'completed',
    'completedAt': DateTime.now(),
    'currentValue': finalValue,
  });
  
  // Generate next instance
  await _generateNextInstance(instance, userId);
}
```

### 6. Update Queue Page Display (queue_page.dart)

Show habits within their active window:

```dart
// Query habits where windowEndDate >= today (window still active)
final activeHabits = await ActivityInstanceRecord.collectionForUser(userId)
  .where('templateCategoryType', isEqualTo: 'habit')
  .where('status', isEqualTo: 'pending')
  .where('windowEndDate', isGreaterThanOrEqualTo: today)
  .get();

// Display with window countdown
// "Workout • 2 days left"
```

### 7. Update Progress Tracking

Count habit for actual completion date:

```dart
// When completed, use completedAt for DailyProgressRecord
// When skipped, use windowEndDate for DailyProgressRecord
```

## Files to Modify

1. `lib/Helper/backend/schema/activity_instance_record.dart`

                                                                                                                                                                                                                                                                                                                                                                                                - Add `windowEndDate`, `windowDuration` fields

2. `lib/Helper/backend/day_end_processor.dart`

                                                                                                                                                                                                                                                                                                                                                                                                - Change query from `dayState='open'` to `windowEndDate < today`
                                                                                                                                                                                                                                                                                                                                                                                                - Add `_generateNextInstance()` helper

3. `lib/Helper/backend/activity_instance_service.dart`

                                                                                                                                                                                                                                                                                                                                                                                                - Update `createActivityInstance()` to calculate windows
                                                                                                                                                                                                                                                                                                                                                                                                - Update `completeActivityInstance()` to generate next
                                                                                                                                                                                                                                                                                                                                                                                                - Add window calculation helpers

4. `lib/Screens/Queue/queue_page.dart`

                                                                                                                                                                                                                                                                                                                                                                                                - Update query to show habits in active window
                                                                                                                                                                                                                                                                                                                                                                                                - Display window countdown

5. `lib/Helper/backend/points_service.dart`

                                                                                                                                                                                                                                                                                                                                                                                                - Update progress calculation to use completion date

## Testing with Day Advancer

The simple day advancer will now:

1. Advance date
2. Process habits whose windows expired on that date
3. Generate next instances for expired habits
4. Create progress records

Example flow:

- Mon: Create "3x/week" habit → window Mon-Wed
- Tue: User completes → generates next instance Wed-Fri
- Thu: User doesn't complete by Wed end → auto-skip Wed night → generates Fri-Mon
- Test by advancing days and checking window expiry

## Benefits

- Habits remain visible for their full window
- "3 times per week" spreads naturally (Mon-Wed, Wed-Fri, Fri-Mon)
- Partial completions preserved until window expires
- Maintains schedule rhythm even with skips
- Works seamlessly with day advancer testing

### To-dos

- [ ] Add windowEndDate and windowDuration fields to ActivityInstanceRecord schema
- [ ] Modify DayEndProcessor to check window expiry instead of day boundary
- [ ] Add _generateNextInstance helper to create next habit after skip/complete
- [ ] Update createActivityInstance to calculate and set window fields
- [ ] Update completeActivityInstance to generate next instance immediately
- [ ] Update Queue page to show habits in active window with countdown
- [ ] Update DailyProgressRecord to use actual completion date
- [ ] Test window system with day advancer for various frequencies