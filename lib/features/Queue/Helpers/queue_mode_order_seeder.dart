import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Queue/Helpers/queue_sort_state_manager.dart';
import 'package:habit_tracker/features/Queue/Helpers/queue_utils.dart';
import 'package:habit_tracker/services/Activtity/instance_order_service.dart';

/// Seeds and resets the per-sort-mode order fields on activity instances.
///
/// Each algorithmic sort mode (`points` / `time` / `urgency`) has its own
/// integer field (`queuePointsOrder` / `queueTimeOrder` / `queueUrgencyOrder`).
/// The field is `null` until the mode is first activated; we then run the
/// algorithm once and persist `0..N-1` to the field. Manual reorders update
/// only the active mode's field, so each mode remembers its own order.
class QueueModeOrderSeeder {
  /// Map a [QueueSortType] value to the page-type key used by
  /// [InstanceOrderService] for field access.
  static String pageTypeForSortType(String sortType) {
    switch (sortType) {
      case QueueSortType.points:
        return 'queue_points';
      case QueueSortType.time:
        return 'queue_time';
      case QueueSortType.urgency:
        return 'queue_urgency';
      default:
        return 'queue';
    }
  }

  /// Algorithmic modes own a separate order field that can be seeded/reset.
  /// `none` (Manual) is not algorithmic — it just uses `queueOrder`.
  static bool isAlgorithmic(String sortType) =>
      sortType == QueueSortType.points ||
      sortType == QueueSortType.time ||
      sortType == QueueSortType.urgency;

  /// Returns instances that participate in the queue page (active tasks/habits).
  /// Mirrors the filter at [queue_bucket_service.dart:55-65] but ignores
  /// search/filter UI state — seeding covers every queue-eligible item.
  static List<ActivityInstanceRecord> _queueEligible(
      List<ActivityInstanceRecord> instances) {
    return instances.where((instance) {
      final normalizedType = instance.templateCategoryType.trim().toLowerCase();
      final isQueueType = normalizedType == 'task' || normalizedType == 'habit';
      return isQueueType && instance.isActive;
    }).toList();
  }

  /// Whether the mode has been seeded — at least one eligible instance carries
  /// a stored order value for it.
  static bool isSeeded(
      List<ActivityInstanceRecord> instances, String sortType) {
    if (!isAlgorithmic(sortType)) return true; // 'none' uses queueOrder
    final pageType = pageTypeForSortType(sortType);
    return _queueEligible(instances)
        .any((i) => InstanceOrderService.hasOrderValue(i, pageType));
  }

  /// Run the algorithm for [sortState] across all queue-eligible instances and
  /// write 0..N-1 to that mode's order field. Skipped for non-algorithmic
  /// modes and modes that are already seeded.
  static Future<void> seedIfNeeded({
    required List<ActivityInstanceRecord> instances,
    required QueueSortState sortState,
    required List<CategoryRecord> categories,
  }) async {
    if (!isAlgorithmic(sortState.sortType)) return;
    final eligible = _queueEligible(instances);
    if (eligible.isEmpty) return;
    if (isSeeded(eligible, sortState.sortType)) return;
    await _writeAlgorithmOrder(
      instances: eligible,
      sortState: sortState,
      categories: categories,
    );
  }

  /// Re-run the algorithm and overwrite the mode's order field for every
  /// instance. Used by the explicit Reset affordance.
  static Future<void> resetMode({
    required List<ActivityInstanceRecord> instances,
    required QueueSortState sortState,
    required List<CategoryRecord> categories,
  }) async {
    if (!isAlgorithmic(sortState.sortType)) return;
    final eligible = _queueEligible(instances);
    if (eligible.isEmpty) return;
    await _writeAlgorithmOrder(
      instances: eligible,
      sortState: sortState,
      categories: categories,
    );
  }

  /// Insert a newly-created instance into every algorithmic mode's saved order
  /// at the slot the mode's algorithm would place it. Only seeds modes that
  /// have already been activated for the user — untouched modes are left
  /// `null` so their first activation can run the seeder fresh.
  static Future<void> placeNewInstance({
    required ActivityInstanceRecord newInstance,
    required List<ActivityInstanceRecord> existingInstances,
    required List<CategoryRecord> categories,
  }) async {
    final eligibleExisting = _queueEligible(existingInstances);
    if (eligibleExisting.isEmpty) return;
    for (final sortType in [
      QueueSortType.points,
      QueueSortType.time,
      QueueSortType.urgency,
    ]) {
      if (!isSeeded(eligibleExisting, sortType)) continue;
      await _insertIntoSeededMode(
        newInstance: newInstance,
        existingInstances: eligibleExisting,
        sortState: QueueSortState(sortType: sortType),
        categories: categories,
      );
    }
  }

  static Future<void> _writeAlgorithmOrder({
    required List<ActivityInstanceRecord> instances,
    required QueueSortState sortState,
    required List<CategoryRecord> categories,
  }) async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return;
    final ordered = QueueUtils.sortSectionItems(
      instances,
      'all',
      {'all'},
      sortState,
      categories,
    );
    final fieldName = InstanceOrderService.orderFieldFor(
      pageTypeForSortType(sortState.sortType),
    );
    final batch = FirebaseFirestore.instance.batch();
    for (int i = 0; i < ordered.length; i++) {
      final ref = ActivityInstanceRecord.collectionForUser(userId)
          .doc(ordered[i].reference.id);
      batch.update(ref, {fieldName: i});
    }
    await batch.commit();
  }

  /// Compute the algorithm slot for [newInstance] inside [existingInstances]
  /// under [sortState], then write/shift the field values so the new item
  /// occupies that slot and everyone below it shifts by +1.
  static Future<void> _insertIntoSeededMode({
    required ActivityInstanceRecord newInstance,
    required List<ActivityInstanceRecord> existingInstances,
    required QueueSortState sortState,
    required List<CategoryRecord> categories,
  }) async {
    final userId = await waitForCurrentUserUid();
    if (userId.isEmpty) return;
    final pageType = pageTypeForSortType(sortState.sortType);
    final fieldName = InstanceOrderService.orderFieldFor(pageType);

    // Sort existing items by their persisted order so we preserve the user's
    // manual tweaks. Use the algorithm only to decide where the new item lands
    // relative to its peers.
    final sortedExisting = List<ActivityInstanceRecord>.from(existingInstances)
      ..sort((a, b) {
        final orderA = InstanceOrderService.getOrderValue(a, pageType);
        final orderB = InstanceOrderService.getOrderValue(b, pageType);
        return orderA.compareTo(orderB);
      });

    final probe = [...sortedExisting, newInstance];
    final algorithmOrdered = QueueUtils.sortSectionItems(
      probe,
      'all',
      {'all'},
      sortState,
      categories,
    );
    final slot = algorithmOrdered
        .indexWhere((i) => i.reference.id == newInstance.reference.id);
    final insertIndex = slot < 0 ? sortedExisting.length : slot;

    final batch = FirebaseFirestore.instance.batch();
    // Shift everyone at or after the slot by +1.
    for (int i = insertIndex; i < sortedExisting.length; i++) {
      final ref = ActivityInstanceRecord.collectionForUser(userId)
          .doc(sortedExisting[i].reference.id);
      batch.update(ref, {fieldName: i + 1});
    }
    // Place the new item.
    final newRef = ActivityInstanceRecord.collectionForUser(userId)
        .doc(newInstance.reference.id);
    batch.update(newRef, {fieldName: insertIndex});
    await batch.commit();
  }
}
