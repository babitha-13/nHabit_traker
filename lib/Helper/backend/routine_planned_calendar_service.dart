import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';

class PlannedCalendarEvent {
  final String? routineId;
  final String? activityId;
  final String name;
  final String dueTime; // "HH:mm"
  final int? durationMinutes; // null => marker line

  const PlannedCalendarEvent({
    this.routineId,
    this.activityId,
    required this.name,
    required this.dueTime,
    required this.durationMinutes,
  });
}

/// Business logic for showing routines and essential activities on the Planned calendar.
///
/// - Only items with a dueTime are eligible.
/// - Items occur on a date based on their frequency fields (or daily if unset).
/// - Duration for routines is the sum of item durations.
/// - Duration for activities is their time-target or estimate.
class RoutinePlannedCalendarService {
  static bool occursOnDate({
    required String frequencyType,
    required List<int> specificDays,
    required int everyXValue,
    required String everyXPeriodType,
    required DateTime? createdTime,
    required DateTime date,
  }) {
    if (frequencyType.isEmpty) return true;
    if (frequencyType == 'daily') return true;

    final dateOnly = DateTime(date.year, date.month, date.day);

    if (frequencyType == 'specific_days') {
      if (specificDays.isEmpty) return true;
      return specificDays.contains(dateOnly.weekday);
    }

    if (frequencyType == 'every_x') {
      final xValue = everyXValue <= 0 ? 1 : everyXValue;
      final periodType = everyXPeriodType.isEmpty ? 'day' : everyXPeriodType;

      if (periodType == 'week' && xValue == 1) return true;
      if (periodType == 'day' && xValue == 1) return true;

      final anchorRaw = createdTime ?? DateTime.now();
      final anchor = DateTime(anchorRaw.year, anchorRaw.month, anchorRaw.day);

      final diffDays = dateOnly.difference(anchor).inDays;
      if (diffDays < 0) return false;

      switch (periodType) {
        case 'day':
          return diffDays % xValue == 0;
        case 'week':
          return diffDays % (xValue * 7) == 0;
        case 'month':
          return diffDays % (xValue * 30) == 0;
        default:
          return diffDays % xValue == 0;
      }
    }

    return true;
  }

  static Future<List<PlannedCalendarEvent>> getPlannedRoutineEvents({
    required String userId,
    required DateTime date,
    required List<RoutineRecord> routines,
    required Set<String> excludedTemplateIds,
  }) async {
    final prefs = await TimeLoggingPreferencesService.getPreferences(userId);
    final enableDefaultEstimates = prefs.enableDefaultEstimates;

    // 1. Filter routines for today
    final eligibleRoutines = routines
        .where((r) => r.hasDueTime() && (r.dueTime?.isNotEmpty ?? false))
        .where((r) => occursOnDate(
              frequencyType: r.reminderFrequencyType,
              specificDays: r.specificDays,
              everyXValue: r.everyXValue,
              everyXPeriodType: r.everyXPeriodType,
              createdTime: r.createdTime,
              date: date,
            ))
        .toList();

    // 2. Fetch essential activities with schedules
    final npActivities = await ActivityRecord.collectionForUser(userId)
        .where('categoryType', isEqualTo: 'essential')
        .where('isActive', isEqualTo: true)
        .get();

    final eligibleActivities = npActivities.docs
        .map((doc) => ActivityRecord.fromSnapshot(doc))
        .where((a) => a.hasDueTime() && (a.dueTime?.isNotEmpty ?? false))
        .where((a) => occursOnDate(
              frequencyType: a.frequencyType,
              specificDays: a.specificDays,
              everyXValue: a.everyXValue,
              everyXPeriodType: a.everyXPeriodType,
              createdTime: a.createdTime,
              date: date,
            ))
        .toList();

    // Collect all template IDs needed for duration calculation
    final allNeededItemIds = <String>{};
    for (final routine in eligibleRoutines) {
      for (final itemId in routine.itemIds) {
        if (excludedTemplateIds.contains(itemId)) continue;
        allNeededItemIds.add(itemId);
      }
    }
    // Also add standalone activities if not already in routines
    for (final activity in eligibleActivities) {
      allNeededItemIds.add(activity.reference.id);
    }

    final templatesById = await _fetchTemplatesById(
      userId: userId,
      templateIds: allNeededItemIds.toList(),
    );

    int? durationForTemplate(ActivityRecord template) {
      final targetMinutes = _targetMinutesForTimeTracking(
        trackingType: template.trackingType,
        target: template.target,
      );
      if (targetMinutes != null) return targetMinutes;

      if (!enableDefaultEstimates) return null;

      if (template.hasTimeEstimateMinutes()) {
        final estimate = template.timeEstimateMinutes!.clamp(1, 600);
        return _applyQuantityIncrementAdjustment(
          trackingType: template.trackingType,
          target: template.target,
          totalMinutes: estimate.toInt(),
        );
      } else {
        final minutes = prefs.defaultDurationMinutes;
        if (minutes <= 0) return null;
        return _applyQuantityIncrementAdjustment(
          trackingType: template.trackingType,
          target: template.target,
          totalMinutes: minutes,
        );
      }
    }

    final out = <PlannedCalendarEvent>[];

    // Add Routines to output
    for (final routine in eligibleRoutines) {
      int totalMinutes = 0;
      for (final itemId in routine.itemOrder.isNotEmpty
          ? routine.itemOrder
          : routine.itemIds) {
        if (excludedTemplateIds.contains(itemId)) continue;
        final template = templatesById[itemId];
        if (template == null) continue;
        final minutes = durationForTemplate(template);
        if (minutes != null && minutes > 0) {
          totalMinutes += minutes;
        }
      }

      out.add(
        PlannedCalendarEvent(
          routineId: routine.reference.id,
          name: routine.name,
          dueTime: routine.dueTime!,
          durationMinutes: totalMinutes > 0 ? totalMinutes : null,
        ),
      );
    }

    // Add Standalone Activities to output
    // Only if they aren't already part of an eligible routine for today
    final routineItemIdsToday =
        eligibleRoutines.expand((r) => r.itemIds).toSet();

    for (final activity in eligibleActivities) {
      if (routineItemIdsToday.contains(activity.reference.id)) continue;

      final minutes = durationForTemplate(activity);
      out.add(
        PlannedCalendarEvent(
          activityId: activity.reference.id,
          name: activity.name,
          dueTime: activity.dueTime!,
          durationMinutes: minutes != null && minutes > 0 ? minutes : null,
        ),
      );
    }

    return out;
  }

  static int? _targetMinutesForTimeTracking({
    required String trackingType,
    required dynamic target,
  }) {
    if (trackingType != 'time') return null;
    if (target == null) return null;
    if (target is int) return target > 0 ? target : null;
    if (target is double) return target > 0 ? target.toInt() : null;
    if (target is String) {
      final parsed = int.tryParse(target);
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    return null;
  }

  static Future<Map<String, ActivityRecord>> _fetchTemplatesById({
    required String userId,
    required List<String> templateIds,
  }) async {
    if (templateIds.isEmpty) return {};

    final out = <String, ActivityRecord>{};
    for (int i = 0; i < templateIds.length; i += 10) {
      final batch = templateIds.skip(i).take(10).toList();
      final snap = await ActivityRecord.collectionForUser(userId)
          .where(FieldPath.documentId, whereIn: batch)
          .get();
      for (final doc in snap.docs) {
        final record = ActivityRecord.fromSnapshot(doc);
        out[doc.id] = record;
      }
    }
    return out;
  }

  static int _applyQuantityIncrementAdjustment({
    required String trackingType,
    required dynamic target,
    required int totalMinutes,
  }) {
    if (trackingType != 'quantity') return totalMinutes;
    final targetValue = _positiveNumericValue(target);
    if (targetValue == null || targetValue <= 1) return totalMinutes;
    final perIncrement = (totalMinutes / targetValue).ceil();
    return perIncrement > 0 ? perIncrement : 1;
  }

  static double? _positiveNumericValue(dynamic value) {
    if (value == null) return null;
    if (value is num) return value > 0 ? value.toDouble() : null;
    if (value is String) {
      final parsed = double.tryParse(value);
      return (parsed != null && parsed > 0) ? parsed : null;
    }
    return null;
  }
}
