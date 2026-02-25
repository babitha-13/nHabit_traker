import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/features/Queue/Queue_filter/queue_filter_state_manager.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';

/// Service class for loading queue data
class QueueDataService {
  static Future<List<ActivityInstanceRecord>> _loadQueueInstancesFromRepo({
    required String userId,
    bool forceRefresh = false,
  }) async {
    final repo = TodayInstanceRepository.instance;
    if (forceRefresh) {
      await repo.refreshToday(userId: userId);
    } else {
      await repo.ensureHydrated(userId: userId);
    }
    return repo.selectQueueItems();
  }

  /// Load all queue data (instances and categories)
  static Future<QueueDataResult> loadQueueData({
    required String userId,
  }) async {
    if (userId.isEmpty) {
      return QueueDataResult(
        instances: [],
        categories: [],
        filterState: QueueFilterState(),
      );
    }

    try {
      // Batch Firestore queries in parallel for faster loading
      final results = await Future.wait<dynamic>([
        _loadQueueInstancesFromRepo(userId: userId),
        queryHabitCategoriesOnce(
          userId: userId,
          callerTag: 'QueuePage._loadData.habits',
        ),
        queryTaskCategoriesOnce(
          userId: userId,
          callerTag: 'QueuePage._loadData.tasks',
        ),
      ]);

      final allInstances = results[0] as List<ActivityInstanceRecord>;
      final habitCategories = results[1] as List<CategoryRecord>;
      final taskCategories = results[2] as List<CategoryRecord>;
      final allCategories = [...habitCategories, ...taskCategories];

      // Deduplicate instances by reference ID to prevent duplicates
      final uniqueInstances = <String, ActivityInstanceRecord>{};
      for (final instance in allInstances) {
        uniqueInstances[instance.reference.id] = instance;
      }
      final deduplicatedInstances = uniqueInstances.values.toList();

      // Initialize default filter state (all categories selected) if filter is empty
      final allHabitNames = habitCategories.map((cat) => cat.name).toSet();
      final allTaskNames = taskCategories.map((cat) => cat.name).toSet();

      final defaultFilter = QueueFilterState(
        allTasks: true,
        allHabits: true,
        selectedHabitCategoryNames: allHabitNames,
        selectedTaskCategoryNames: allTaskNames,
      );

      return QueueDataResult(
        instances: deduplicatedInstances,
        categories: allCategories,
        filterState: defaultFilter,
      );
    } catch (e) {
      rethrow;
    }
  }

  /// Silent refresh instances without loading indicator
  static Future<QueueDataResult> silentRefreshInstances({
    required String userId,
  }) async {
    if (userId.isEmpty) {
      return QueueDataResult(
        instances: [],
        categories: [],
        filterState: QueueFilterState(),
      );
    }

    // Batch queries in parallel for faster loading
    final results = await Future.wait<dynamic>([
      _loadQueueInstancesFromRepo(
        userId: userId,
        forceRefresh: true,
      ),
      queryHabitCategoriesOnce(
        userId: userId,
        callerTag: 'QueuePage._silentRefreshInstances.habits',
      ),
      queryTaskCategoriesOnce(
        userId: userId,
        callerTag: 'QueuePage._silentRefreshInstances.tasks',
      ),
    ]);

    final allInstances = results[0] as List<ActivityInstanceRecord>;
    final habitCategories = results[1] as List<CategoryRecord>;
    final taskCategories = results[2] as List<CategoryRecord>;
    final allCategories = [...habitCategories, ...taskCategories];

    // Deduplicate instances by reference ID to prevent duplicates
    final uniqueInstances = <String, ActivityInstanceRecord>{};
    for (final instance in allInstances) {
      uniqueInstances[instance.reference.id] = instance;
    }
    final deduplicatedInstances = uniqueInstances.values.toList();

    return QueueDataResult(
      instances: deduplicatedInstances,
      categories: allCategories,
      filterState: QueueFilterState(),
    );
  }
}

/// Result class for queue data loading
class QueueDataResult {
  final List<ActivityInstanceRecord> instances;
  final List<CategoryRecord> categories;
  final QueueFilterState filterState;

  QueueDataResult({
    required this.instances,
    required this.categories,
    required this.filterState,
  });
}
