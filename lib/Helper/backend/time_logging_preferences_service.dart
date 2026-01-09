import 'package:habit_tracker/Helper/backend/schema/users_record.dart';

class TimeLoggingPreferences {
  const TimeLoggingPreferences({
    required this.defaultDurationMinutes,
    required this.enableDefaultEstimates,
    required this.enableActivityEstimates,
  });

  final int defaultDurationMinutes;
  final bool enableDefaultEstimates;
  final bool enableActivityEstimates;
}

/// Service for managing user time logging preferences
/// All business logic for time logging preferences is centralized here (#REFACTOR_NOW compliance)
class TimeLoggingPreferencesService {
  // In-memory cache to avoid repeated Firestore reads
  static final Map<String, int> _cache = {};
  static final Map<String, bool> _enableDefaultEstimatesCache = {};
  static final Map<String, bool> _enableActivityEstimatesCache = {};
  static const int _defaultDurationMinutes = 10;
  static const int _minDurationMinutes = 5;
  static const int _maxDurationMinutes = 60;
  static const bool _defaultEnableDefaultEstimates =
      true; // Backward compatibility
  static const bool _defaultEnableActivityEstimates = false;

  /// Get user's time logging preferences in a single read.
  ///
  /// Returns defaults when missing/invalid and clamps duration to 5-60.
  static Future<TimeLoggingPreferences> getPreferences(String userId) async {
    final hasAllCached = _cache.containsKey(userId) &&
        _enableDefaultEstimatesCache.containsKey(userId) &&
        _enableActivityEstimatesCache.containsKey(userId);

    if (hasAllCached) {
      return TimeLoggingPreferences(
        defaultDurationMinutes: _cache[userId]!,
        enableDefaultEstimates: _enableDefaultEstimatesCache[userId]!,
        enableActivityEstimates: _enableActivityEstimatesCache[userId]!,
      );
    }

    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        _cache[userId] = _defaultDurationMinutes;
        _enableDefaultEstimatesCache[userId] = _defaultEnableDefaultEstimates;
        _enableActivityEstimatesCache[userId] = _defaultEnableActivityEstimates;
        return const TimeLoggingPreferences(
          defaultDurationMinutes: _defaultDurationMinutes,
          enableDefaultEstimates: _defaultEnableDefaultEstimates,
          enableActivityEstimates: _defaultEnableActivityEstimates,
        );
      }

      final userData = UsersRecord.fromSnapshot(userDoc);
      final prefs = userData.notificationPreferences;

      final timeLoggingPrefs =
          prefs['time_logging_preferences'] as Map<String, dynamic>?;

      final durationRaw = timeLoggingPrefs?['default_duration_minutes'] as int?;
      final duration = (durationRaw ?? _defaultDurationMinutes)
          .clamp(_minDurationMinutes, _maxDurationMinutes);

      final enableDefault =
          timeLoggingPrefs?['enable_default_estimates'] as bool?;
      final enableActivity =
          timeLoggingPrefs?['enable_activity_estimates'] as bool?;

      final enableDefaultValue =
          enableDefault ?? _defaultEnableDefaultEstimates;
      final enableActivityValue = enableDefaultValue
          ? (enableActivity ?? _defaultEnableActivityEstimates)
          : false;

      _cache[userId] = duration;
      _enableDefaultEstimatesCache[userId] = enableDefaultValue;
      _enableActivityEstimatesCache[userId] = enableActivityValue;

      return TimeLoggingPreferences(
        defaultDurationMinutes: duration,
        enableDefaultEstimates: enableDefaultValue,
        enableActivityEstimates: enableActivityValue,
      );
    } catch (e) {
      _cache[userId] = _defaultDurationMinutes;
      _enableDefaultEstimatesCache[userId] = _defaultEnableDefaultEstimates;
      _enableActivityEstimatesCache[userId] = _defaultEnableActivityEstimates;
      return const TimeLoggingPreferences(
        defaultDurationMinutes: _defaultDurationMinutes,
        enableDefaultEstimates: _defaultEnableDefaultEstimates,
        enableActivityEstimates: _defaultEnableActivityEstimates,
      );
    }
  }

  /// Update one or more time logging preferences in a single write.
  ///
  /// If `enableDefaultEstimates` is set to `false`, `enableActivityEstimates`
  /// will be forced to `false` for consistency.
  static Future<void> updatePreferences(
    String userId, {
    int? defaultDurationMinutes,
    bool? enableDefaultEstimates,
    bool? enableActivityEstimates,
  }) async {
    final shouldForceDisableActivity =
        enableDefaultEstimates != null && enableDefaultEstimates == false;

    final clampedMinutes = defaultDurationMinutes == null
        ? null
        : defaultDurationMinutes.clamp(
            _minDurationMinutes, _maxDurationMinutes);

    try {
      final userDoc = await UsersRecord.collection.doc(userId).get();
      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final userData = UsersRecord.fromSnapshot(userDoc);
      final existingPrefs =
          Map<String, dynamic>.from(userData.notificationPreferences);

      final timeLoggingPrefs = Map<String, dynamic>.from(
        existingPrefs['time_logging_preferences'] as Map<String, dynamic>? ??
            {},
      );

      if (clampedMinutes != null) {
        timeLoggingPrefs['default_duration_minutes'] = clampedMinutes;
      }
      if (enableDefaultEstimates != null) {
        timeLoggingPrefs['enable_default_estimates'] = enableDefaultEstimates;
      }
      if (shouldForceDisableActivity) {
        timeLoggingPrefs['enable_activity_estimates'] = false;
      } else if (enableActivityEstimates != null) {
        timeLoggingPrefs['enable_activity_estimates'] = enableActivityEstimates;
      }

      existingPrefs['time_logging_preferences'] = timeLoggingPrefs;

      await UsersRecord.collection.doc(userId).update(
            createUsersRecordData(
              notificationPreferences: existingPrefs,
            ),
          );

      if (clampedMinutes != null) {
        _cache[userId] = clampedMinutes;
      }
      if (enableDefaultEstimates != null) {
        _enableDefaultEstimatesCache[userId] = enableDefaultEstimates;
      }
      if (shouldForceDisableActivity) {
        _enableActivityEstimatesCache[userId] = false;
      } else if (enableActivityEstimates != null) {
        _enableActivityEstimatesCache[userId] = enableActivityEstimates;
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Get user's default duration for time logging (in minutes)
  /// Returns a value between 5-60 minutes, defaulting to 10 if not set
  static Future<int> getDefaultDurationMinutes(String userId) async {
    if (_cache.containsKey(userId)) return _cache[userId]!;
    final prefs = await getPreferences(userId);
    return prefs.defaultDurationMinutes;
  }

  /// Update user's default duration for time logging (in minutes)
  /// Validates and clamps the value to 5-60 minutes
  static Future<void> updateDefaultDurationMinutes(
    String userId,
    int minutes,
  ) async {
    await updatePreferences(userId, defaultDurationMinutes: minutes);
  }

  /// Clear cache for a user (useful for testing or when preferences are updated elsewhere)
  static void clearCache(String userId) {
    _cache.remove(userId);
    _enableDefaultEstimatesCache.remove(userId);
    _enableActivityEstimatesCache.remove(userId);
  }

  /// Clear all cache
  static void clearAllCache() {
    _cache.clear();
    _enableDefaultEstimatesCache.clear();
    _enableActivityEstimatesCache.clear();
  }

  /// Get user's preference for enabling default time estimates
  /// Returns true by default for backward compatibility
  static Future<bool> getEnableDefaultEstimates(String userId) async {
    if (_enableDefaultEstimatesCache.containsKey(userId)) {
      return _enableDefaultEstimatesCache[userId]!;
    }
    final prefs = await getPreferences(userId);
    return prefs.enableDefaultEstimates;
  }

  /// Update user's preference for enabling default time estimates
  static Future<void> updateEnableDefaultEstimates(
    String userId,
    bool enabled,
  ) async {
    await updatePreferences(userId, enableDefaultEstimates: enabled);
  }

  /// Get user's preference for enabling activity-wise time estimates
  /// Returns false by default
  static Future<bool> getEnableActivityEstimates(String userId) async {
    if (_enableActivityEstimatesCache.containsKey(userId)) {
      return _enableActivityEstimatesCache[userId]!;
    }
    final prefs = await getPreferences(userId);
    return prefs.enableActivityEstimates;
  }

  /// Update user's preference for enabling activity-wise time estimates
  static Future<void> updateEnableActivityEstimates(
    String userId,
    bool enabled,
  ) async {
    await updatePreferences(userId, enableActivityEstimates: enabled);
  }
}
