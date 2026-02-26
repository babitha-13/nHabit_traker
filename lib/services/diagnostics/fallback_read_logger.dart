import 'package:flutter/foundation.dart';

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
