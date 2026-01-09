# Add Essential Activities Feature

## Overview

Implement "Essential Activities" - a new category type for tracking time-consuming activities like sleep, travel, rest, and entertainment. These items won't earn points but will appear in the calendar for complete time accounting and can be included in sequences/routines.

## Architecture Approach

Model after the existing `sequence_item` pattern:

- **Templates**: Pre-created essential item templates stored in `ActivityRecord` with `categoryType: 'essential'`
- **Instances**: On-demand instances created with time logs (start/end time) when user taps to record
- **No Points**: Excluded from all points calculations and daily progress percentages
- **Calendar Integration**: Display time blocks in calendar view
- **Sequence Integration**: Available in sequence builder search

## Implementation Steps

### 1. Database Schema Updates

**File: `lib/Helper/backend/schema/activity_record.dart`**

- Already supports `categoryType` field - will use value `'essential'`
- No schema changes needed; existing structure supports this

**File: `lib/Helper/backend/schema/activity_instance_record.dart`**

- Already has `timeLogSessions` field for time tracking
- Will use existing instance structure with `templateCategoryType: 'essential'`

### 2. Backend Service Layer

**New File: `lib/Helper/backend/essential_service.dart`**

Create service with methods:

- `createessentialTemplate()` - Create reusable templates (e.g., "Sleep", "Travel")
- `createessentialInstance()` - Create instance with time log on demand
- `getessentialTemplates()` - Fetch all essential templates for user
- `logTimeForInstance()` - Add/update time log session (start/end time, notes)
- `deleteessentialTemplate()` - Remove template

### 3. Points System Exclusion

**File: `lib/Helper/backend/points_service.dart`**

- Update `calculateDailyTarget()` - Skip if `templateCategoryType == 'essential'`
- Update `calculatePointsEarned()` - Return 0.0 for Essential Activities
- Update `calculateTaskPointsEarned()` - Skip Essential Activities

**File: `lib/Helper/backend/daily_progress_calculator.dart`**

- Filter out Essential Activities from habit/task counts
- Exclude from target/earned points calculations
- Exclude from completion percentage

### 4. Calendar Integration

**File: `lib/Screens/Calendar/calendar_page.dart`**

- Update `_loadEvents()` to query essential instances with time logs
- Display time blocks with distinct visual styling (e.g., muted colors, dashed borders)
- Show notes/description in event details

**File: `lib/Helper/backend/task_instance_service.dart`**

- Add `getessentialInstances()` method to fetch instances for calendar

### 5. Sequence Integration

**File: `lib/Screens/Sequence/create_sequence_page.dart`**

- Update search/filter to include essential templates
- Display with distinct icon/badge (e.g., "NP" badge or clock icon)

**File: `lib/Helper/backend/sequence_service.dart`**

- Ensure `createSequence()` handles `categoryType: 'essential'`
- Update instance creation to support Essential Activities in sequences

**File: `lib/Screens/Sequence/sequence_detail_page.dart`**

- Display Essential Activities in sequence list
- Allow quick-tap to create instance with time log dialog

### 6. UI Components

**New File: `lib/Helper/utils/essential_template_dialog.dart`**

Create dialog for adding/editing essential templates:

- Name field (e.g., "Sleep", "Commute")
- Description/notes field
- Optional default duration hint
- Color picker for calendar display

**New File: `lib/Helper/utils/time_log_dialog.dart`**

Create dialog for logging time when tapping a essential template:

- Start time picker
- End time picker (or "Now" button)
- Notes field
- Quick duration buttons (15m, 30m, 1h, 2h)

**New File: `lib/Screens/essential/essential_templates_page.dart`**

Management page accessible from Sequences tab or Calendar:

- List of essential templates
- Add new template button
- Edit/delete existing templates
- Quick-log button to create instance

### 7. Access Points

**Option A: Add to Sequences Page**

- Add floating action button or tab in Sequences page
- "Manage Essential Activities" option in menu

**Option B: Add to Calendar Page**

- Add FAB in calendar to create essential log
- Long-press on calendar to quick-add time block

**Recommended: Both**

- Sequences page: Manage templates
- Calendar page: Quick-log instances

### 8. Search Integration

**File: `lib/Helper/backend/backend.dart` or search utility**

- Include essential templates in global search
- Filter by `categoryType: 'essential'`
- Display with "essential" badge in results

## Key Technical Decisions

1. **No new collections**: Use existing `ActivityRecord` (templates) and `ActivityInstanceRecord` (instances) with `categoryType: 'essential'`

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

- `lib/Helper/backend/essential_service.dart`
- `lib/Helper/utils/essential_template_dialog.dart`
- `lib/Helper/utils/time_log_dialog.dart`
- `lib/Screens/essential/essential_templates_page.dart`

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

- [ ] Create Essential Template (e.g., "Sleep")
- [ ] Log time instance from calendar
- [ ] Verify no points awarded
- [ ] Verify excluded from daily progress %
- [ ] Add to sequence and verify it appears
- [ ] Create instance from sequence
- [ ] Verify calendar displays time blocks correctly
- [ ] Edit/delete templates
- [ ] Search for Essential Activities in sequence builder