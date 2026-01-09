# Fix Uncomplete Behavior for All Item Types

## Problem

When uncompleting an item (unchecking, reducing quantity, or resetting timer to zero), the status doesn't consistently revert to 'pending' and items don't move back to the Pending section in the Queue page.

### Current Issues:

1. **Timer Reset** doesn't revert status - only sets `accumulatedTime: 0` without checking if item is completed
2. **Skipped items** can't be uncompleted - no logic to revert `'skipped'` status to `'pending'`
3. **Quantity reduction** works for completed items but not skipped items
4. **Binary uncheck** works for completed items but not skipped items

## Expected Behavior

All uncomplete actions should:
- Revert status from `'completed'` OR `'skipped'` to `'pending'`
- Clear `completedAt` or `skippedAt` timestamp
- Remove strike-through styling
- Move item back to "Pending" section in Queue page
- Work consistently across all pages (Queue, Habits, Tasks)

## Solution

### 1. Update `uncompleteInstance()` to handle skipped items

**File:** `lib/Helper/backend/activity_instance_service.dart` (line 864-894)

Update the function to also clear `skippedAt`:

```dart
/// Uncomplete an activity instance (mark as pending from completed OR skipped)
static Future<void> uncompleteInstance({
  required String instanceId,
  String? userId,
}) async {
  final uid = userId ?? _currentUserId;

  try {
    final instanceRef =
        ActivityInstanceRecord.collectionForUser(uid).doc(instanceId);
    final instanceDoc = await instanceRef.get();

    if (!instanceDoc.exists) {
      throw Exception('Activity instance not found');
    }

    await instanceRef.update({
      'status': 'pending',
      'completedAt': null,
      'skippedAt': null,  // Add this to also clear skippedAt
      'lastUpdated': DateService.currentDate,
    });

    // Broadcast the instance update event
    final updatedInstance =
        await getUpdatedInstance(instanceId: instanceId, userId: uid);
    InstanceEvents.broadcastInstanceUpdated(updatedInstance);
  } catch (e) {
    print('Error uncompleting activity instance: $e');
    rethrow;
  }
}
```

### 2. Update auto-uncomplete logic to handle skipped items

**File:** `lib/Helper/backend/activity_instance_service.dart` (line 950-955)

Update the condition to check for both completed AND skipped:

```dart
} else {
  // Auto-uncomplete if currently completed OR skipped and progress dropped below target
  if (instance.status == 'completed' || instance.status == 'skipped') {
    await uncompleteInstance(
      instanceId: instanceId,
      userId: uid,
    );
  } else {
    // Not completed, just broadcast progress update
    final updatedInstance =
        await getUpdatedInstance(instanceId: instanceId, userId: uid);
    InstanceEvents.broadcastInstanceUpdated(updatedInstance);
  }
}
```

### 3. Update timer reset to auto-uncomplete

**File:** `lib/Helper/utils/item_component.dart` (line 1521-1559)

After resetting the timer, check if status should revert to pending:

```dart
Future<void> _resetTimer() async {
  if (_isUpdating) return;

  setState(() {
    _isUpdating = true;
  });

  try {
    // Get current instance to check status
    final instance = widget.instance;
    
    // Reset timer by updating the instance directly
    final instanceRef =
        ActivityInstanceRecord.collectionForUser(currentUserUid)
            .doc(widget.instance.reference.id);
    
    await instanceRef.update({
      'accumulatedTime': 0,
      'isTimerActive': false,
      'timerStartTime': null,
      'lastUpdated': DateTime.now(),
    });

    // If the item was completed or skipped based on timer, uncomplete it
    if (instance.status == 'completed' || instance.status == 'skipped') {
      // Check if timer was the only progress (for time-based tracking)
      if (instance.templateTrackingType == 'time') {
        await ActivityInstanceService.uncompleteInstance(
          instanceId: widget.instance.reference.id,
        );
      }
    }

    // Get the updated instance data
    final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
      instanceId: widget.instance.reference.id,
    );

    // Call the instance update callback for real-time updates
    widget.onInstanceUpdated?.call(updatedInstance);

    // Broadcast update
    InstanceEvents.broadcastInstanceUpdated(updatedInstance);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Timer reset to 0')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error resetting timer: $e')),
      );
    }
  } finally {
    if (mounted) {
      setState(() {
        _isUpdating = false;
      });
    }
  }
}
```

### 4. Update binary uncheck to handle skipped items

**File:** `lib/Helper/utils/item_component.dart` (line 1225-1271)

The current implementation already calls `uncompleteInstance()`, so once we update that function to handle skipped items (step 1), this will automatically work correctly.

No changes needed here - it will work once uncompleteInstance() is updated.

### 5. Add "Unskip" option to context menu for skipped items

**File:** `lib/Helper/utils/item_component.dart` (line 721-858)

Update the `_showScheduleMenu()` function to show "Unskip" instead of "Skip/Snooze" when the item is skipped.

#### For Habits (lines 736-799):

```dart
if (isHabit) {
  // Habit-specific menu
  final isSkipped = widget.instance.status == 'skipped';
  
  if (isSkipped) {
    // Show unskip option for skipped habits
    menuItems.add(
      const PopupMenuItem<String>(
        value: 'unskip',
        height: 32,
        child: Text('Unskip', style: TextStyle(fontSize: 12)),
      ),
    );
  } else if (isSnoozed) {
    // Show bring back option for snoozed habits
    menuItems.add(
      const PopupMenuItem<String>(
        value: 'bring_back',
        height: 32,
        child: Text('Bring back', style: TextStyle(fontSize: 12)),
      ),
    );
  } else {
    // Check if habit has partial progress
    final currentValue = _currentProgressLocal();
    final hasProgress = currentValue > 0;

    if (hasProgress) {
      menuItems.add(
        const PopupMenuItem<String>(
          value: 'skip_rest',
          height: 32,
          child: Text('Skip the rest', style: TextStyle(fontSize: 12)),
        ),
      );
    } else {
      menuItems.add(
        const PopupMenuItem<String>(
          value: 'skip',
          height: 32,
          child: Text('Skip', style: TextStyle(fontSize: 12)),
        ),
      );
    }

    // ... rest of the snooze options for pending habits
  }
}
```

#### For Recurring Tasks (lines 800-857):

```dart
} else if (isRecurringTask) {
  // Recurring task menu
  final isSkipped = widget.instance.status == 'skipped';
  
  if (isSkipped) {
    // Show unskip option for skipped tasks
    menuItems.add(
      const PopupMenuItem<String>(
        value: 'unskip',
        height: 32,
        child: Text('Unskip', style: TextStyle(fontSize: 12)),
      ),
    );
  } else if (isSnoozed) {
    // Show bring back option for snoozed tasks
    menuItems.add(
      const PopupMenuItem<String>(
        value: 'bring_back',
        height: 32,
        child: Text('Bring back', style: TextStyle(fontSize: 12)),
      ),
    );
  } else {
    // ... existing skip and snooze options for pending tasks
  }
}
```

#### For One-time Tasks (lines 858+):

```dart
} else {
  // One-time tasks menu
  final isSkipped = widget.instance.status == 'skipped';
  
  if (isSkipped) {
    // Show unskip option for skipped one-time tasks
    menuItems.add(
      const PopupMenuItem<String>(
        value: 'unskip',
        height: 32,
        child: Text('Unskip', style: TextStyle(fontSize: 12)),
      ),
    );
  } else {
    // ... existing snooze options for pending tasks
  }
}
```

#### Handle "unskip" action in menu selection (around line 1020-1050):

```dart
switch (value) {
  case 'unskip':
    await _handleUnskip();
    break;
  case 'skip':
    // ... existing skip logic
    break;
  // ... other cases
}
```

#### Add `_handleUnskip()` function:

```dart
Future<void> _handleUnskip() async {
  try {
    await ActivityInstanceService.uncompleteInstance(
      instanceId: widget.instance.reference.id,
    );
    
    // Get the updated instance
    final updatedInstance = await ActivityInstanceService.getUpdatedInstance(
      instanceId: widget.instance.reference.id,
    );
    
    // Call the instance update callback
    widget.onInstanceUpdated?.call(updatedInstance);
    
    // Broadcast update
    InstanceEvents.broadcastInstanceUpdated(updatedInstance);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item unskipped and returned to pending')),
      );
    }
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error unskipping: $e')),
      );
    }
  }
}
```

### 6. Ensure pages handle status changes correctly

**Files:** 
- `lib/Screens/Queue/queue_page.dart`
- `lib/Screens/Habits/habits_page.dart`
- `lib/Screens/Task/task_page.dart`

The pages already listen to `InstanceEvents.instanceUpdated` and update their local state. The Queue page's bucketing logic already handles status changes correctly by moving items between sections based on status.

**No changes needed** - the existing event system will handle the moves.

## Testing Checklist

After implementation, verify:

### Uncomplete via UI Actions:
- [ ] Binary checkbox: Uncheck completed item → status becomes pending, no strike-through, moves to Pending section
- [ ] Binary checkbox: Uncheck skipped item → status becomes pending, no strike-through, moves to Pending section
- [ ] Quantity: Reduce below target when completed → status becomes pending, moves to Pending section
- [ ] Quantity: Reduce below target when skipped → status becomes pending, moves to Pending section
- [ ] Timer: Reset to 0 when completed via timer → status becomes pending, moves to Pending section
- [ ] Timer: Reset to 0 when skipped → status becomes pending, moves to Pending section

### Unskip via Context Menu:
- [ ] Skipped habit shows "Unskip" option in context menu (not Skip/Snooze)
- [ ] Skipped recurring task shows "Unskip" option in context menu (not Skip/Snooze)
- [ ] Skipped one-time task shows "Unskip" option in context menu (not Snooze)
- [ ] Clicking "Unskip" reverts status to pending and removes strike-through
- [ ] Unskipped item moves from Completed/Skipped section to Pending section in Queue
- [ ] Unskip shows confirmation message "Item unskipped and returned to pending"

### Cross-page Consistency:
- [ ] Works consistently in Queue page (items move between sections)
- [ ] Works consistently in Habits page (strike-through appears/disappears)
- [ ] Works consistently in Tasks page (strike-through appears/disappears)
- [ ] Unskip works for both habits and tasks

## Expected Behavior After Fix

✅ Unchecking a binary item reverts status to pending (completed or skipped)
✅ Reducing quantity below target reverts status to pending (completed or skipped)
✅ Resetting timer to zero reverts status to pending if time-tracked (completed or skipped)
✅ **Unskip option appears in context menu for skipped items** (instead of Skip/Snooze)
✅ **Clicking Unskip reverts skipped items to pending status**
✅ Strike-through styling removed when status reverts to pending
✅ Items move from Completed/Skipped section back to Pending section in Queue
✅ Consistent behavior across all pages (Queue, Habits, Tasks)
✅ Works for both habits and tasks

