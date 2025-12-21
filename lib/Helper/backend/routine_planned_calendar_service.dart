import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/time_logging_preferences_service.dart';

class PlannedRoutineEvent {
  final String routineId;
  final String name;
  final String dueTime; // "HH:mm"
  final int? durationMinutes; // null => marker line

  const PlannedRoutineEvent({
    required this.routineId,
    required this.name,
    required this.dueTime,
    required this.durationMinutes,
  });
}

/// Business logic for showing routines on the Planned calendar.
///
/// - Only routines with a dueTime are eligible.
/// - Routines occur on a date based on their frequency fields (or daily if unset).
/// - Duration is the sum of item durations (time-target or estimates), excluding items
///   that are explicitly scheduled elsewhere (have their own due time that day).
/// - If total duration is 0/unknown, durationMinutes is null (render as marker line).
class RoutinePlannedCalendarService {
  static bool occursOnDate(RoutineRecord routine, DateTime date) {
    // If not configured, treat as daily (user explicitly set a start time).
    final frequencyType = routine.reminderFrequencyType;
    if (frequencyType.isEmpty) return true;

    final dateOnly = DateTime(date.year, date.month, date.day);

    if (frequencyType == 'specific_days') {
      if (routine.specificDays.isEmpty) return true;
      return routine.specificDays.contains(dateOnly.weekday);
    }

    if (frequencyType == 'every_x') {
      final everyXValue = routine.everyXValue <= 0 ? 1 : routine.everyXValue;
      final periodType = routine.everyXPeriodType.isEmpty
          ? 'day'
          : routine.everyXPeriodType;

      // Treat "every 1 week" as daily (matches reminder scheduler behavior).
      if (periodType == 'week' && everyXValue == 1) return true;
      if (periodType == 'day' && everyXValue == 1) return true;

      final anchorRaw = routine.createdTime ?? DateTime.now();
      final anchor = DateTime(anchorRaw.year, anchorRaw.month, anchorRaw.day);

      final diffDays = dateOnly.difference(anchor).inDays;
      if (diffDays < 0) return false;

      switch (periodType) {
        case 'day':
          return diffDays % everyXValue == 0;
        case 'week':
          return diffDays % (everyXValue * 7) == 0;
        case 'month':
          // Match scheduler's "month ~= 30 days" approximation.
          return diffDays % (everyXValue * 30) == 0;
        default:
          return diffDays % everyXValue == 0;
      }
    }

    // Unknown config -> show daily to avoid "disappearing" routines.
    return true;
  }

  static Future<List<PlannedRoutineEvent>> getPlannedRoutineEvents({
    required String userId,
    required DateTime date,
    required List<RoutineRecord> routines,
    required Set<String> excludedTemplateIds,
  }) async {
    final eligible = routines
        .where((r) => r.hasDueTime() && (r.dueTime?.isNotEmpty ?? false))
        .where((r) => occursOnDate(r, date))
        .toList();

    if (eligible.isEmpty) return const [];

    final prefs = await TimeLoggingPreferencesService.getPreferences(userId);

    // If global default estimates are off and items aren't time-target, duration may become 0/null.
    final enableDefaultEstimates = prefs.enableDefaultEstimates;
    final enableActivityEstimates = prefs.enableActivityEstimates;

    // Collect template ids needed across all eligible routines (excluding already scheduled items).
    final allNeededItemIds = <String>{};
    for (final routine in eligible) {
      for (final itemId in routine.itemIds) {
        if (excludedTemplateIds.contains(itemId)) continue;
        allNeededItemIds.add(itemId);
      }
    }

    final templatesById = await _fetchTemplatesById(
      userId: userId,
      templateIds: allNeededItemIds.toList(),
    );

    int? durationForTemplate(ActivityRecord template) {
      // Time-target activities: duration is target minutes.
      final targetMinutes = _targetMinutesForTimeTracking(
        trackingType: template.trackingType,
        target: template.target,
      );
      if (targetMinutes != null) return targetMinutes;

      // Non-time-target:
      if (!enableDefaultEstimates) return null;

      if (enableActivityEstimates && template.hasTimeEstimateMinutes()) {
        return template.timeEstimateMinutes!.clamp(1, 600);
      }

      return prefs.defaultDurationMinutes;
    }

    final out = <PlannedRoutineEvent>[];
    for (final routine in eligible) {
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
        PlannedRoutineEvent(
          routineId: routine.reference.id,
          name: routine.name,
          dueTime: routine.dueTime!,
          durationMinutes: totalMinutes > 0 ? totalMinutes : null,
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

    // Firestore whereIn limit is 10
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
}


