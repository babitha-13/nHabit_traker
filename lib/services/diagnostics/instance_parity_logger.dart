import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/config/instance_repository_flags.dart';

class InstanceParityLogger {
  const InstanceParityLogger._();

  static bool get _enabled =>
      kDebugMode && InstanceRepositoryFlags.enableParityChecks;

  static void logQueueParity({
    required List<ActivityInstanceRecord> legacy,
    required List<ActivityInstanceRecord> repo,
  }) {
    _logListParity(
      scope: 'queue',
      legacy: legacy,
      repo: repo,
    );
  }

  static void logTaskParity({
    required List<ActivityInstanceRecord> legacy,
    required List<ActivityInstanceRecord> repo,
  }) {
    _logListParity(
      scope: 'tasks',
      legacy: legacy,
      repo: repo,
    );
  }

  static void logHabitParity({
    required String scope,
    required List<ActivityInstanceRecord> legacy,
    required List<ActivityInstanceRecord> repo,
  }) {
    _logListParity(
      scope: scope,
      legacy: legacy,
      repo: repo,
    );
  }

  static void logRoutineParity({
    required Map<String, ActivityInstanceRecord> legacy,
    required Map<String, ActivityInstanceRecord> repo,
  }) {
    if (!_enabled) return;
    final legacySignatures = _mapSignatures(legacy);
    final repoSignatures = _mapSignatures(repo);
    if (mapEquals(legacySignatures, repoSignatures)) {
      return;
    }
    print(
      '[instance-parity][routine] mismatch: legacy=${legacySignatures.length}, repo=${repoSignatures.length}',
    );
    print(
      '[instance-parity][routine] missingInRepo=${_diffKeys(legacySignatures, repoSignatures)}, missingInLegacy=${_diffKeys(repoSignatures, legacySignatures)}',
    );
  }

  static void logEssentialStatsParity({
    required Map<String, int> legacyCounts,
    required Map<String, int> legacyMinutes,
    required Map<String, Map<String, int>> repo,
  }) {
    if (!_enabled) return;
    final repoCounts = <String, int>{};
    final repoMinutes = <String, int>{};
    repo.forEach((templateId, stats) {
      repoCounts[templateId] = stats['count'] ?? 0;
      repoMinutes[templateId] = stats['minutes'] ?? 0;
    });
    final countsMatch = mapEquals(legacyCounts, repoCounts);
    final minutesMatch = mapEquals(legacyMinutes, repoMinutes);
    if (countsMatch && minutesMatch) {
      return;
    }
    print(
      '[instance-parity][essential] mismatch: countsMatch=$countsMatch, minutesMatch=$minutesMatch',
    );
    print(
      '[instance-parity][essential] legacyCounts=${legacyCounts.length}, repoCounts=${repoCounts.length}',
    );
    print(
      '[instance-parity][essential] legacyMinutes=${legacyMinutes.length}, repoMinutes=${repoMinutes.length}',
    );
  }

  static void logCalendarParity({
    required List<ActivityInstanceRecord> legacyPlanned,
    required List<ActivityInstanceRecord> repoPlanned,
    required List<ActivityInstanceRecord> legacyCompleted,
    required List<ActivityInstanceRecord> repoCompleted,
  }) {
    if (!_enabled) return;
    _logListParity(
      scope: 'calendar_today_planned',
      legacy: legacyPlanned,
      repo: repoPlanned,
    );
    _logListParity(
      scope: 'calendar_today_completed',
      legacy: legacyCompleted,
      repo: repoCompleted,
    );
  }

  static void _logListParity({
    required String scope,
    required List<ActivityInstanceRecord> legacy,
    required List<ActivityInstanceRecord> repo,
  }) {
    if (!_enabled) return;
    final legacySignatures = _listSignatures(legacy);
    final repoSignatures = _listSignatures(repo);
    if (setEquals(legacySignatures, repoSignatures)) {
      return;
    }
    print(
      '[instance-parity][$scope] mismatch: legacy=${legacySignatures.length}, repo=${repoSignatures.length}',
    );
    print(
      '[instance-parity][$scope] missingInRepo=${_diffSet(legacySignatures, repoSignatures)}, missingInLegacy=${_diffSet(repoSignatures, legacySignatures)}',
    );
  }

  static Set<String> _listSignatures(List<ActivityInstanceRecord> list) {
    return list
        .map((i) => '${i.reference.id}:${i.status}:${i.templateCategoryType}')
        .toSet();
  }

  static Map<String, String> _mapSignatures(
    Map<String, ActivityInstanceRecord> map,
  ) {
    final signatures = <String, String>{};
    map.forEach((key, value) {
      signatures[key] =
          '${value.reference.id}:${value.status}:${value.templateCategoryType}';
    });
    return signatures;
  }

  static List<String> _diffSet(Set<String> a, Set<String> b) {
    return a.where((item) => !b.contains(item)).take(12).toList();
  }

  static List<String> _diffKeys(Map<String, String> a, Map<String, String> b) {
    return a.keys.where((key) => !b.containsKey(key)).take(12).toList();
  }
}
