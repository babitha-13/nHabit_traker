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
  static const bool _failOnLegacyPathUseFromEnv = bool.fromEnvironment(
    'FAIL_ON_LEGACY_INSTANCE_PATH_USE',
    defaultValue: false,
  );
  static const bool _allowLegacyInDebug = bool.fromEnvironment(
    'ALLOW_LEGACY_INSTANCE_PATH_USE_IN_DEBUG',
    defaultValue: false,
  );

  static bool get failOnLegacyPathUse {
    if (_failOnLegacyPathUseFromEnv) return true;
    if (kDebugMode && !_allowLegacyInDebug) return true;
    return false;
  }

  static void onLegacyPathUsed(String scope) {
    FallbackReadTelemetry.logLegacyPathInvocation(scope: scope);
    if (warnOnLegacyPathUse) {
      debugPrint(
        '[instance-repo][legacy-path] $scope is using legacy fallback. '
        'Avoid adding new behavior here.',
      );
    }
    if (failOnLegacyPathUse) {
      throw StateError(
        'Legacy instance path used in $scope while fail-fast is enabled '
        '(FAIL_ON_LEGACY_INSTANCE_PATH_USE or default debug enforcement).',
      );
    }
  }
}
