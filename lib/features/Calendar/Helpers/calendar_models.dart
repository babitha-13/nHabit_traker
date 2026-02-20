import 'package:calendar_view/calendar_view.dart';

class CalendarEventMetadata {
  final String instanceId;
  final int sessionIndex; // Index in timeLogSessions array
  final int? sessionStartEpochMs;
  final int? sessionEndEpochMs;
  final int? sessionLoggedAtEpochMs;
  final String activityName;
  final String activityType; // 'task', 'habit', 'essential'
  final String? templateId;
  final String? categoryId;
  final String? categoryName;
  final String? categoryColorHex;

  CalendarEventMetadata({
    required this.instanceId,
    required this.sessionIndex,
    this.sessionStartEpochMs,
    this.sessionEndEpochMs,
    this.sessionLoggedAtEpochMs,
    required this.activityName,
    required this.activityType,
    this.templateId,
    this.categoryId,
    this.categoryName,
    this.categoryColorHex,
  });

  Map<String, dynamic> toMap() {
    return {
      'instanceId': instanceId,
      'sessionIndex': sessionIndex,
      'sessionStartEpochMs': sessionStartEpochMs,
      'sessionEndEpochMs': sessionEndEpochMs,
      'sessionLoggedAtEpochMs': sessionLoggedAtEpochMs,
      'activityName': activityName,
      'activityType': activityType,
      'templateId': templateId,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'categoryColorHex': categoryColorHex,
    };
  }

  static CalendarEventMetadata? fromMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      final rawSessionIndex = data['sessionIndex'];
      final rawSessionStart = data['sessionStartEpochMs'];
      final rawSessionEnd = data['sessionEndEpochMs'];
      final rawSessionLoggedAt = data['sessionLoggedAtEpochMs'];
      return CalendarEventMetadata(
        instanceId: data['instanceId'] as String,
        sessionIndex: rawSessionIndex is num ? rawSessionIndex.toInt() : -1,
        sessionStartEpochMs:
            rawSessionStart is num ? rawSessionStart.toInt() : null,
        sessionEndEpochMs: rawSessionEnd is num ? rawSessionEnd.toInt() : null,
        sessionLoggedAtEpochMs:
            rawSessionLoggedAt is num ? rawSessionLoggedAt.toInt() : null,
        activityName: data['activityName'] as String,
        activityType: data['activityType'] as String,
        templateId: data['templateId'] as String?,
        categoryId: data['categoryId'] as String?,
        categoryName: data['categoryName'] as String?,
        categoryColorHex: data['categoryColorHex'] as String?,
      );
    }
    return null;
  }
}

class PlannedOverlapGroup {
  final DateTime start;
  final DateTime end;
  final List<CalendarEventData> events;

  const PlannedOverlapGroup({
    required this.start,
    required this.end,
    required this.events,
  });
}

class PlannedOverlapInfo {
  final int pairCount;
  final Set<String> overlappedIds;
  final List<PlannedOverlapGroup> groups;

  const PlannedOverlapInfo({
    required this.pairCount,
    required this.overlappedIds,
    required this.groups,
  });
}
