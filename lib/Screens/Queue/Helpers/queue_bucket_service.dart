import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_state_manager.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_sort_state_manager.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/Backend/instance_order_service.dart';
import 'package:habit_tracker/Screens/Queue/Helpers/queue_utils.dart';

/// Service class for bucketing queue items
class QueueBucketService {
  /// Calculate hash code for instances
  static int calculateInstancesHash(List<ActivityInstanceRecord> instances) {
    return instances.length.hashCode ^
        instances.fold(0, (sum, inst) {
          final idHash = inst.reference.id.hashCode;
          final valueHash = inst.currentValue.hashCode;
          final updatedHash = inst.lastUpdated?.hashCode ?? 0;
          final statusHash = inst.status.hashCode;
          return sum ^ idHash ^ valueHash ^ updatedHash ^ statusHash;
        });
  }

  /// Calculate hash code for categories
  static int calculateCategoriesHash(List<CategoryRecord> categories) {
    return categories.length.hashCode ^
        categories.fold(0, (sum, cat) => sum ^ cat.reference.id.hashCode);
  }

  /// Bucket instances into categories (Overdue, Pending, Completed, Skipped/Snoozed)
  static Map<String, List<ActivityInstanceRecord>> bucketItems({
    required List<ActivityInstanceRecord> instances,
    required List<CategoryRecord> categories,
    required QueueFilterState currentFilter,
    required QueueSortState currentSort,
    required Set<String> expandedSections,
    required String searchQuery,
    required bool isDefaultFilterState,
  }) {
    // Recalculate buckets
    final Map<String, List<ActivityInstanceRecord>> buckets = {
      'Overdue': [],
      'Pending': [],
      'Completed': [],
      'Skipped/Snoozed': [],
    };
    final today = QueueUtils.todayDate();

    // Apply filters first
    final filteredInstances = QueueUtils.applyFilters(
      instances,
      currentFilter,
      isDefaultFilterState,
    );

    // Filter instances by search query if active
    final instancesToProcess = filteredInstances.where((instance) {
      if (searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(searchQuery.toLowerCase());
    }).toList();

    for (final instance in instancesToProcess) {
      // Don't skip completed/skipped instances here - they'll be handled in the Completed/Skipped section
      if (QueueUtils.isInstanceCompleted(instance)) {
        continue;
      }
      // Skip snoozed instances from main processing (they'll be handled in Completed/Skipped section)
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        continue;
      }
      final dueDate = instance.dueDate;
      if (dueDate == null) {
        // Skip instances without due dates (no "Later" section)
        continue;
      }
      final dateOnly = DateTime(dueDate.year, dueDate.month, dueDate.day);
      // OVERDUE: Only tasks that are overdue
      if (dateOnly.isBefore(today) && instance.templateCategoryType == 'task') {
        buckets['Overdue']!.add(instance);
      }
      // PENDING: Both habits and tasks for today
      else if (QueueUtils.isTodayOrOverdue(instance)) {
        buckets['Pending']!.add(instance);
      }
      // Skip anything beyond today (no "Later" section)
    }

    // Populate Completed bucket (completed TODAY only)
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    for (final instance in instancesToProcess) {
      if (instance.status == 'completed') {
        if (instance.completedAt == null) {
          continue;
        }
        final completedAt = instance.completedAt!;
        final completedDateOnly =
            DateTime(completedAt.year, completedAt.month, completedAt.day);
        final isToday = completedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Completed']!.add(instance);
        }
      }
    }

    // Populate Skipped/Snoozed bucket (skipped TODAY or currently snoozed)
    for (final instance in instancesToProcess) {
      // For skipped items, check skipped date
      if (instance.status == 'skipped') {
        if (instance.skippedAt == null) {
          continue;
        }
        final skippedAt = instance.skippedAt!;
        final skippedDateOnly =
            DateTime(skippedAt.year, skippedAt.month, skippedAt.day);
        final isToday = skippedDateOnly.isAtSameMomentAs(todayStart);
        if (isToday) {
          buckets['Skipped/Snoozed']!.add(instance);
        }
      }
    }

    // Add snoozed instances to Skipped/Snoozed section (only if due today)
    for (final instance in instancesToProcess) {
      if (instance.snoozedUntil != null &&
          DateTime.now().isBefore(instance.snoozedUntil!)) {
        // Only show snoozed items if their original due date was today
        final dueDate = instance.dueDate;
        if (dueDate != null) {
          final dueDateOnly =
              DateTime(dueDate.year, dueDate.month, dueDate.day);
          if (dueDateOnly.isAtSameMomentAs(todayStart)) {
            buckets['Skipped/Snoozed']!.add(instance);
          }
        }
      }
    }

    // Sort items within each bucket
    for (final key in buckets.keys) {
      final items = buckets[key]!;
      if (items.isNotEmpty) {
        // Apply sort if active, otherwise use queue order
        if (currentSort.isActive && expandedSections.contains(key)) {
          buckets[key] = QueueUtils.sortSectionItems(
            items,
            key,
            expandedSections,
            currentSort,
            categories,
          );
        } else {
          // Sort by queue order (manual order)
          buckets[key] =
              InstanceOrderService.sortInstancesByOrder(items, 'queue');
        }
      }
    }

    // Auto-expand sections with search results
    if (searchQuery.isNotEmpty) {
      for (final key in buckets.keys) {
        if (buckets[key]!.isNotEmpty) {
          expandedSections.add(key);
        }
      }
    }

    return buckets;
  }
}
