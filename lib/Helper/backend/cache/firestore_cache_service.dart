import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_events_result.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';

/// Centralized cache service for Firestore data
/// Reduces redundant reads by caching frequently accessed data
class FirestoreCacheService {
  static final FirestoreCacheService _instance =
      FirestoreCacheService._internal();
  factory FirestoreCacheService() => _instance;
  FirestoreCacheService._internal() {
    _setupCacheInvalidationListeners();
  }

  // Cache storage
  List<ActivityInstanceRecord>? _cachedAllInstances;
  List<ActivityInstanceRecord>? _cachedTaskInstances;
  List<ActivityInstanceRecord>? _cachedHabitInstances;
  List<CategoryRecord>? _cachedHabitCategories;
  List<CategoryRecord>? _cachedTaskCategories;
  Map<String, ActivityRecord> _cachedTemplates = {};
  Map<String, ActivityInstanceRecord> _cachedInstancesById = {};
  Map<String, CalendarEventsResult> _calendarDateCache = {};

  // Cache timestamps
  DateTime? _allInstancesTimestamp;
  DateTime? _taskInstancesTimestamp;
  DateTime? _habitInstancesTimestamp;
  DateTime? _habitCategoriesTimestamp;
  DateTime? _taskCategoriesTimestamp;
  Map<String, DateTime> _templateTimestamps = {};
  Map<String, DateTime> _instanceTimestamps = {};
  Map<String, DateTime> _calendarDateTimestamps = {};

  // Cache TTL (Time To Live) in seconds
  static const int _instancesCacheTTL = 30; // 30 seconds for instances
  static const int _categoriesCacheTTL =
      900; // 15 minutes for categories (change infrequently)
  static const int _templateCacheTTL = 60; // 1 minute for templates
  static const int _calendarDateCacheTTL =
      60; // 60 seconds for calendar events (current/future dates)
  static const int _calendarPastDateCacheTTL =
      86400 * 7; // 7 days for past dates (never change)

  // Cache size limits to prevent OOM on web
  static const int _maxHabitInstancesCache =
      500; // Limit habit instances to 500
  static const int _maxInstancesByIdCache = 300; // Limit instancesById to 300

  // Track if listeners are already set up to prevent duplicates on hot restart
  static bool _listenersSetup = false;

  /// Setup listeners for cache invalidation
  void _setupCacheInvalidationListeners() {
    // CRITICAL FIX: Only set up listeners once per app lifecycle
    // On hot restart, static variables are reset, but NotificationCenter might still have observers
    // So we check observer count - if there are already observers for these events, skip setup
    // This prevents duplicate observers from accumulating
    if (_listenersSetup) {
      return;
    }
    // Invalidate instances cache when instances are created/updated/deleted
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceCreated,
      (param) {
        final instance = _extractInstanceFromEventParam(param);
        final isOptimistic = _isOptimisticEventParam(param);

        if (isOptimistic && instance != null) {
          _applyOptimisticInstanceCacheUpdate(instance);
        } else {
          invalidateInstancesCache();
        }

        if (instance != null && !isOptimistic) {
          _invalidateCalendarCacheForInstance(instance);
        }
      },
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      (param) {
        final instance = _extractInstanceFromEventParam(param);
        final isOptimistic = _isOptimisticEventParam(param);

        if (isOptimistic && instance != null) {
          _applyOptimisticInstanceCacheUpdate(instance);
        } else {
          invalidateInstancesCache();
        }

        if (instance != null && !isOptimistic) {
          _invalidateCalendarCacheForInstance(instance);
        }
      },
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceDeleted,
      (param) {
        invalidateInstancesCache();
        // Invalidate calendar cache for affected dates
        if (param is ActivityInstanceRecord) {
          _invalidateCalendarCacheForInstance(param);
        }
      },
    );

    // Invalidate templates cache when templates are updated
    NotificationCenter.addObserver(
      this,
      'templateUpdated',
      (param) {
        if (param is Map && param['templateId'] is String) {
          invalidateTemplateCache(param['templateId'] as String);
        }
      },
    );
    // Also listen to ActivityTemplateEvents
    NotificationCenter.addObserver(
      this,
      'activityTemplateUpdated',
      (param) {
        if (param is Map && param['templateId'] is String) {
          invalidateTemplateCache(param['templateId'] as String);
        }
      },
    );

    // Invalidate categories cache when categories are updated
    NotificationCenter.addObserver(
      this,
      'categoryUpdated',
      (_) => invalidateCategoriesCache(),
    );
    _listenersSetup = true;
  }

  ActivityInstanceRecord? _extractInstanceFromEventParam(Object? param) {
    if (param is ActivityInstanceRecord) {
      return param;
    }
    if (param is Map && param['instance'] is ActivityInstanceRecord) {
      return param['instance'] as ActivityInstanceRecord;
    }
    return null;
  }

  bool _isOptimisticEventParam(Object? param) {
    if (param is Map) {
      return param['isOptimistic'] as bool? ?? false;
    }
    return false;
  }

  void _upsertInstanceInList(
    List<ActivityInstanceRecord> instances,
    ActivityInstanceRecord instance,
  ) {
    final index = instances.indexWhere(
      (existing) => existing.reference.id == instance.reference.id,
    );
    if (index == -1) {
      instances.add(instance);
    } else {
      instances[index] = instance;
    }
  }

  void _applyOptimisticInstanceCacheUpdate(ActivityInstanceRecord instance) {
    cacheInstance(instance);

    // Aggregate caches only store habit/task instances.
    if (instance.templateCategoryType != 'habit' &&
        instance.templateCategoryType != 'task') {
      return;
    }

    final now = DateTime.now();

    if (_cachedAllInstances != null) {
      _upsertInstanceInList(_cachedAllInstances!, instance);
      _allInstancesTimestamp = now;
    }

    if (instance.templateCategoryType == 'task' &&
        _cachedTaskInstances != null) {
      _upsertInstanceInList(_cachedTaskInstances!, instance);
      _taskInstancesTimestamp = now;
    }

    if (instance.templateCategoryType == 'habit' &&
        _cachedHabitInstances != null) {
      _upsertInstanceInList(_cachedHabitInstances!, instance);
      _habitInstancesTimestamp = now;
    }
  }

  /// Ensure listeners are set up (can be called from main.dart on reassemble)
  void ensureListenersSetup() {
    // Only setup if not already setup (handled inside _setupCacheInvalidationListeners via flag check)
    // But first, if this is called explicitly, we might want to force it if the flag was reset
    _setupCacheInvalidationListeners();
  }

  /// Reset the listeners setup flag (called when NotificationCenter is reset)
  static void resetListenersSetup() {
    _listenersSetup = false;
  }

  /// Check if cache is still valid based on TTL
  bool _isCacheValid(DateTime? timestamp, int ttlSeconds) {
    if (timestamp == null) return false;
    final age = DateTime.now().difference(timestamp).inSeconds;
    return age < ttlSeconds;
  }

  // ==================== INSTANCES CACHE ====================

  /// Get cached all instances if available and fresh
  List<ActivityInstanceRecord>? getCachedAllInstances() {
    if (_isCacheValid(_allInstancesTimestamp, _instancesCacheTTL)) {
      return _cachedAllInstances;
    }
    return null;
  }

  /// Cache all instances
  void cacheAllInstances(List<ActivityInstanceRecord> instances) {
    _cachedAllInstances = instances;
    _allInstancesTimestamp = DateTime.now();
    // Also cache individual instances by ID for quick lookup (with size limit)
    // Clear old entries if cache is getting too large
    if (_cachedInstancesById.length > _maxInstancesByIdCache) {
      _cachedInstancesById.clear();
      _instanceTimestamps.clear();
    }
    for (final instance in instances) {
      _cachedInstancesById[instance.reference.id] = instance;
      _instanceTimestamps[instance.reference.id] = DateTime.now();
    }
  }

  /// Get cached task instances if available and fresh
  List<ActivityInstanceRecord>? getCachedTaskInstances() {
    if (_isCacheValid(_taskInstancesTimestamp, _instancesCacheTTL)) {
      return _cachedTaskInstances;
    }
    return null;
  }

  /// Cache task instances
  void cacheTaskInstances(List<ActivityInstanceRecord> instances) {
    _cachedTaskInstances = instances;
    _taskInstancesTimestamp = DateTime.now();
  }

  /// Get cached habit instances if available and fresh
  List<ActivityInstanceRecord>? getCachedHabitInstances() {
    if (_isCacheValid(_habitInstancesTimestamp, _instancesCacheTTL)) {
      return _cachedHabitInstances;
    }
    return null;
  }

  /// Cache habit instances (with size limit to prevent OOM)
  void cacheHabitInstances(List<ActivityInstanceRecord> instances) {
    // Limit cache size to prevent OOM on web
    if (instances.length > _maxHabitInstancesCache) {
      // Keep only the most recent instances (by lastUpdated or createdTime)
      final sorted = List<ActivityInstanceRecord>.from(instances);
      sorted.sort((a, b) {
        final aTime = a.lastUpdated ?? a.createdTime ?? DateTime(2000);
        final bTime = b.lastUpdated ?? b.createdTime ?? DateTime(2000);
        return bTime.compareTo(aTime); // Most recent first
      });
      _cachedHabitInstances = sorted.take(_maxHabitInstancesCache).toList();
    } else {
      _cachedHabitInstances = instances;
    }
    _habitInstancesTimestamp = DateTime.now();
  }

  /// Get cached instance by ID
  ActivityInstanceRecord? getCachedInstanceById(String instanceId) {
    if (_isCacheValid(_instanceTimestamps[instanceId], _instancesCacheTTL)) {
      return _cachedInstancesById[instanceId];
    }
    return null;
  }

  /// Cache a single instance
  void cacheInstance(ActivityInstanceRecord instance) {
    _cachedInstancesById[instance.reference.id] = instance;
    _instanceTimestamps[instance.reference.id] = DateTime.now();
  }

  // ==================== CATEGORIES CACHE ====================

  /// Get cached habit categories if available and fresh
  List<CategoryRecord>? getCachedHabitCategories() {
    if (_isCacheValid(_habitCategoriesTimestamp, _categoriesCacheTTL)) {
      return _cachedHabitCategories;
    }
    return null;
  }

  /// Cache habit categories
  void cacheHabitCategories(List<CategoryRecord> categories) {
    _cachedHabitCategories = categories;
    _habitCategoriesTimestamp = DateTime.now();
  }

  /// Get cached task categories if available and fresh
  List<CategoryRecord>? getCachedTaskCategories() {
    if (_isCacheValid(_taskCategoriesTimestamp, _categoriesCacheTTL)) {
      return _cachedTaskCategories;
    }
    return null;
  }

  /// Cache task categories
  void cacheTaskCategories(List<CategoryRecord> categories) {
    _cachedTaskCategories = categories;
    _taskCategoriesTimestamp = DateTime.now();
  }

  // ==================== TEMPLATES CACHE ====================

  /// Get cached template by ID if available and fresh
  ActivityRecord? getCachedTemplate(String templateId) {
    if (_isCacheValid(_templateTimestamps[templateId], _templateCacheTTL)) {
      return _cachedTemplates[templateId];
    }
    return null;
  }

  /// Cache a template
  void cacheTemplate(String templateId, ActivityRecord template) {
    _cachedTemplates[templateId] = template;
    _templateTimestamps[templateId] = DateTime.now();
  }

  /// Cache multiple templates
  void cacheTemplates(Map<String, ActivityRecord> templates) {
    final now = DateTime.now();
    _cachedTemplates.addAll(templates);
    for (final templateId in templates.keys) {
      _templateTimestamps[templateId] = now;
    }
  }

  // ==================== CACHE INVALIDATION ====================

  /// Invalidate all instances cache
  void invalidateInstancesCache() {
    _cachedAllInstances = null;
    _cachedTaskInstances = null;
    _cachedHabitInstances = null;
    _cachedInstancesById.clear();
    _instanceTimestamps.clear();
    _allInstancesTimestamp = null;
    _taskInstancesTimestamp = null;
    _habitInstancesTimestamp = null;
    // Also invalidate calendar cache since it depends on instances
    invalidateCalendarCache();
  }

  /// Partially invalidate instances cache for a specific instance
  /// This is more efficient than invalidating the entire cache
  void invalidateInstanceCache(String instanceId) {
    // Remove specific instance from cache
    _cachedInstancesById.remove(instanceId);
    _instanceTimestamps.remove(instanceId);

    // Invalidate aggregate caches that might contain this instance
    // Note: We could be smarter and update the lists, but for simplicity
    // we invalidate the aggregate caches. The TTL will handle freshness.
    _cachedAllInstances = null;
    _cachedTaskInstances = null;
    _cachedHabitInstances = null;
    _allInstancesTimestamp = null;
    _taskInstancesTimestamp = null;
    _habitInstancesTimestamp = null;
  }

  /// Invalidate categories cache
  void invalidateCategoriesCache() {
    _cachedHabitCategories = null;
    _cachedTaskCategories = null;
    _habitCategoriesTimestamp = null;
    _taskCategoriesTimestamp = null;
  }

  /// Invalidate template cache for a specific template
  void invalidateTemplateCache(String templateId) {
    _cachedTemplates.remove(templateId);
    _templateTimestamps.remove(templateId);
  }

  /// Invalidate all templates cache
  void invalidateAllTemplatesCache() {
    _cachedTemplates.clear();
    _templateTimestamps.clear();
  }

  // ==================== CALENDAR DATE CACHE ====================

  /// Get cache key for a date (normalized to start of day) + optional variant.
  String _getDateCacheKey(DateTime date, {String variant = 'full'}) {
    final normalized = DateService.normalizeToStartOfDay(date);
    return '${normalized.year}-${normalized.month}-${normalized.day}|$variant';
  }

  String _getDateCachePrefix(DateTime date) {
    final normalized = DateService.normalizeToStartOfDay(date);
    return '${normalized.year}-${normalized.month}-${normalized.day}|';
  }

  /// Check if a date is in the past (before today)
  bool _isPastDate(DateTime date) {
    final todayStart = DateService.todayStart;
    final dateStart = DateService.normalizeToStartOfDay(date);
    return dateStart.isBefore(todayStart);
  }

  /// Get cached calendar events for a date if available and fresh
  /// Uses longer TTL for past dates since they never change
  CalendarEventsResult? getCachedCalendarEvents(
    DateTime date, {
    String variant = 'full',
  }) {
    final key = _getDateCacheKey(date, variant: variant);
    final timestamp = _calendarDateTimestamps[key];

    // Use longer TTL for past dates (they never change)
    final ttl =
        _isPastDate(date) ? _calendarPastDateCacheTTL : _calendarDateCacheTTL;

    if (_isCacheValid(timestamp, ttl)) {
      return _calendarDateCache[key];
    }
    return null;
  }

  /// Cache calendar events for a date
  void cacheCalendarEvents(
    DateTime date,
    CalendarEventsResult events, {
    String variant = 'full',
  }) {
    // Prevent unbound growth of calendar cache
    if (_calendarDateCache.length > 100) {
      _calendarDateCache.clear();
      _calendarDateTimestamps.clear();
    }
    final key = _getDateCacheKey(date, variant: variant);
    _calendarDateCache[key] = events;
    _calendarDateTimestamps[key] = DateTime.now();
  }

  Map<String, int> debugCounts() {
    return {
      'allInstances': _cachedAllInstances?.length ?? 0,
      'taskInstances': _cachedTaskInstances?.length ?? 0,
      'habitInstances': _cachedHabitInstances?.length ?? 0,
      'habitCategories': _cachedHabitCategories?.length ?? 0,
      'taskCategories': _cachedTaskCategories?.length ?? 0,
      'templates': _cachedTemplates.length,
      'instancesById': _cachedInstancesById.length,
      'calendarDates': _calendarDateCache.length,
    };
  }

  /// Invalidate calendar cache for a specific date
  /// Note: Past dates are never invalidated since they never change
  void invalidateCalendarDateCache(DateTime date) {
    // Don't invalidate past dates - they never change
    if (_isPastDate(date)) {
      return;
    }

    final prefix = _getDateCachePrefix(date);
    _calendarDateCache.removeWhere((key, _) => key.startsWith(prefix));
    _calendarDateTimestamps.removeWhere((key, _) => key.startsWith(prefix));
  }

  /// Invalidate calendar cache for multiple dates (useful when instance affects multiple dates)
  void invalidateCalendarDatesCache(List<DateTime> dates) {
    for (final date in dates) {
      invalidateCalendarDateCache(date);
    }
  }

  /// Invalidate all calendar cache
  void invalidateCalendarCache() {
    _calendarDateCache.clear();
    _calendarDateTimestamps.clear();
  }

  /// Invalidate calendar cache when instance changes affect specific dates
  /// This is called from the notification handlers to invalidate only affected dates
  /// Past dates are automatically filtered out since they never change
  void _invalidateCalendarCacheForInstance(ActivityInstanceRecord instance) {
    final affectedDates = <DateTime>{};
    final todayStart = DateService.todayStart;

    // Check completedAt date (only if today or future)
    if (instance.completedAt != null) {
      final date = DateService.normalizeToStartOfDay(instance.completedAt!);
      if (!date.isBefore(todayStart)) {
        affectedDates.add(date);
      }
    }

    // Check dueDate (only if today or future)
    if (instance.dueDate != null) {
      final date = DateService.normalizeToStartOfDay(instance.dueDate!);
      if (!date.isBefore(todayStart)) {
        affectedDates.add(date);
      }
    }

    // Check belongsToDate (only if today or future)
    if (instance.belongsToDate != null) {
      final date = DateService.normalizeToStartOfDay(instance.belongsToDate!);
      if (!date.isBefore(todayStart)) {
        affectedDates.add(date);
      }
    }

    // Check time log sessions (only if today or future)
    if (instance.timeLogSessions.isNotEmpty) {
      for (final session in instance.timeLogSessions) {
        final sessionStart = session['startTime'] as DateTime?;
        if (sessionStart != null) {
          final date = DateService.normalizeToStartOfDay(sessionStart);
          if (!date.isBefore(todayStart)) {
            affectedDates.add(date);
          }
        }
      }
    }

    // Only invalidate current/future dates
    if (affectedDates.isNotEmpty) {
      invalidateCalendarDatesCache(affectedDates.toList());
    }
  }

  /// Invalidate all caches
  void invalidateAllCache() {
    invalidateInstancesCache();
    invalidateCategoriesCache();
    invalidateAllTemplatesCache();
    invalidateCalendarCache();
  }

  /// Preload data on app start (optional - can be called from main.dart)
  Future<void> preloadData(String userId) async {
    // This can be called asynchronously after app initialization
    // to warm up the cache
    // Implementation can be added later if needed
  }
}
