# Unified Activity Instance System Implementation

## Overview

Refactor the partial instance implementation to use a unified `activity_instances` collection for both habits and tasks, implementing Microsoft To-Do style on-demand generation with smart filtering.

## Key Design Decisions

### Instance Display Logic

- Show only the **earliest pending instance** per activity (not multiple instances of same activity)
- If user hasn't completed for 7 days, show the oldest overdue instance
- User can skip one-by-one or bulk skip to today
- Completing an instance immediately generates the next based on original schedule

### Data Separation

- **Template (ActivityRecord)**: Pure definition data only (name, schedule, frequency, target, etc.)
- **Instance (ActivityInstanceRecord)**: All occurrence-specific data (dueDate, status, currentValue, accumulatedTime, completedAt, etc.)
- Remove instance-tracking fields from ActivityRecord (completedDates, skippedDates, currentValue, accumulatedTime, timer fields)

## Implementation Approach

**Phased Development**: Implement and test each phase before proceeding to the next.

### PHASE 1: Instance Creation on Activity Creation ⭐ (START HERE)

**Goal**: When user creates a new activity (task/habit), automatically create the first instance in Firestore and verify it exists.

**Files to Create/Modify**:

1. **Create**: `lib/Helper/backend/schema/activity_instance_record.dart` (NEW)

   - Firestore schema for unified instance collection
   - Collection path: `users/{userId}/activity_instances/`
   - Fields: templateId, dueDate, status, completedAt, skippedAt, currentValue, accumulatedTime, isTimerActive, timerStartTime, notes, cached template fields (templateName, templateCategoryId, templateCategoryName, templateCategoryType, templatePriority, templateTrackingType, templateTarget, templateUnit, templateDescription, templateShowInFloatingTimer), metadata (createdTime, lastUpdated, isActive)

2. **Create**: `lib/Helper/backend/activity_instance_service.dart` (NEW - under 400 lines)

   - ONLY implement: `createActivityInstance()` method
   - Logic: Create new instance with cached template data
   - Follow separation of concerns: pure business logic, no UI dependencies

3. **Modify**: `lib/Helper/backend/backend.dart` (business logic layer)

   - Update `createActivity()` function to call `ActivityInstanceService.createActivityInstance()` after template creation
   - Calculate initial dueDate: use template.startDate if available, otherwise today

**Testing**: Create a new activity through UI → Check Firestore to verify instance document was created in `activity_instances` collection

---

### PHASE 2: Display Instances Instead of Templates

**Goal**: Query and display instances in the UI instead of templates, showing only the earliest pending instance per activity.

**Files to Create/Modify**:

1. **Modify**: `lib/Helper/backend/activity_instance_service.dart`

   - Add: `getActiveInstances({userId})` method
   - Logic: Query all pending instances, group by templateId, return only earliest dueDate per group
   - Keep under 400 lines

2. **Modify**: `lib/Helper/backend/backend.dart`

   - Add wrapper: `queryTodaysActivities()` → calls ActivityInstanceService.getActiveInstances()
   - Maintain backward compatibility temporarily

3. **Modify**: `lib/Screens/Home/Home.dart` and other display screens

   - Replace ActivityRecord with ActivityInstanceRecord in queries
   - Use cached template fields for display
   - No functional changes, just display

**Testing**: Open app → Verify instances are displayed correctly with proper data from cached template fields

---

### PHASE 3: Instance Completion & Next Instance Generation

**Goal**: When user completes an instance, mark it complete and generate the next instance based on schedule.

**Files to Modify**:

1. **Create**: `lib/Helper/backend/recurrence_calculator.dart` (NEW - separate file for SoC, under 400 lines)

   - Extract recurrence logic to dedicated file
   - Method: `calculateNextDueDate({currentDueDate, schedule, frequency, specificDays, everyXValue, periodType, etc.})`
   - Support all frequency patterns

2. **Modify**: `lib/Helper/backend/activity_instance_service.dart`

   - Add: `completeInstance({instanceId, finalValue, finalAccumulatedTime, notes})`
   - Logic: Mark complete, calculate next due date, create next instance

3. **Modify**: `lib/Helper/backend/backend.dart`

   - Add wrapper: `completeActivity()` → calls ActivityInstanceService.completeInstance()

4. **Modify**: UI completion handlers (item_component.dart, etc.)

   - Update to call new completion function with instanceId

**Testing**: Complete an activity → Verify it's marked complete in Firestore AND next instance is created with correct due date

---

### PHASE 4: Skip Functionality (Single & Bulk)

**Goal**: Allow users to skip instances one-by-one or bulk skip all past instances.

**Files to Modify**:

1. **Modify**: `lib/Helper/backend/activity_instance_service.dart`

   - Add: `skipInstance({instanceId, notes})`
   - Add: `skipAllPastInstances({templateId})`

2. **Modify**: `lib/Helper/backend/backend.dart`

   - Add wrappers: `skipActivity()`, `skipAllPastActivities()`

3. **Modify**: UI components

   - Add "Skip" button for individual instances
   - Add "Skip All Past" button for overdue activities

**Testing**: Skip individual instance → next appears. Skip all past → today's instance appears.

---

### PHASE 5: Progress Tracking & Timer

**Goal**: Update instance progress in real-time (quantity tracking, timer accumulation).

**Files to Modify**:

1. **Modify**: `lib/Helper/backend/activity_instance_service.dart`

   - Add: `updateInstanceProgress({instanceId, currentValue, accumulatedTime, isTimerActive, timerStartTime})`

2. **Modify**: Timer and progress UI components

   - Update to work with instance fields instead of template fields

**Testing**: Track progress on an instance → verify updates in Firestore instance document

---

### PHASE 6: Template Cleanup & Migration

**Goal**: Remove instance-specific fields from ActivityRecord template, clean up old files.

**Files to Modify**:

1. **Modify**: `lib/Helper/backend/schema/activity_record.dart`

   - Remove: completedDates, skippedDates, currentValue, accumulatedTime, timer fields
   - Keep only definition fields

2. **Delete**: Old instance files

   - `lib/Helper/backend/schema/habit_instance_record.dart`
   - `lib/Helper/backend/schema/task_instance_record.dart`  
   - `lib/Helper/backend/task_instance_service.dart`

3. **Update**: Remove any remaining references to removed template fields

**Testing**: Ensure app functions normally without old instance fields on template

---

## Architecture Principles (Apply to All Phases)

1. **Separation of Concerns**

   - Business logic: `lib/Helper/backend/` (NO UI dependencies)
   - UI: `lib/Screens/` (calls Helper functions, handles presentation only)
   - Reusable UI: `lib/Helper/utils/` (widgets, NO business logic)

2. **File Size Limits**

   - Maximum 400 lines per file
   - Extract complex functions to separate files if needed
   - Examples: recurrence_calculator.dart, instance_query_helpers.dart

3. **Function Size**

   - Maximum 50 lines per function
   - Break complex logic into smaller helper functions

4. **Testing Strategy**

   - Complete each phase fully
   - Verify in UI AND Firestore console
   - Get user confirmation before proceeding to next phase

## Key Business Rules

1. **One Instance Per Activity in View**: Group by templateId, show earliest pending
2. **On-Demand Generation**: Next instance created only when current is completed/skipped
3. **Original Schedule Preservation**: Next due date calculated from instance.dueDate, not completion date
4. **Early Completion**: If completing ahead of schedule, next instance uses original next date
5. **Template as Definition**: Template never stores completion data, only configuration
6. **Bulk Skip Option**: User can skip all past to jump to today's instance

## Data Flow Example

```
1. User creates "Workout" habit (daily)
   → ActivityRecord created with schedule="daily", frequency=1
   → ActivityInstanceRecord created with dueDate=today

2. User completes workout on Day 1
   → Instance marked completed, completedAt=now
   → New instance created with dueDate=Day 2

3. User misses Days 2-5, opens app on Day 6
   → Query shows Day 2 instance (earliest pending)
   → User can: (a) complete Day 2, (b) skip Day 2, (c) skip all to Day 6

4. User chooses "Skip All Past"
   → Days 2-5 instances marked skipped
   → New instance created for Day 6
```

## Files to Modify

- `lib/Helper/backend/schema/activity_record.dart` - Remove instance fields
- `lib/Helper/backend/schema/activity_instance_record.dart` - Create new unified schema
- `lib/Helper/backend/activity_instance_service.dart` - Create new service
- `lib/Helper/backend/backend.dart` - Update integration functions
- `lib/Helper/utils/item_component.dart` - Update to use instances
- `lib/Screens/Home/Home.dart` - Query instances instead of templates
- `lib/Screens/Task/task_page.dart` - Update task page logic
- `lib/Screens/Habits/habits_page.dart` - Update habits page logic
- `lib/Screens/Queue/queue_page.dart` - Update queue logic
- `lib/Screens/Edit Task/edit_task.dart` - Update edit logic
- Delete: `habit_instance_record.dart`, `task_instance_record.dart`, `task_instance_service.dart`