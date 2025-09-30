# Task Instance System - Implementation Guide

## Overview

This system implements a Microsoft To-Do style recurring task management system that separates **Templates** (your current tasks/habits) from **Instances** (individual occurrences). This ensures users only see current/overdue tasks, with new instances generated automatically when tasks are completed or skipped.

## Architecture

### Core Components

1. **TaskRecord & HabitRecord** - Templates that define recurring patterns
2. **TaskInstanceRecord & HabitInstanceRecord** - Individual occurrences with due dates
3. **TaskInstanceService** - Core business logic for instance management
4. **Backend functions** - Integration layer for UI components

### Key Benefits

- ✅ Only current/overdue tasks shown to users
- ✅ Automatic next instance generation on completion/skip
- ✅ Proper handling of daily, weekly, and monthly recurrence
- ✅ Support for specific days (e.g., Mon, Wed, Fri)
- ✅ Maintains existing UI compatibility
- ✅ Clean separation of concerns

## Database Structure

### Collections

```
users/{userId}/tasks/          # Task templates (existing)
users/{userId}/habits/         # Habit templates (existing)
users/{userId}/task_instances/ # NEW: Task instances
users/{userId}/habit_instances/# NEW: Habit instances
```

### Instance Fields

```dart
// Common fields for both task and habit instances
{
  templateId: String,           // Reference to template
  dueDate: DateTime,           // When this instance is due
  status: String,              // 'pending', 'completed', 'skipped'
  completedAt: DateTime?,      // When completed
  skippedAt: DateTime?,        // When skipped
  currentValue: dynamic,       // Progress for quantity/duration
  accumulatedTime: int,        // Timer duration in milliseconds
  
  // Cached template data for performance
  templateName: String,
  templateCategoryId: String,
  templateCategoryName: String,
  templatePriority: int,
  templateTrackingType: String,
  templateTarget: dynamic,
  templateUnit: String,
}
```

## Usage Guide

### 1. Querying Today's Tasks/Habits

**OLD WAY (Templates):**
```dart
final tasks = await queryTasksRecordOnce(userId: userId);
final habits = await queryHabitsRecordOnce(userId: userId);
```

**NEW WAY (Instances):**
```dart
final taskInstances = await queryTodaysTaskInstances(userId: userId);
final habitInstances = await queryTodaysHabitInstances(userId: userId);
```

### 2. Creating Tasks/Habits

The system automatically creates initial instances:

```dart
// Create a recurring task
await createTask(
  title: 'Daily Exercise',
  isRecurring: true,
  schedule: 'daily',
  frequency: 1,
);

// Create a weekly task with specific days
await createTask(
  title: 'Team Meeting',
  isRecurring: true,
  schedule: 'weekly',
  specificDays: [1, 3, 5], // Mon, Wed, Fri
);

// Create a habit (always recurring)
await createHabit(
  name: 'Drink Water',
  schedule: 'daily',
  frequency: 1,
);
```

### 3. Completing/Skipping Instances

```dart
// Complete a task instance
await completeTaskInstance(
  instanceId: instance.reference.id,
  finalValue: 100, // For quantity tracking
  notes: 'Completed successfully',
);

// Skip a habit instance
await skipHabitInstance(
  instanceId: instance.reference.id,
  notes: 'Skipped due to illness',
);
```

### 4. Progress Tracking

```dart
// Update progress during the day
await updateInstanceProgress(
  instanceId: instance.reference.id,
  instanceType: 'task', // or 'habit'
  currentValue: 50, // Current progress
  accumulatedTime: 1800000, // 30 minutes in milliseconds
);
```

## Recurrence Logic

### Daily Tasks
- **Daily (frequency=1)**: Next day
- **Every 3 days**: 3 days from completion

### Weekly Tasks
- **Weekly (frequency=1)**: Same day next week
- **3 times per week**: Next occurrence based on `specificDays`
- **Specific days**: Mon=1, Tue=2, ..., Sun=7

### Monthly Tasks
- **Monthly (frequency=1)**: Same date next month
- **Every 3 months**: 3 months from completion
- **Edge cases**: Jan 31 → Feb 28 (last day of month)

## Migration

### Automatic Migration

For new tasks/habits, instances are created automatically. For existing data:

```dart
// Run once to migrate existing data
final result = await migrateToInstanceSystem();
print('Migrated: ${result['tasks']} tasks, ${result['habits']} habits');
```

### Manual Migration

If you need more control:

```dart
// Migrate specific task
final task = await TaskRecord.getDocumentOnce(taskRef);
await TaskInstanceService.initializeTaskInstances(
  templateId: taskRef.id,
  template: task,
);
```

## UI Integration Examples

### 1. Display Today's Tasks

```dart
class TodayTasksList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskInstanceRecord>>(
      future: queryTodaysTaskInstances(userId: currentUserId),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final instances = snapshot.data!;
        return ListView.builder(
          itemCount: instances.length,
          itemBuilder: (context, index) {
            final instance = instances[index];
            return TaskInstanceTile(instance: instance);
          },
        );
      },
    );
  }
}
```

### 2. Task Instance Tile

```dart
class TaskInstanceTile extends StatelessWidget {
  final TaskInstanceRecord instance;
  
  const TaskInstanceTile({required this.instance});
  
  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(instance.templateName),
      subtitle: Text('Due: ${instance.dueDate?.toString()}'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.check),
            onPressed: () => _completeInstance(),
          ),
          IconButton(
            icon: Icon(Icons.skip_next),
            onPressed: () => _skipInstance(),
          ),
        ],
      ),
    );
  }
  
  void _completeInstance() async {
    await completeTaskInstance(
      instanceId: instance.reference.id,
    );
    // Refresh UI
  }
  
  void _skipInstance() async {
    await skipTaskInstance(
      instanceId: instance.reference.id,
    );
    // Refresh UI
  }
}
```

### 3. Progress Tracking

```dart
class ProgressTracker extends StatefulWidget {
  final TaskInstanceRecord instance;
  
  @override
  _ProgressTrackerState createState() => _ProgressTrackerState();
}

class _ProgressTrackerState extends State<ProgressTracker> {
  double _currentValue = 0;
  
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Slider(
          value: _currentValue,
          max: widget.instance.templateTarget?.toDouble() ?? 100,
          onChanged: (value) {
            setState(() => _currentValue = value);
            _updateProgress(value);
          },
        ),
        Text('${_currentValue.toInt()} / ${widget.instance.templateTarget}'),
      ],
    );
  }
  
  void _updateProgress(double value) async {
    await updateInstanceProgress(
      instanceId: widget.instance.reference.id,
      instanceType: 'task',
      currentValue: value,
    );
  }
}
```

## Best Practices

### 1. Error Handling
Always wrap instance operations in try-catch blocks:

```dart
try {
  await completeTaskInstance(instanceId: id);
} catch (e) {
  print('Error completing task: $e');
  // Show user-friendly error message
}
```

### 2. Performance
- Use cached template data in instances for quick access
- Query only today's instances, not all instances
- Implement proper pagination for large datasets

### 3. Data Consistency
- Always update both template and instances when needed
- Use transactions for critical operations
- Implement proper cleanup when deleting templates

### 4. Testing
- Test recurrence logic with edge cases (month boundaries, leap years)
- Test timezone handling
- Test migration with existing data

## Troubleshooting

### Common Issues

1. **No instances showing**: Check if migration was run
2. **Wrong recurrence**: Verify schedule and frequency settings
3. **Performance issues**: Ensure proper indexing on `dueDate` and `status`
4. **Data inconsistency**: Run cleanup functions periodically

### Debug Queries

```dart
// Check if instances exist for a template
final instances = await TaskInstanceRecord.collectionForUser(userId)
    .where('templateId', isEqualTo: templateId)
    .get();

// Check overdue instances
final overdue = await TaskInstanceRecord.collectionForUser(userId)
    .where('dueDate', isLessThan: DateTime.now())
    .where('status', isEqualTo: 'pending')
    .get();
```

## Future Enhancements

1. **Batch Operations**: Complete multiple instances at once
2. **Smart Scheduling**: AI-powered optimal scheduling
3. **Dependency Management**: Task dependencies and sequences
4. **Advanced Recurrence**: Custom patterns, holidays, etc.
5. **Analytics**: Completion rates, streak tracking
6. **Sync**: Cross-device synchronization
7. **Offline Support**: Local storage with sync

---

This system provides a solid foundation for Microsoft To-Do style task management while maintaining compatibility with your existing codebase. The separation of templates and instances ensures scalability and proper user experience.
