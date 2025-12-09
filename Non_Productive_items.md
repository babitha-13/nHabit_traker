# Add Non-Productive Items Feature

## Overview

Implement "Non-Productive Items" - a new category type for tracking time-consuming activities like sleep, travel, rest, and entertainment. These items won't earn points but will appear in the calendar for complete time accounting and can be included in sequences/routines.

## Architecture Approach

Model after the existing `sequence_item` pattern:

- **Templates**: Pre-created non-productive item templates stored in `ActivityRecord` with `categoryType: 'non_productive'`
- **Instances**: On-demand instances created with time logs (start/end time) when user taps to record
- **No Points**: Excluded from all points calculations and daily progress percentages
- **Calendar Integration**: Display time blocks in calendar view
- **Sequence Integration**: Available in sequence builder search

## Implementation Steps

### 1. Database Schema Updates

**File: `lib/Helper/backend/schema/activity_record.dart`**

- Already supports `categoryType` field - will use value `'non_productive'`
- No schema changes needed; existing structure supports this

**File: `lib/Helper/backend/schema/activity_instance_record.dart`**

- Already has `timeLogSessions` field for time tracking
- Will use existing instance structure with `templateCategoryType: 'non_productive'`

### 2. Backend Service Layer

**New File: `lib/Helper/backend/non_productive_service.dart`**

Create service with methods:

- `createNonProductiveTemplate()` - Create reusable templates (e.g., "Sleep", "Travel")
- `createNonProductiveInstance()` - Create instance with time log on demand
- `getNonProductiveTemplates()` - Fetch all non-productive templates for user
- `logTimeForInstance()` - Add/update time log session (start/end time, notes)
- `deleteNonProductiveTemplate()` - Remove template

### 3. Points System Exclusion

**File: `lib/Helper/backend/points_service.dart`**

- Update `calculateDailyTarget()` - Skip if `templateCategoryType == 'non_productive'`
- Update `calculatePointsEarned()` - Return 0.0 for non-productive items
- Update `calculateTaskPointsEarned()` - Skip non-productive items

**File: `lib/Helper/backend/daily_progress_calculator.dart`**

- Filter out non-productive items from habit/task counts
- Exclude from target/earned points calculations
- Exclude from completion percentage

### 4. Calendar Integration

**File: `lib/Screens/Calendar/calendar_page.dart`**

- Update `_loadEvents()` to query non-productive instances with time logs
- Display time blocks with distinct visual styling (e.g., muted colors, dashed borders)
- Show notes/description in event details

**File: `lib/Helper/backend/task_instance_service.dart`**

- Add `getNonProductiveInstances()` method to fetch instances for calendar

### 5. Sequence Integration

**File: `lib/Screens/Sequence/create_sequence_page.dart`**

- Update search/filter to include non-productive templates
- Display with distinct icon/badge (e.g., "NP" badge or clock icon)

**File: `lib/Helper/backend/sequence_service.dart`**

- Ensure `createSequence()` handles `categoryType: 'non_productive'`
- Update instance creation to support non-productive items in sequences

**File: `lib/Screens/Sequence/sequence_detail_page.dart`**

- Display non-productive items in sequence list
- Allow quick-tap to create instance with time log dialog

### 6. UI Components

**New File: `lib/Helper/utils/non_productive_template_dialog.dart`**

Create dialog for adding/editing non-productive templates:

- Name field (e.g., "Sleep", "Commute")
- Description/notes field
- Optional default duration hint
- Color picker for calendar display

**New File: `lib/Helper/utils/time_log_dialog.dart`**

Create dialog for logging time when tapping a non-productive template:

- Start time picker
- End time picker (or "Now" button)
- Notes field
- Quick duration buttons (15m, 30m, 1h, 2h)

**New File: `lib/Screens/NonProductive/non_productive_templates_page.dart`**

Management page accessible from Sequences tab or Calendar:

- List of non-productive templates
- Add new template button
- Edit/delete existing templates
- Quick-log button to create instance

### 7. Access Points

**Option A: Add to Sequences Page**

- Add floating action button or tab in Sequences page
- "Manage Non-Productive Items" option in menu

**Option B: Add to Calendar Page**

- Add FAB in calendar to create non-productive log
- Long-press on calendar to quick-add time block

**Recommended: Both**

- Sequences page: Manage templates
- Calendar page: Quick-log instances

### 8. Search Integration

**File: `lib/Helper/backend/backend.dart` or search utility**

- Include non-productive templates in global search
- Filter by `categoryType: 'non_productive'`
- Display with "Non-Productive" badge in results

## Key Technical Decisions

1. **No new collections**: Use existing `ActivityRecord` (templates) and `ActivityInstanceRecord` (instances) with `categoryType: 'non_productive'`

2. **Time tracking**: Leverage existing `timeLogSessions` field structure:
```dart
{
  'startTime': DateTime,
  'endTime': DateTime,
  'notes': String?,
}
```

3. **Points exclusion**: Filter at calculation level, not database level, for flexibility

4. **Visual distinction**: Use muted colors and "NP" badge to differentiate from productive items

5. **No Queue/Progress**: Exclude from Queue page and daily progress percentage, but could optionally show count in a separate section

## Files to Create

- `lib/Helper/backend/non_productive_service.dart`
- `lib/Helper/utils/non_productive_template_dialog.dart`
- `lib/Helper/utils/time_log_dialog.dart`
- `lib/Screens/NonProductive/non_productive_templates_page.dart`

## Files to Modify

- `lib/Helper/backend/points_service.dart`
- `lib/Helper/backend/daily_progress_calculator.dart`
- `lib/Screens/Calendar/calendar_page.dart`
- `lib/Helper/backend/task_instance_service.dart`
- `lib/Screens/Sequence/create_sequence_page.dart`
- `lib/Helper/backend/sequence_service.dart`
- `lib/Screens/Sequence/sequence_detail_page.dart`
- `lib/Screens/Home/Home.dart` (optional: add menu item)

## Testing Checklist

- [ ] Create non-productive template (e.g., "Sleep")
- [ ] Log time instance from calendar
- [ ] Verify no points awarded
- [ ] Verify excluded from daily progress %
- [ ] Add to sequence and verify it appears
- [ ] Create instance from sequence
- [ ] Verify calendar displays time blocks correctly
- [ ] Edit/delete templates
- [ ] Search for non-productive items in sequence builder