import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/features/Progress/Statemanagement/today_progress_state.dart';
import 'package:habit_tracker/features/Progress/backend/daily_progress_query_service.dart';
import 'package:habit_tracker/features/Shared/Points_and_Scores/daily_points_calculator.dart';

/// Service to fetch data needed by Progress page UI
/// Encapsulates Firestore access for progress page to maintain separation of concerns
class ProgressPageDataService {
  /// Fetch all instances needed for breakdown/score calculation.
  /// Uses cache first to avoid redundant reads.
  static Future<Map<String, dynamic>> fetchInstancesForBreakdown({
    required String userId,
    bool useCacheOnly = false,
  }) async {
    final cache = FirestoreCacheService();

    List<ActivityInstanceRecord>? habits = cache.getCachedHabitInstances();
    List<ActivityInstanceRecord>? tasks = cache.getCachedTaskInstances();
    List<CategoryRecord>? categories = cache.getCachedHabitCategories();

    final cachedAll = cache.getCachedAllInstances();
    habits ??= cachedAll
        ?.where((inst) => inst.templateCategoryType == 'habit')
        .toList();
    tasks ??= cachedAll
        ?.where((inst) => inst.templateCategoryType == 'task')
        .toList();

    if (habits != null && tasks != null && categories != null) {
      return {
        'habits': habits,
        'tasks': tasks,
        'categories': categories,
      };
    }

    if (useCacheOnly) {
      return {
        'habits': habits ?? <ActivityInstanceRecord>[],
        'tasks': tasks ?? <ActivityInstanceRecord>[],
        'categories': categories ?? <CategoryRecord>[],
      };
    }

    try {
      final fetches = <Future<void>>[];

      if (habits == null) {
        fetches.add(() async {
          final habitQuery = ActivityInstanceRecord.collectionForUser(userId)
              .where('templateCategoryType', isEqualTo: 'habit');
          final result = await habitQuery.get();
          habits = result.docs
              .map<ActivityInstanceRecord>(
                (doc) => ActivityInstanceRecord.fromSnapshot(doc),
              )
              .toList();
          cache.cacheHabitInstances(habits!);
        }());
      }

      if (tasks == null) {
        fetches.add(() async {
          final taskQuery = ActivityInstanceRecord.collectionForUser(userId)
              .where('templateCategoryType', isEqualTo: 'task');
          final result = await taskQuery.get();
          tasks = result.docs
              .map<ActivityInstanceRecord>(
                (doc) => ActivityInstanceRecord.fromSnapshot(doc),
              )
              .toList();
          cache.cacheTaskInstances(tasks!);
        }());
      }

      if (categories == null) {
        fetches.add(() async {
          final categoryQuery = CategoryRecord.collectionForUser(userId)
              .where('categoryType', isEqualTo: 'habit');
          final result = await categoryQuery.get();
          categories = result.docs
              .map<CategoryRecord>((doc) => CategoryRecord.fromSnapshot(doc))
              .toList();
          cache.cacheHabitCategories(categories!);
        }());
      }

      if (fetches.isNotEmpty) {
        await Future.wait(fetches);
      }

      final finalHabits = habits ?? <ActivityInstanceRecord>[];
      final finalTasks = tasks ?? <ActivityInstanceRecord>[];
      final finalCategories = categories ?? <CategoryRecord>[];

      if (finalHabits.isNotEmpty || finalTasks.isNotEmpty) {
        cache.cacheAllInstances([...finalHabits, ...finalTasks]);
      }

      return {
        'habits': finalHabits,
        'tasks': finalTasks,
        'categories': finalCategories,
      };
    } catch (_) {
      return {
        'habits': habits ?? <ActivityInstanceRecord>[],
        'tasks': tasks ?? <ActivityInstanceRecord>[],
        'categories': categories ?? <CategoryRecord>[],
      };
    }
  }

  /// Get breakdown for a specific date from stored DailyProgressRecord only.
  /// For today only, if DailyProgressRecord does not exist yet, use already
  /// fetched in-memory data (shared state/cache) without re-fetching.
  static Future<Map<String, dynamic>> calculateBreakdownForDate({
    required String userId,
    required DateTime date,
  }) async {
    final normalizedDate = DateService.normalizeToStartOfDay(date);
    final records = await DailyProgressQueryService.queryDailyProgress(
      userId: userId,
      startDate: normalizedDate,
      endDate: normalizedDate,
      orderDescending: false,
    );
    if (records.isEmpty) {
      final today = DateService.todayStart;
      final isToday = normalizedDate.year == today.year &&
          normalizedDate.month == today.month &&
          normalizedDate.day == today.day;
      if (!isToday) {
        throw Exception(
          'No daily progress record found for ${normalizedDate.toIso8601String().split('T').first}.',
        );
      }

      final sharedBreakdown = TodayProgressState().getTodayActivityBreakdown();
      final sharedHabits =
          sharedBreakdown['habitBreakdown'] as List<Map<String, dynamic>>? ??
              [];
      final sharedTasks =
          sharedBreakdown['taskBreakdown'] as List<Map<String, dynamic>>? ?? [];
      if (sharedHabits.isNotEmpty || sharedTasks.isNotEmpty) {
        return {
          'habitBreakdown': sharedHabits,
          'taskBreakdown': sharedTasks,
          'totalHabits': sharedHabits.length,
          'totalTasks': sharedTasks.length,
        };
      }

      final cachedData = await fetchInstancesForBreakdown(
        userId: userId,
        useCacheOnly: true,
      );
      final cachedHabits =
          cachedData['habits'] as List<ActivityInstanceRecord>? ?? const [];
      final cachedTasks =
          cachedData['tasks'] as List<ActivityInstanceRecord>? ?? const [];
      final cachedCategories =
          cachedData['categories'] as List<CategoryRecord>? ?? const [];

      if (cachedHabits.isEmpty && cachedTasks.isEmpty) {
        throw Exception(
          'Today breakdown is unavailable. Open Queue once to hydrate local cache.',
        );
      }

      final optimistic =
          DailyProgressCalculator.calculateTodayProgressOptimistic(
        userId: userId,
        allInstances: cachedHabits,
        categories: cachedCategories,
        taskInstances: cachedTasks,
      );

      return {
        'habitBreakdown':
            (optimistic['habitBreakdown'] as List<Map<String, dynamic>>?) ??
                <Map<String, dynamic>>[],
        'taskBreakdown':
            (optimistic['taskBreakdown'] as List<Map<String, dynamic>>?) ??
                <Map<String, dynamic>>[],
        'totalHabits': optimistic['totalHabits'] as int? ?? cachedHabits.length,
        'totalTasks': optimistic['totalTasks'] as int? ?? cachedTasks.length,
      };
    }

    final record = records.first;
    return {
      'habitBreakdown': List<Map<String, dynamic>>.from(record.habitBreakdown),
      'taskBreakdown': List<Map<String, dynamic>>.from(record.taskBreakdown),
      'totalHabits': record.totalHabits,
      'totalTasks': record.totalTasks,
    };
  }

  /// Fetch progress history for a date range
  /// Returns list of DailyProgressRecord sorted by date descending
  static Future<List<DailyProgressRecord>> fetchProgressHistory({
    required String userId,
    required int days,
  }) async {
    try {
      final endDate = DateService.currentDate;
      final startDate = endDate.subtract(Duration(days: days));
      return await DailyProgressQueryService.queryDailyProgress(
        userId: userId,
        startDate: startDate,
        endDate: endDate,
        orderDescending: true,
      );
    } catch (e) {
      return [];
    }
  }

  /// Fetch cumulative score history for the last 30 days
  /// Returns list of maps with 'date', 'score', 'gain'
  ///
  /// NOTE: Moved to `lib/Screens/Shared/cumulative_score_calculator.dart`
  /// to avoid duplication with Queue.
}
