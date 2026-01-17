# Double Optimistic Broadcast Issue - Root Cause Analysis

## Problem
Status flip observed when completing/uncompleting tasks or habits on Queue and Habits pages:
- User completes task → Status: complete
- Brief revert → Status: incomplete  
- Final correction → Status: complete

## Root Cause: Double Optimistic Broadcasts

### Flow Analysis

#### ItemBinary Controls Flow (DOUBLE BROADCAST):
1. **Line 89-95** (`item_binary_controls_helper.dart`): Creates optimistic instance, tracks operation
2. **Line 98-100**: **FIRST BROADCAST** - `broadcastInstanceUpdatedOptimistic()` 
3. **Line 116**: Calls `ActivityInstanceService.completeInstance()`
4. **Line 1457** (`activity_instance_service.dart`): **SECOND BROADCAST** - `broadcastInstanceUpdatedOptimistic()` again!
5. Backend update happens
6. Reconciliation broadcast

**Result**: Two different optimistic instances with potentially different timestamps/data are broadcast, causing race conditions.

#### ItemQuantitative/ItemTime Controls Flow (SINGLE BROADCAST - Correct):
1. Directly calls `ActivityInstanceService.completeInstance()`
2. Service creates optimistic instance and broadcasts once
3. Backend update happens
4. Reconciliation broadcast

### Why This Causes the Flip

The issue sequence:
1. ItemComponent broadcasts optimistic update with timestamp T1
2. Service broadcasts another optimistic update with timestamp T2 (slightly later)
3. Pages receive both broadcasts and process them
4. The stale-update guard compares timestamps
5. Non-optimistic updates from backend might arrive between T1 and T2
6. This creates a race where:
   - T1 optimistic shows "complete"
   - Backend update (or T2 optimistic) temporarily overwrites with old data
   - Final reconciliation corrects to "complete"

## Solution

Added `skipOptimisticUpdate` flag to `completeInstance()` and `uncompleteInstance()`:

### Changes Made:

1. **`activity_instance_service.dart`**:
   - Added `skipOptimisticUpdate` parameter to both methods
   - Wrapped optimistic broadcast logic in `if (!skipOptimisticUpdate)` blocks
   - Made `operationId` nullable to handle skip case
   - Only reconcile if `operationId` exists (i.e., we created an optimistic update)
   - Broadcast regular update if skipping optimistic but need notification

2. **`item_binary_controls_helper.dart`**:
   - Pass `skipOptimisticUpdate: true` when calling both methods
   - Prevents double broadcast since ItemComponent already handled optimistic update

### Pattern:

**Callers that handle their own optimistic updates:**
- ItemBinaryControlsHelper ✓ (calls with `skipOptimisticUpdate: true`)

**Callers that rely on service optimistic updates:**
- ItemTimeControlsHelper ✓ (calls without flag - service handles it)
- ItemQuantitativeControlsHelper ✓ (calls without flag - service handles it)
- NotificationService ✓ (calls without flag - service handles it)
- AlarmRingingPage ✓ (calls without flag - service handles it)
- MorningCatchupLogic ✓ (calls without flag - service handles it)
- Other direct callers ✓ (existing behavior preserved)

## Testing Checklist

- [ ] Complete task on Queue page - no flip
- [ ] Uncomplete task on Queue page - no flip
- [ ] Complete habit on Habits page - no flip
- [ ] Uncomplete habit on Habits page - no flip
- [ ] Rapid toggle complete/incomplete - smooth handling
- [ ] Complete from notification action - works
- [ ] Complete from alarm page - works
- [ ] Quantitative auto-completion - works
- [ ] Time tracking completion - works
