import 'dart:convert';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Screens/Queue/Queue_filter/queue_filter_state_manager.dart';
import 'package:habit_tracker/debug_log_stub.dart'
    if (dart.library.io) 'package:habit_tracker/debug_log_io.dart'
    if (dart.library.html) 'package:habit_tracker/debug_log_web.dart';

// #region agent log
void _logQueueDataDebug(String location, Map<String, dynamic> data) {
  try {
    final logEntry = {
      'id': 'log_${DateTime.now().millisecondsSinceEpoch}_queue_data',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': 'queue_page_refresh.dart:$location',
      'message': data['event'] ?? 'debug',
      'data': data,
      'sessionId': 'debug-session',
      'runId': 'run2',
    };
    writeDebugLog(jsonEncode(logEntry));
  } catch (_) {
    // Silently fail
  }
}
// #endregion

/// Service class for loading queue data
class QueueDataService {
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
      // #region agent log
      _logQueueDataDebug('loadQueueData', {
        'hypothesisId': 'O',
        'event': 'load_start',
        'userIdLength': userId.length,
      });
      // #endregion
      // Batch Firestore queries in parallel for faster loading
      final results = await Future.wait([
        queryAllInstances(userId: userId),
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

      // #region agent log
      _logQueueDataDebug('loadQueueData', {
        'hypothesisId': 'O',
        'event': 'load_complete',
        'instancesCount': deduplicatedInstances.length,
        'categoriesCount': allCategories.length,
      });
      // #endregion

      return QueueDataResult(
        instances: deduplicatedInstances,
        categories: allCategories,
        filterState: defaultFilter,
      );
    } catch (e) {
      // #region agent log
      _logQueueDataDebug('loadQueueData', {
        'hypothesisId': 'O',
        'event': 'load_error',
        'errorType': e.runtimeType.toString(),
      });
      // #endregion
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

    // Batch Firestore queries in parallel for faster loading
    final results = await Future.wait([
      queryAllInstances(userId: userId),
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
