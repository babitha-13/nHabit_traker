import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';

class TaskBucketingLogicHelper {
  static Map<String, List<dynamic>> getBucketedItems({
    required List<ActivityInstanceRecord> taskInstances,
    required String searchQuery,
    required int completionTimeFrame,
    required String? categoryName,
    Map<String, List<dynamic>>? cachedBucketedItems,
    int? taskInstancesHashCode,
    String? lastSearchQuery,
    int? lastCompletionTimeFrame,
    String? lastCategoryName,
    required Function(Set<String>) onExpandedSectionsUpdate,
    Set<String> expandedSections = const {},
  }) {
    // Cache validity is already checked by caller using taskInstancesHashCode
    // No need to recalculate hash here - rely on hash passed from caller
    final cacheInvalid = cachedBucketedItems == null ||
        taskInstancesHashCode == null ||
        searchQuery != (lastSearchQuery ?? '') ||
        completionTimeFrame != (lastCompletionTimeFrame ?? 2) ||
        categoryName != lastCategoryName;

    if (!cacheInvalid && cachedBucketedItems != null) {
      return cachedBucketedItems;
    }

    // Recalculate buckets
    final Map<String, List<dynamic>> buckets = {
      'Overdue': [],
      'Today': [],
      'Tomorrow': [],
      'This Week': [],
      'Later': [],
      'No due date': [],
      'Recent Completions': [],
    };

    // Filter instances by search query if active
    final activeInstancesToProcess = taskInstances
        .where((inst) => inst.status == 'pending')
        .where((instance) {
      if (searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
    }).toList();

    print(
        '_bucketedItems: Processing ${activeInstancesToProcess.length} active task instances (search: "$searchQuery")');

    final today = DateService.todayStart;
    final tomorrow = DateService.tomorrowStart;
    final thisWeekEnd = tomorrow.add(const Duration(days: 5));

    // Group recurring tasks by templateId to show only earliest pending instance
    final Map<String, List<ActivityInstanceRecord>> recurringTasksByTemplate =
        {};
    final List<ActivityInstanceRecord> oneOffTasks = [];

    for (final instance in activeInstancesToProcess) {
      if (!instance.isActive) {
        continue;
      }
      if (categoryName != null &&
          instance.templateCategoryName != categoryName) {
        continue;
      }
      if (instance.templateIsRecurring) {
        final templateId = instance.templateId;
        (recurringTasksByTemplate[templateId] ??= []).add(instance);
      } else {
        oneOffTasks.add(instance);
      }
    }

    // Process one-off tasks normally
    for (final instance in oneOffTasks) {
      final dueDate = instance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(instance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(instance);
      } else if (isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(instance);
      } else if (isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(instance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(instance);
      } else {
        buckets['Later']!.add(instance);
      }
    }

    // Process recurring tasks - show only earliest pending instance per template
    for (final templateId in recurringTasksByTemplate.keys) {
      final instances = recurringTasksByTemplate[templateId]!;
      instances.sort((a, b) {
        if (a.dueDate == null && b.dueDate == null) return 0;
        if (a.dueDate == null) return 1;
        if (b.dueDate == null) return -1;
        return a.dueDate!.compareTo(b.dueDate!);
      });
      final earliestInstance = instances.first;
      print(
          '  Processing recurring task: ${earliestInstance.templateName} (earliest of ${instances.length} instances)');
      final dueDate = earliestInstance.dueDate;
      if (dueDate == null) {
        buckets['No due date']!.add(earliestInstance);
        continue;
      }
      final instanceDueDate =
          DateTime(dueDate.year, dueDate.month, dueDate.day);
      if (instanceDueDate.isBefore(today)) {
        buckets['Overdue']!.add(earliestInstance);
      } else if (isSameDay(instanceDueDate, today)) {
        buckets['Today']!.add(earliestInstance);
      } else if (isSameDay(instanceDueDate, tomorrow)) {
        buckets['Tomorrow']!.add(earliestInstance);
      } else if (instanceDueDate.isAfter(tomorrow) &&
          !instanceDueDate.isAfter(thisWeekEnd)) {
        buckets['This Week']!.add(earliestInstance);
      } else {
        buckets['Later']!.add(earliestInstance);
      }
    }

    // Populate Recent Completions with unified time window logic
    final completionCutoff =
        DateService.todayStart.subtract(Duration(days: completionTimeFrame));
    final allInstancesToProcess = taskInstances.where((instance) {
      if (searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
    }).toList();

    // Group completed instances by template for recurring tasks
    final Map<String, List<ActivityInstanceRecord>>
        completedRecurringByTemplate = {};
    final List<ActivityInstanceRecord> completedOneOffTasks = [];

    for (final instance in allInstancesToProcess) {
      if (instance.status != 'completed') continue;
      if (instance.completedAt == null) continue;
      if (categoryName != null &&
          instance.templateCategoryName != categoryName) {
        continue;
      }
      final completedDate = instance.completedAt!;
      final completedDateOnly =
          DateTime(completedDate.year, completedDate.month, completedDate.day);
      if (completedDateOnly.isAfter(completionCutoff) ||
          completedDateOnly.isAtSameMomentAs(completionCutoff)) {
        if (instance.templateIsRecurring) {
          final templateId = instance.templateId;
          (completedRecurringByTemplate[templateId] ??= []).add(instance);
        } else {
          completedOneOffTasks.add(instance);
        }
      }
    }

    // Add all completed instances of recurring tasks within time window
    for (final templateId in completedRecurringByTemplate.keys) {
      final instances = completedRecurringByTemplate[templateId]!;
      instances.sort((a, b) => b.completedAt!.compareTo(a.completedAt!));
      for (final instance in instances) {
        buckets['Recent Completions']!.add(instance);
        print(
            '  Added completed recurring task: ${instance.templateName} (completed: ${instance.completedAt})');
      }
    }

    // Add all completed one-off tasks within time window
    for (final instance in completedOneOffTasks) {
      buckets['Recent Completions']!.add(instance);
    }

    // Sort items within each bucket by tasks order
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        final typedItems = items.cast<ActivityInstanceRecord>();
        buckets[key] =
            InstanceOrderService.sortInstancesByOrder(typedItems, 'tasks');
      }
    }

    // Auto-expand sections with search results
    if (searchQuery.isNotEmpty) {
      final newExpandedSections = Set<String>.from(expandedSections);
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          newExpandedSections.add(key);
        }
      }
      onExpandedSectionsUpdate(newExpandedSections);
    }

    return buckets;
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
