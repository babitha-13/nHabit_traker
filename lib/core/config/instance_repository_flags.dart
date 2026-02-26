import 'package:flutter/foundation.dart';
import 'package:habit_tracker/services/diagnostics/fallback_read_logger.dart';

class InstanceRepositoryFlags {
  const InstanceRepositoryFlags._();

  // Migration posture (Phase 1): repository is the default path.
  // Legacy branches remain only as temporary fallback during soak.
  static const bool useRepoQueue =
      bool.fromEnvironment('USE_REPO_QUEUE', defaultValue: true);
  static const bool useRepoTasks =
      bool.fromEnvironment('USE_REPO_TASKS', defaultValue: true);
  static const bool useRepoHabits =
      bool.fromEnvironment('USE_REPO_HABITS', defaultValue: true);
  static const bool useRepoRoutine =
      bool.fromEnvironment('USE_REPO_ROUTINE', defaultValue: true);
  static const bool useRepoCalendarToday =
      bool.fromEnvironment('USE_REPO_CALENDAR_TODAY', defaultValue: true);
  static const bool useRepoEssentialTab =
      bool.fromEnvironment('USE_REPO_ESSENTIAL_TAB', defaultValue: true);
  static const bool enableParityChecks = bool.fromEnvironment(
    'ENABLE_INSTANCE_PARITY_CHECKS',
    defaultValue: false,
  );

  // Debug guardrails to catch accidental legacy-path development.
  static const bool warnOnLegacyPathUse = bool.fromEnvironment(
    'WARN_ON_LEGACY_INSTANCE_PATH_USE',
    defaultValue: true,
  );
  static const bool failOnLegacyPathUse = bool.fromEnvironment(
    'FAIL_ON_LEGACY_INSTANCE_PATH_USE',
    defaultValue: false,
  );

  static void onLegacyPathUsed(String scope) {
    if (!kDebugMode) return;
    FallbackReadLogger.logQuery(
      scope: scope,
      reason: 'legacy_instance_path_used',
      queryShape: 'app_level_legacy_branch',
      fallbackDocsReadEstimate: 0,
    );
    if (warnOnLegacyPathUse) {
      debugPrint(
        '[instance-repo][legacy-path] $scope is using legacy fallback. '
        'Avoid adding new behavior here.',
      );
    }
    assert(() {
      if (failOnLegacyPathUse) {
        throw StateError(
          'Legacy instance path used in $scope while '
          'FAIL_ON_LEGACY_INSTANCE_PATH_USE=true',
        );
      }
      return true;
    }());
  }
}
