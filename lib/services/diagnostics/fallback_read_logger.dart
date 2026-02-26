import 'package:flutter/foundation.dart';

class FallbackReadEvent {
  const FallbackReadEvent({
    required this.scope,
    required this.reason,
    required this.queryShape,
    required this.userCountSampled,
    required this.fallbackDocsReadEstimate,
  });

  final String scope;
  final String reason;
  final String queryShape;
  final int userCountSampled;
  final int fallbackDocsReadEstimate;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'scope': scope,
      'reason': reason,
      'query_shape': queryShape,
      'user_count_sampled': userCountSampled,
      'fallback_docs_read_estimate': fallbackDocsReadEstimate,
    };
  }
}

class FallbackReadLogger {
  const FallbackReadLogger._();

  static const bool _envEnabled =
      bool.fromEnvironment('LOG_FALLBACK_READS', defaultValue: true);

  static bool get enabled => kDebugMode && _envEnabled;

  static void logQuery({
    required String scope,
    required String reason,
    required String queryShape,
    int userCountSampled = 1,
    int fallbackDocsReadEstimate = 0,
  }) {
    if (!enabled) return;
    debugPrint(
      '[fallback-read][query] scope=$scope, '
      'reason=$reason, '
      'query_shape=$queryShape, '
      'user_count_sampled=$userCountSampled, '
      'fallback_docs_read_estimate=$fallbackDocsReadEstimate',
    );
  }
}

class FallbackReadTelemetry {
  const FallbackReadTelemetry._();

  static const bool _enabled = bool.fromEnvironment(
    'ENABLE_FALLBACK_READ_TELEMETRY',
    defaultValue: true,
  );

  static int _legacyPathInvocationCount = 0;
  static int _queryFallbackInvocationCount = 0;
  static final Map<String, int> _legacyInvocationsByScope = <String, int>{};
  static final Map<String, int> _queryFallbackInvocationsByScope =
      <String, int>{};

  static int get legacyPathInvocationCount => _legacyPathInvocationCount;
  static int get queryFallbackInvocationCount => _queryFallbackInvocationCount;

  static Map<String, int> get legacyInvocationsByScope =>
      Map<String, int>.from(_legacyInvocationsByScope);
  static Map<String, int> get queryFallbackInvocationsByScope =>
      Map<String, int>.from(_queryFallbackInvocationsByScope);

  static void logLegacyPathInvocation({
    required String scope,
    String reason = 'legacy_path_invoked',
  }) {
    if (!_enabled) return;
    _legacyPathInvocationCount += 1;
    _legacyInvocationsByScope[scope] =
        (_legacyInvocationsByScope[scope] ?? 0) + 1;
    FallbackReadLogger.logQuery(
      scope: scope,
      reason: reason,
      queryShape: 'app_level_legacy_branch',
      fallbackDocsReadEstimate: 0,
    );
  }

  static void logQueryFallback(FallbackReadEvent event) {
    if (!_enabled) return;
    _queryFallbackInvocationCount += 1;
    _queryFallbackInvocationsByScope[event.scope] =
        (_queryFallbackInvocationsByScope[event.scope] ?? 0) + 1;
    FallbackReadLogger.logQuery(
      scope: event.scope,
      reason: event.reason,
      queryShape: event.queryShape,
      userCountSampled: event.userCountSampled,
      fallbackDocsReadEstimate: event.fallbackDocsReadEstimate,
    );
  }

  static Map<String, Object?> snapshotCounters() {
    return <String, Object?>{
      'legacy_path_invocation_count': _legacyPathInvocationCount,
      'query_fallback_invocation_count': _queryFallbackInvocationCount,
      'legacy_path_invocations_by_scope': legacyInvocationsByScope,
      'query_fallback_invocations_by_scope': queryFallbackInvocationsByScope,
    };
  }
}
