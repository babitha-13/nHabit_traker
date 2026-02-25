import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/task_instance_service/task_instance_time_logging_service.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_selectors.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_snapshot.dart';

class TodayInstanceRepository extends ChangeNotifier {
  TodayInstanceRepository._internal();
  static final TodayInstanceRepository instance =
      TodayInstanceRepository._internal();

  static bool _listenersSetup = false;

  static void resetListenersSetup() {
    _listenersSetup = false;
  }

  void ensureListenersSetup() {
    if (_listenersSetup) {
      return;
    }
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceCreated,
      _handleInstanceCreated,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      _handleInstanceUpdated,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceDeleted,
      _handleInstanceDeleted,
    );
    NotificationCenter.addObserver(
      this,
      'instanceUpdateRollback',
      _handleInstanceRollback,
    );
    _listenersSetup = true;
  }

  TodayInstanceSnapshot? _snapshot;
  Future<TodayInstanceSnapshot>? _inFlightHydration;
  String? _inFlightHydrationKey;
  List<ActivityInstanceRecord>? _taskItemsSnapshot;
  Future<List<ActivityInstanceRecord>>? _inFlightTaskHydration;
  String? _inFlightTaskHydrationKey;
  String? _taskItemsUserId;
  DateTime? _taskItemsDayStart;
  List<ActivityInstanceRecord>? _habitItemsSnapshot;
  Future<List<ActivityInstanceRecord>>? _inFlightHabitHydration;
  String? _inFlightHabitHydrationKey;
  String? _habitItemsUserId;
  DateTime? _habitItemsDayStart;
  int _revision = 0;

  TodayInstanceSnapshot? get snapshot => _snapshot;
  int get revision => _revision;

  bool get hasSnapshot {
    final snap = _snapshot;
    if (snap == null) return false;
    return snap.dayStart.isAtSameMomentAs(DateService.todayStart);
  }

  void clearSnapshot() {
    _snapshot = null;
    _clearTaskItemsSnapshot();
    _revision++;
    notifyListeners();
  }

  Future<TodayInstanceSnapshot> ensureHydrated({
    required String userId,
    bool forceRefresh = false,
  }) async {
    ensureListenersSetup();
    final dayStart = DateService.todayStart;
    final cacheKey = _buildHydrationKey(userId: userId, dayStart: dayStart);

    if (!forceRefresh &&
        _isSnapshotValidFor(userId: userId, dayStart: dayStart)) {
      return _snapshot!;
    }

    if (_inFlightHydration != null && _inFlightHydrationKey == cacheKey) {
      return _inFlightHydration!;
    }

    final hydrationFuture = _hydrateSnapshot(
      userId: userId,
      dayStart: dayStart,
    );
    _inFlightHydration = hydrationFuture;
    _inFlightHydrationKey = cacheKey;

    try {
      final hydrated = await hydrationFuture;
      _snapshot = hydrated;
      _revision++;
      notifyListeners();
      return hydrated;
    } finally {
      if (_inFlightHydrationKey == cacheKey) {
        _inFlightHydration = null;
        _inFlightHydrationKey = null;
      }
    }
  }

  Future<TodayInstanceSnapshot> refreshToday({
    required String userId,
  }) {
    return ensureHydrated(
      userId: userId,
      forceRefresh: true,
    );
  }

  Future<TodayInstanceSnapshot> ensureHydratedForTasks({
    required String userId,
    bool forceRefresh = false,
    bool includeHabitItems = false,
  }) async {
    final hydrated = await ensureHydrated(
      userId: userId,
      forceRefresh: forceRefresh,
    );
    await _ensureTaskItemsHydrated(
      userId: userId,
      forceRefresh: forceRefresh,
    );
    if (includeHabitItems) {
      await _ensureHabitItemsHydrated(
        userId: userId,
        forceRefresh: forceRefresh,
      );
    }
    return hydrated;
  }

  Future<TodayInstanceSnapshot> refreshTodayForTasks({
    required String userId,
    bool includeHabitItems = false,
  }) {
    return ensureHydratedForTasks(
      userId: userId,
      forceRefresh: true,
      includeHabitItems: includeHabitItems,
    );
  }

  List<ActivityInstanceRecord> selectQueueItems() {
    return TodayInstanceSelectors.selectQueueItems(_currentSnapshotOrEmpty());
  }

  List<ActivityInstanceRecord> selectTaskItems() {
    final taskScoped = _taskItemsIfValid();
    if (taskScoped != null) {
      return taskScoped;
    }
    return TodayInstanceSelectors.selectTaskItems(_currentSnapshotOrEmpty());
  }

  List<ActivityInstanceRecord> selectHabitItems() {
    final habitScoped = _habitItemsIfValid();
    if (habitScoped != null) {
      return habitScoped;
    }
    return TodayInstanceSelectors.selectHabitItemsCurrentWindow(
      _currentSnapshotOrEmpty(),
    );
  }

  List<ActivityInstanceRecord> selectHabitItemsCurrentWindow() {
    return TodayInstanceSelectors.selectHabitItemsCurrentWindow(
      _currentSnapshotOrEmpty(),
    );
  }

  List<ActivityInstanceRecord> selectHabitItemsLatestPerTemplate() {
    return TodayInstanceSelectors.selectHabitItemsLatestPerTemplate(
      _currentSnapshotOrEmpty(),
    );
  }

  Map<String, ActivityInstanceRecord> selectRoutineItems({
    required RoutineRecord routine,
  }) {
    return TodayInstanceSelectors.selectRoutineItems(
      snapshot: _currentSnapshotOrEmpty(),
      routine: routine,
    );
  }

  List<ActivityInstanceRecord> selectCalendarTodayTaskHabitPlanned() {
    return TodayInstanceSelectors.selectCalendarTodayTaskHabitPlanned(
      _currentSnapshotOrEmpty(),
    );
  }

  List<ActivityInstanceRecord> selectCalendarTodayCompleted() {
    return TodayInstanceSelectors.selectCalendarTodayCompleted(
      _currentSnapshotOrEmpty(),
    );
  }

  List<ActivityInstanceRecord> selectEssentialTodayInstances({
    bool includePending = true,
    bool includeLogged = true,
  }) {
    return TodayInstanceSelectors.selectEssentialTodayInstances(
      _currentSnapshotOrEmpty(),
      includePending: includePending,
      includeLogged: includeLogged,
    );
  }

  Map<String, Map<String, int>> selectEssentialTodayStatsByTemplate() {
    return TodayInstanceSelectors.selectEssentialTodayStatsByTemplate(
      _currentSnapshotOrEmpty(),
    );
  }

  TodayInstanceSnapshot _currentSnapshotOrEmpty() {
    final existing = _snapshot;
    final today = DateService.todayStart;
    if (existing == null || !existing.dayStart.isAtSameMomentAs(today)) {
      return TodayInstanceSnapshot(
        userId: existing?.userId ?? '',
        dayStart: today,
        dayEnd: today.add(const Duration(days: 1)),
        instancesById: const <String, ActivityInstanceRecord>{},
        hydratedAt: DateTime.now(),
      );
    }
    return existing;
  }

  String _buildHydrationKey({
    required String userId,
    required DateTime dayStart,
  }) {
    return '$userId:${dayStart.millisecondsSinceEpoch}';
  }

  bool _isSnapshotValidFor({
    required String userId,
    required DateTime dayStart,
  }) {
    final existing = _snapshot;
    if (existing == null) return false;
    return existing.userId == userId &&
        existing.dayStart.isAtSameMomentAs(dayStart);
  }

  Future<TodayInstanceSnapshot> _hydrateSnapshot({
    required String userId,
    required DateTime dayStart,
  }) async {
    final dayEnd = dayStart.add(const Duration(days: 1));

    final results = await Future.wait<dynamic>([
      ActivityInstanceService.getAllActiveInstances(userId: userId),
      TaskInstanceTimeLoggingService.getTodayEssentialInstances(
        userId: userId,
        dayStart: dayStart,
        includePending: true,
        includeLogged: true,
      ),
    ]);

    final mergedById = <String, ActivityInstanceRecord>{};

    void merge(List<ActivityInstanceRecord> items) {
      for (final instance in items) {
        mergedById[instance.reference.id] = instance;
      }
    }

    merge(results[0] as List<ActivityInstanceRecord>);
    merge(results[1] as List<ActivityInstanceRecord>);

    return TodayInstanceSnapshot(
      userId: userId,
      dayStart: dayStart,
      dayEnd: dayEnd,
      instancesById: mergedById,
      hydratedAt: DateTime.now(),
    );
  }

  void _handleInstanceCreated(Object? param) {
    _applyUpsertFromEvent(param);
  }

  void _handleInstanceUpdated(Object? param) {
    _applyUpsertFromEvent(param);
  }

  void _applyUpsertFromEvent(Object? param) {
    final existing = _snapshot;
    if (existing == null) {
      return;
    }

    ActivityInstanceRecord? instance;
    if (param is ActivityInstanceRecord) {
      instance = param;
    } else if (param is Map && param['instance'] is ActivityInstanceRecord) {
      instance = param['instance'] as ActivityInstanceRecord;
    }
    if (instance == null) {
      return;
    }
    if (instance.templateCategoryType == 'task') {
      _upsertTaskItemsSnapshot(instance);
    } else if (instance.templateCategoryType == 'habit') {
      _upsertHabitItemsSnapshot(instance);
    }

    if (_extractUserIdFromPath(instance.reference.path) != existing.userId) {
      return;
    }

    final instanceId = instance.reference.id;
    final alreadyTracked = existing.instancesById.containsKey(instanceId);
    final isRelevant = _isRelevantForToday(instance, existing);

    if (!alreadyTracked && !isRelevant) {
      return;
    }

    // Keep snapshot bounded to today-scope parity with hydration queries:
    // if a tracked item updates out of scope (e.g., backdated completion),
    // remove it instead of retaining stale membership.
    if (!isRelevant) {
      final updated =
          Map<String, ActivityInstanceRecord>.from(existing.instancesById)
            ..remove(instanceId);
      _snapshot = existing.copyWith(
        instancesById: updated,
        hydratedAt: DateTime.now(),
      );
      _revision++;
      notifyListeners();
      return;
    }

    final updated =
        Map<String, ActivityInstanceRecord>.from(existing.instancesById)
          ..[instanceId] = instance;
    _snapshot = existing.copyWith(
      instancesById: updated,
      hydratedAt: DateTime.now(),
    );
    _revision++;
    notifyListeners();
  }

  void _handleInstanceDeleted(Object? param) {
    final existing = _snapshot;
    if (existing == null) {
      return;
    }

    ActivityInstanceRecord? deletedInstance;
    String? deletedId;

    if (param is ActivityInstanceRecord) {
      deletedInstance = param;
      deletedId = param.reference.id;
    } else if (param is Map && param['instance'] is ActivityInstanceRecord) {
      deletedInstance = param['instance'] as ActivityInstanceRecord;
      deletedId = deletedInstance.reference.id;
    } else if (param is Map && param['instanceId'] is String) {
      deletedId = param['instanceId'] as String;
    }

    if (deletedId == null || deletedId.isEmpty) {
      return;
    }
    if (deletedInstance != null &&
        deletedInstance.templateCategoryType == 'task') {
      _removeFromTaskItemsSnapshot(deletedId);
    } else if (deletedInstance != null &&
        deletedInstance.templateCategoryType == 'habit') {
      _removeFromHabitItemsSnapshot(deletedId);
    }

    if (deletedInstance != null &&
        _extractUserIdFromPath(deletedInstance.reference.path) !=
            existing.userId) {
      return;
    }

    if (!existing.instancesById.containsKey(deletedId)) {
      return;
    }

    final updated =
        Map<String, ActivityInstanceRecord>.from(existing.instancesById)
          ..remove(deletedId);
    _snapshot = existing.copyWith(
      instancesById: updated,
      hydratedAt: DateTime.now(),
    );
    _revision++;
    notifyListeners();
  }

  void _handleInstanceRollback(Object? param) {
    if (param is! Map) {
      return;
    }
    // Rollback may restore the original or remove an optimistic create.
    final existing = _snapshot;
    if (existing == null) {
      return;
    }

    final original = param['originalInstance'] as ActivityInstanceRecord?;
    if (original != null) {
      _applyUpsertFromEvent({'instance': original});
      return;
    }

    final operationType = param['operationType'] as String?;
    final instanceId = param['instanceId'] as String?;
    if (operationType == 'create' &&
        instanceId != null &&
        instanceId.isNotEmpty) {
      final updated =
          Map<String, ActivityInstanceRecord>.from(existing.instancesById)
            ..remove(instanceId);
      _snapshot = existing.copyWith(
        instancesById: updated,
        hydratedAt: DateTime.now(),
      );
      _revision++;
      notifyListeners();
    }
  }

  bool _isRelevantForToday(
    ActivityInstanceRecord instance,
    TodayInstanceSnapshot snapshot,
  ) {
    final dayStart = snapshot.dayStart;
    final dayEnd = snapshot.dayEnd;
    final recentThreshold = dayStart.subtract(const Duration(days: 2));
    final type = instance.templateCategoryType;

    if (type == 'task') {
      if (instance.status == 'pending') {
        return TodayInstanceSelectors.isTaskDueTodayOrOverdue(
            instance, dayStart);
      }
      final ts = TodayInstanceSelectors.statusTimestamp(instance);
      return ts != null && !ts.isBefore(recentThreshold);
    }

    if (type == 'habit') {
      if (TodayInstanceSelectors.isHabitWindowLive(instance, dayStart)) {
        return true;
      }
      if (instance.status == 'pending') {
        return true;
      }
      final ts = TodayInstanceSelectors.statusTimestamp(instance);
      return ts != null && !ts.isBefore(recentThreshold);
    }

    if (type == 'essential') {
      final belongsToday =
          TodayInstanceSelectors.isSameDay(instance.belongsToDate, dayStart);
      final sessionToday =
          TodayInstanceSelectors.hasSessionOnDay(instance, dayStart, dayEnd);
      final completedToday =
          TodayInstanceSelectors.isSameDay(instance.completedAt, dayStart);
      if (belongsToday || sessionToday || completedToday) {
        return true;
      }
      final ts = TodayInstanceSelectors.statusTimestamp(instance);
      return ts != null && !ts.isBefore(recentThreshold);
    }

    return false;
  }

  String _extractUserIdFromPath(String path) {
    final parts = path.split('/');
    final usersIndex = parts.indexOf('users');
    if (usersIndex >= 0 && usersIndex + 1 < parts.length) {
      return parts[usersIndex + 1];
    }
    return '';
  }

  List<ActivityInstanceRecord>? _taskItemsIfValid() {
    final items = _taskItemsSnapshot;
    final dayStart = _taskItemsDayStart;
    if (items == null || dayStart == null) {
      return null;
    }
    if (!dayStart.isAtSameMomentAs(DateService.todayStart)) {
      return null;
    }
    final snapshotUserId = _snapshot?.userId;
    if (snapshotUserId != null &&
        snapshotUserId.isNotEmpty &&
        snapshotUserId != _taskItemsUserId) {
      return null;
    }
    return List<ActivityInstanceRecord>.from(items);
  }

  bool _isTaskItemsSnapshotValidFor({
    required String userId,
    required DateTime dayStart,
  }) {
    final items = _taskItemsSnapshot;
    final cachedDay = _taskItemsDayStart;
    if (items == null || cachedDay == null) {
      return false;
    }
    return _taskItemsUserId == userId && cachedDay.isAtSameMomentAs(dayStart);
  }

  List<ActivityInstanceRecord>? _habitItemsIfValid() {
    final items = _habitItemsSnapshot;
    final dayStart = _habitItemsDayStart;
    if (items == null || dayStart == null) {
      return null;
    }
    if (!dayStart.isAtSameMomentAs(DateService.todayStart)) {
      return null;
    }
    final snapshotUserId = _snapshot?.userId;
    if (snapshotUserId != null &&
        snapshotUserId.isNotEmpty &&
        snapshotUserId != _habitItemsUserId) {
      return null;
    }
    return List<ActivityInstanceRecord>.from(items);
  }

  bool _isHabitItemsSnapshotValidFor({
    required String userId,
    required DateTime dayStart,
  }) {
    final items = _habitItemsSnapshot;
    final cachedDay = _habitItemsDayStart;
    if (items == null || cachedDay == null) {
      return false;
    }
    return _habitItemsUserId == userId && cachedDay.isAtSameMomentAs(dayStart);
  }

  Future<List<ActivityInstanceRecord>> _ensureTaskItemsHydrated({
    required String userId,
    bool forceRefresh = false,
  }) async {
    final dayStart = DateService.todayStart;
    final cacheKey = _buildHydrationKey(userId: userId, dayStart: dayStart);

    if (!forceRefresh &&
        _isTaskItemsSnapshotValidFor(userId: userId, dayStart: dayStart)) {
      return _taskItemsSnapshot!;
    }

    if (_inFlightTaskHydration != null &&
        _inFlightTaskHydrationKey == cacheKey) {
      return _inFlightTaskHydration!;
    }

    final hydrationFuture = ActivityInstanceService.getAllTaskInstances(
      userId: userId,
    );
    _inFlightTaskHydration = hydrationFuture;
    _inFlightTaskHydrationKey = cacheKey;

    try {
      final hydrated = await hydrationFuture;
      _taskItemsSnapshot = hydrated;
      _taskItemsUserId = userId;
      _taskItemsDayStart = dayStart;
      return hydrated;
    } finally {
      if (_inFlightTaskHydrationKey == cacheKey) {
        _inFlightTaskHydration = null;
        _inFlightTaskHydrationKey = null;
      }
    }
  }

  Future<List<ActivityInstanceRecord>> _ensureHabitItemsHydrated({
    required String userId,
    bool forceRefresh = false,
  }) async {
    final dayStart = DateService.todayStart;
    final cacheKey = _buildHydrationKey(userId: userId, dayStart: dayStart);

    if (!forceRefresh &&
        _isHabitItemsSnapshotValidFor(userId: userId, dayStart: dayStart)) {
      return _habitItemsSnapshot!;
    }

    if (_inFlightHabitHydration != null &&
        _inFlightHabitHydrationKey == cacheKey) {
      return _inFlightHabitHydration!;
    }

    final hydrationFuture = ActivityInstanceService.getAllHabitInstances(
      userId: userId,
    );
    _inFlightHabitHydration = hydrationFuture;
    _inFlightHabitHydrationKey = cacheKey;

    try {
      final hydrated = await hydrationFuture;
      _habitItemsSnapshot = hydrated;
      _habitItemsUserId = userId;
      _habitItemsDayStart = dayStart;
      return hydrated;
    } finally {
      if (_inFlightHabitHydrationKey == cacheKey) {
        _inFlightHabitHydration = null;
        _inFlightHabitHydrationKey = null;
      }
    }
  }

  void _clearTaskItemsSnapshot() {
    _taskItemsSnapshot = null;
    _inFlightTaskHydration = null;
    _inFlightTaskHydrationKey = null;
    _taskItemsUserId = null;
    _taskItemsDayStart = null;
    _habitItemsSnapshot = null;
    _inFlightHabitHydration = null;
    _inFlightHabitHydrationKey = null;
    _habitItemsUserId = null;
    _habitItemsDayStart = null;
  }

  void _upsertTaskItemsSnapshot(ActivityInstanceRecord instance) {
    final items = _taskItemsSnapshot;
    if (items == null) return;
    final id = instance.reference.id;
    final index = items.indexWhere((i) => i.reference.id == id);
    if (index >= 0) {
      items[index] = instance;
    } else {
      items.add(instance);
    }
  }

  void _removeFromTaskItemsSnapshot(String instanceId) {
    _taskItemsSnapshot?.removeWhere((i) => i.reference.id == instanceId);
  }

  void _upsertHabitItemsSnapshot(ActivityInstanceRecord instance) {
    final items = _habitItemsSnapshot;
    if (items == null) return;
    final id = instance.reference.id;
    final index = items.indexWhere((i) => i.reference.id == id);
    if (index >= 0) {
      items[index] = instance;
    } else {
      items.add(instance);
    }
  }

  void _removeFromHabitItemsSnapshot(String instanceId) {
    _habitItemsSnapshot?.removeWhere((i) => i.reference.id == instanceId);
  }
}
