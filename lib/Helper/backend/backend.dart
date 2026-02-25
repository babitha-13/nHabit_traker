import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/backend/schema/work_session_record.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/activity_update_broadcast.dart';
import 'package:habit_tracker/core/utils/Date_time/date_service.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/services/Activtity/instance_date_calculator.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Helper/backend/cache/firestore_cache_service.dart';
import 'package:habit_tracker/services/resource_tracker.dart';
import 'package:habit_tracker/Helper/backend/firestore_error_logger.dart';

/// Functions to query UsersRecords (as a Stream and as a Future).
Future<int> queryUsersRecordCount({
  Query Function(Query)? queryBuilder,
  int limit = -1,
}) =>
    queryCollectionCount(
      UsersRecord.collection,
      queryBuilder: queryBuilder,
      limit: limit,
    );
Stream<List<UsersRecord>> queryUsersRecord({
  Query Function(Query)? queryBuilder,
  int limit = -1,
  bool singleRecord = false,
}) =>
    queryCollection(
      UsersRecord.collection,
      UsersRecord.fromSnapshot,
      queryBuilder: queryBuilder,
      limit: limit,
      singleRecord: singleRecord,
    );
Future<List<UsersRecord>> queryUsersRecordOnce({
  Query Function(Query)? queryBuilder,
  int limit = -1,
  bool singleRecord = false,
}) =>
    queryCollectionOnce(
      UsersRecord.collection,
      UsersRecord.fromSnapshot,
      queryBuilder: queryBuilder,
      limit: limit,
      singleRecord: singleRecord,
    );
String _getQueryCollectionName(Query query) {
  if (query is CollectionReference) {
    return query.path;
  }
  return query.toString();
}

final Map<String, Future<dynamic>> _inFlightQueryFutures = {};

Future<T> _runWithInFlightDedupe<T>(
  String key,
  Future<T> Function() fetcher,
) async {
  final existing = _inFlightQueryFutures[key];
  if (existing != null) {
    return existing as Future<T>;
  }

  final future = fetcher();
  _inFlightQueryFutures[key] = future;

  try {
    return await future;
  } finally {
    if (identical(_inFlightQueryFutures[key], future)) {
      _inFlightQueryFutures.remove(key);
    }
  }
}

Future<int> queryCollectionCount(
  Query collection, {
  Query Function(Query)? queryBuilder,
  int limit = -1,
  String? queryDescription,
}) async {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0) {
    query = query.limit(limit);
  }
  try {
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  } catch (err, stackTrace) {
    logFirestoreQueryError(
      err,
      queryDescription: queryDescription ?? 'queryCollectionCount',
      collectionName: _getQueryCollectionName(query),
      stackTrace: stackTrace,
    );
    return 0;
  }
}

Stream<List<T>> queryCollection<T>(
  Query collection,
  RecordBuilder<T> recordBuilder, {
  Query Function(Query)? queryBuilder,
  int limit = -1,
  bool singleRecord = false,
  String? queryDescription,
}) {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0 || singleRecord) {
    query = query.limit(singleRecord ? 1 : limit);
  }
  // #region agent log - Track Firestore listener creation
  ResourceTracker.incrementFirestoreListener();
  // #endregion
  return query.snapshots().handleError((err, stackTrace) {
    // #region agent log
    ResourceTracker.decrementFirestoreListener();
    // #endregion
    logFirestoreQueryError(
      err,
      queryDescription: queryDescription ?? 'queryCollection',
      collectionName: _getQueryCollectionName(query),
      stackTrace: stackTrace,
    );
  }).map((s) => s.docs
      .map(
        (d) => safeGet(
          () => recordBuilder(d),
          (e) {},
        ),
      )
      .where((d) => d != null)
      .map((d) => d!)
      .toList());
}

Future<List<T>> queryCollectionOnce<T>(
  Query collection,
  RecordBuilder<T> recordBuilder, {
  Query Function(Query)? queryBuilder,
  int limit = -1,
  bool singleRecord = false,
  String? queryDescription,
}) {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0 || singleRecord) {
    query = query.limit(singleRecord ? 1 : limit);
  }
  return query
      .get()
      .then((s) => s.docs
          .map(
            (d) => safeGet(
              () => recordBuilder(d),
              (e) {},
            ),
          )
          .where((d) => d != null)
          .map((d) => d!)
          .toList())
      .catchError((err, stackTrace) {
    logFirestoreQueryError(
      err,
      queryDescription: queryDescription ?? 'queryCollectionOnce',
      collectionName: _getQueryCollectionName(query),
      stackTrace: stackTrace,
    );
    return <T>[];
  });
}

Filter filterIn(String field, List? list) => (list?.isEmpty ?? true)
    ? Filter(field, whereIn: null)
    : Filter(field, whereIn: list);

Filter filterArrayContainsAny(String field, List? list) =>
    (list?.isEmpty ?? true)
        ? Filter(field, arrayContainsAny: null)
        : Filter(field, arrayContainsAny: list);

extension QueryExtension on Query {
  Query whereIn(String field, List? list) => (list?.isEmpty ?? true)
      ? where(field, whereIn: null)
      : where(field, whereIn: list);
  Query whereNotIn(String field, List? list) => (list?.isEmpty ?? true)
      ? where(field, whereNotIn: null)
      : where(field, whereNotIn: list);
  Query whereArrayContainsAny(String field, List? list) =>
      (list?.isEmpty ?? true)
          ? where(field, arrayContainsAny: null)
          : where(field, arrayContainsAny: list);
}

class FFFirestorePage<T> {
  final List<T> data;
  final Stream<List<T>>? dataStream;
  final QueryDocumentSnapshot? nextPageMarker;
  FFFirestorePage(this.data, this.dataStream, this.nextPageMarker);
}

Future<FFFirestorePage<T>> queryCollectionPage<T>(
  Query collection,
  RecordBuilder<T> recordBuilder, {
  Query Function(Query)? queryBuilder,
  DocumentSnapshot? nextPageMarker,
  required int pageSize,
  required bool isStream,
  String? queryDescription,
}) async {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection).limit(pageSize);
  if (nextPageMarker != null) {
    query = query.startAfterDocument(nextPageMarker);
  }
  try {
    Stream<QuerySnapshot>? docSnapshotStream;
    QuerySnapshot docSnapshot;
    if (isStream) {
      docSnapshotStream = query.snapshots();
      docSnapshot = await docSnapshotStream.first;
    } else {
      docSnapshot = await query.get();
    }
    getDocs(QuerySnapshot s) => s.docs
        .map(
          (d) => safeGet(
            () => recordBuilder(d),
            (e) {},
          ),
        )
        .where((d) => d != null)
        .map((d) => d!)
        .toList();
    final data = getDocs(docSnapshot);
    final dataStream = docSnapshotStream?.map(getDocs);
    final nextPageToken =
        docSnapshot.docs.isEmpty ? null : docSnapshot.docs.last;
    return FFFirestorePage(data, dataStream, nextPageToken);
  } catch (err, stackTrace) {
    logFirestoreQueryError(
      err,
      queryDescription: queryDescription ?? 'queryCollectionPage',
      collectionName: _getQueryCollectionName(query),
      stackTrace: stackTrace,
    );
    return FFFirestorePage(<T>[], null, null);
  }
}

// Creates a Firestore document representing the logged in user if it doesn't yet exist
Future maybeCreateUser(User user) async {
  try {
    // Add a small delay to ensure user is fully authenticated
    await Future.delayed(const Duration(milliseconds: 500));
    final userRecord = UsersRecord.collection.doc(user.uid);
    final userExists = await userRecord.get().then((u) => u.exists);
    if (userExists) {
      currentUserDocument = await UsersRecord.getDocumentOnce(userRecord);
      return;
    }
    final userData = createUsersRecordData(
      email: user.email ??
          FirebaseAuth.instance.currentUser?.email ??
          user.providerData.firstOrNull?.email,
      displayName:
          user.displayName ?? FirebaseAuth.instance.currentUser?.displayName,
      photoUrl: user.photoURL,
      uid: user.uid,
      phoneNumber: user.phoneNumber,
      createdTime: getCurrentTimestamp,
      goalPromptSkipped: false,
      goalOnboardingCompleted: false,
    );
    await userRecord.set(userData);
    currentUserDocument = UsersRecord.getDocumentFromData(userData, userRecord);

    // Create default system categories for the new user
    try {
      await getOrCreateInboxCategory(userId: user.uid);
      await getOrCreateEssentialDefaultCategory(userId: user.uid);
    } catch (e) {
      print('Error creating default categories for new user: $e');
      // Non-critical error, don't fail user creation
    }
  } catch (e) {
    rethrow;
  }
}

Future updateUserDocument({String? email}) async {
  await currentUserDocument?.reference
      .update(createUsersRecordData(email: email));
}

/// Helper function to check if a habit is active based on date boundaries
bool isHabitActiveByDate(ActivityRecord habit, DateTime currentDate) {
  // Check if habit has started (startDate <= currentDate)
  // Compare only the date part, not the time
  if (habit.startDate != null) {
    final habitStartDate = DateTime(
        habit.startDate!.year, habit.startDate!.month, habit.startDate!.day);
    if (habitStartDate.isAfter(currentDate)) {
      return false; // Habit hasn't started yet
    }
  }
  // Check if habit has ended (endDate < currentDate)
  // Compare only the date part, not the time
  if (habit.endDate != null) {
    final habitEndDate =
        DateTime(habit.endDate!.year, habit.endDate!.month, habit.endDate!.day);
    if (habitEndDate.isBefore(currentDate)) {
      return false; // Habit has ended
    }
  }
  return true; // Habit is active within date range
}

/// Query to get habits for a specific user
Future<List<ActivityRecord>> queryActivitiesRecordOnce({
  required String userId,
  bool includeEssentialItems = false,
}) async {
  try {
    // Use simple query without orderBy to avoid Firestore composite index requirements
    final query = ActivityRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true);
    final result = await query.get();
    final activities =
        result.docs.map((doc) => ActivityRecord.fromSnapshot(doc)).toList();
    // Filter out essential types unless explicitly requested
    final filteredActivities = activities.where((activity) {
      if (!includeEssentialItems && activity.categoryType == 'essential') {
        return false;
      }
      return true;
    }).toList();
    // Filter habits based on date boundaries (skip for Essential Activities)
    final today = DateService.todayStart;
    final activeHabits = filteredActivities.where((habit) {
      // Essential Activities don't have date boundaries, always include them
      if (habit.categoryType == 'essential') {
        return true;
      }
      return isHabitActiveByDate(habit, today);
    }).toList();
    // Sort in memory instead of in query
    activeHabits.sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
    return activeHabits;
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryActivitiesRecordOnce',
      collectionName: 'activities',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get categories for a specific user
Future<List<CategoryRecord>> queryCategoriesRecordOnce({
  required String userId,
  String callerTag = 'queryCategoriesRecordOnce',
}) async {
  // Validate userId before attempting query
  if (userId.isEmpty) {
    return [];
  }
  try {
    return await _runWithInFlightDedupe<List<CategoryRecord>>(
      'queryCategoriesRecordOnce:$userId',
      () async {
        // Use simple query without orderBy to avoid Firestore composite index requirements
        final query = CategoryRecord.collectionForUser(userId)
            .where('isActive', isEqualTo: true);
        final result = await query.get();
        final categories =
            result.docs.map((doc) => CategoryRecord.fromSnapshot(doc)).toList();
        // Sort in memory instead of in query
        categories.sort((a, b) => a.name.compareTo(b.name));
        return categories;
      },
    );
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryCategoriesRecordOnce ($callerTag)',
      collectionName: 'categories',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get habit categories for a specific user
/// Uses cache to reduce redundant Firestore reads
Future<List<CategoryRecord>> queryHabitCategoriesOnce({
  required String userId,
  String callerTag = 'queryHabitCategoriesOnce',
}) async {
  try {
    final cache = FirestoreCacheService();
    // Check cache first
    final cached = cache.getCachedHabitCategories();
    if (cached != null) {
      return cached;
    }
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(
      userId: userId,
      callerTag: callerTag,
    );
    // Filter in memory (no Firestore index needed)
    final habitCategories =
        allCategories.where((c) => c.categoryType == 'habit').toList();
    // Sort in memory
    habitCategories.sort((a, b) => a.name.compareTo(b.name));
    // Update cache
    cache.cacheHabitCategories(habitCategories);
    return habitCategories;
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryHabitCategoriesOnce',
      collectionName: 'categories',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get task categories for a specific user
/// Uses cache to reduce redundant Firestore reads
Future<List<CategoryRecord>> queryTaskCategoriesOnce({
  required String userId,
  String callerTag = 'queryTaskCategoriesOnce',
}) async {
  try {
    final cache = FirestoreCacheService();
    // Check cache first
    final cached = cache.getCachedTaskCategories();
    if (cached != null) {
      return cached;
    }
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(
      userId: userId,
      callerTag: callerTag,
    );
    // Filter in memory (no Firestore index needed)
    final taskCategories =
        allCategories.where((c) => c.categoryType == 'task').toList();
    // Sort in memory
    taskCategories.sort((a, b) => a.name.compareTo(b.name));
    // Update cache
    cache.cacheTaskCategories(taskCategories);
    return taskCategories;
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryTaskCategoriesOnce',
      collectionName: 'categories',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get essential categories for a specific user
Future<List<CategoryRecord>> queryEssentialCategoriesOnce({
  required String userId,
  String callerTag = 'queryEssentialCategoriesOnce',
}) async {
  try {
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(
      userId: userId,
      callerTag: callerTag,
    );
    // Filter in memory (no Firestore index needed)
    final essentialCategories =
        allCategories.where((c) => c.categoryType == 'essential').toList();
    // Sort in memory
    essentialCategories.sort((a, b) => a.name.compareTo(b.name));
    return essentialCategories;
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryEssentialCategoriesOnce',
      collectionName: 'categories',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get today's task instances (current and overdue)
/// This is the main function to use for displaying active tasks to users
/// TODO: Phase 2 - Implement with ActivityInstanceService
Future<List<ActivityInstanceRecord>> queryTaskInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getActiveTaskInstances(userId: userId);
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryTaskInstances',
      collectionName: 'activity_instances',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get all task instances (active and completed) for Recent Completions
/// Uses cache to reduce redundant Firestore reads unless explicitly bypassed
@Deprecated(
  'Migration-only wrapper. Use ActivityInstanceService.getAllTaskInstances '
  'or TodayInstanceRepository selectors instead.',
)
Future<List<ActivityInstanceRecord>> queryAllTaskInstances({
  required String userId,
  bool useCache = true,
}) async {
  try {
    return await _runWithInFlightDedupe<List<ActivityInstanceRecord>>(
      'queryAllTaskInstances:$userId:$useCache',
      () async {
        final cache = FirestoreCacheService();
        // Check cache first
        if (useCache) {
          final cached = cache.getCachedTaskInstances();
          if (cached != null) {
            return cached;
          }
        }
        // Fetch from Firestore if cache miss
        final instances =
            await ActivityInstanceService.getAllTaskInstances(userId: userId);
        // Update cache if allowed
        if (useCache) {
          cache.cacheTaskInstances(instances);
        }
        return instances;
      },
    );
  } catch (e, stackTrace) {
    print('🔴 queryAllTaskInstances: ERROR - $e');
    print('🔴 queryAllTaskInstances: StackTrace: $stackTrace');
    logFirestoreQueryError(
      e,
      queryDescription: 'queryAllTaskInstances',
      collectionName: 'activity_instances',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get today's habit instances (current and overdue)
/// This is the main function to use for displaying active habits to users
/// TODO: Phase 2 - Implement with ActivityInstanceService
Future<List<ActivityInstanceRecord>> queryTodaysHabitInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getActiveHabitInstances(
        userId: userId);
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryTodaysHabitInstances',
      collectionName: 'activity_instances',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get current habit instances for Habits page (no future instances)
/// Only shows instances whose window includes today
@Deprecated(
  'Migration-only wrapper. Use ActivityInstanceService.getCurrentHabitInstances '
  'or TodayInstanceRepository selectors instead.',
)
Future<List<ActivityInstanceRecord>> queryCurrentHabitInstances({
  required String userId,
}) async {
  try {
    return await _runWithInFlightDedupe<List<ActivityInstanceRecord>>(
      'queryCurrentHabitInstances:$userId',
      () => ActivityInstanceService.getCurrentHabitInstances(userId: userId),
    );
  } catch (e, stackTrace) {
    logFirestoreQueryError(
      e,
      queryDescription: 'queryCurrentHabitInstances',
      collectionName: 'activity_instances',
      stackTrace: stackTrace,
    );
    return []; // Return empty list on error
  }
}

/// Query to get all habit instances for Habits page (all dates and statuses)
/// Shows complete view of all habits regardless of window or status
/// Uses cache to reduce redundant Firestore reads
Future<List<ActivityInstanceRecord>> queryAllHabitInstances({
  required String userId,
}) async {
  try {
    return await _runWithInFlightDedupe<List<ActivityInstanceRecord>>(
      'queryAllHabitInstances:$userId',
      () async {
        final cache = FirestoreCacheService();
        // Check cache first
        final cached = cache.getCachedHabitInstances();
        if (cached != null) {
          return cached;
        }

        final cachedAllInstances = cache.getCachedAllInstances();
        if (cachedAllInstances != null) {
          final derivedHabits =
              _derivePendingHabitInstancesFromAllInstances(cachedAllInstances);
          cache.cacheHabitInstances(derivedHabits);
          return derivedHabits;
        }

        // Fetch from Firestore if cache miss
        final instances =
            await ActivityInstanceService.getAllHabitInstances(userId: userId);
        // Update cache
        cache.cacheHabitInstances(instances);
        return instances;
      },
    );
  } catch (e) {
    return []; // Return empty list on error
  }
}

/// Query to get latest habit instance per template for Habits page
/// Returns one instance per habit template - the next upcoming/actionable instance
/// Uses cache to reduce redundant Firestore reads
@Deprecated(
  'Migration-only wrapper. Use '
  'ActivityInstanceService.getLatestHabitInstancePerTemplate '
  'or TodayInstanceRepository selectors instead.',
)
Future<List<ActivityInstanceRecord>> queryLatestHabitInstances({
  required String userId,
}) async {
  try {
    return await _runWithInFlightDedupe<List<ActivityInstanceRecord>>(
      'queryLatestHabitInstances:$userId',
      () async {
        final cache = FirestoreCacheService();
        // Check cache first - if we have cached habit instances, compute "latest per template" from cache
        final cached = cache.getCachedHabitInstances();
        if (cached != null) {
          // Compute "latest per template" from cached instances (no Firestore read needed)
          return _computeLatestHabitInstancePerTemplate(cached);
        }

        final cachedAllInstances = cache.getCachedAllInstances();
        if (cachedAllInstances != null) {
          final derivedHabits =
              _derivePendingHabitInstancesFromAllInstances(cachedAllInstances);
          cache.cacheHabitInstances(derivedHabits);
          return _computeLatestHabitInstancePerTemplate(derivedHabits);
        }

        // Cache miss - fetch all habit instances, cache them, then compute
        final allInstances =
            await ActivityInstanceService.getAllHabitInstances(userId: userId);
        // Update cache
        cache.cacheHabitInstances(allInstances);
        // Compute "latest per template" from fetched instances
        return _computeLatestHabitInstancePerTemplate(allInstances);
      },
    );
  } catch (e) {
    return []; // Return empty list on error
  }
}

List<ActivityInstanceRecord> _derivePendingHabitInstancesFromAllInstances(
  List<ActivityInstanceRecord> allInstances,
) {
  final pendingHabits = allInstances
      .where((inst) => inst.templateCategoryType == 'habit')
      .where((inst) => inst.status == 'pending')
      .where((inst) => inst.isActive)
      .toList();

  pendingHabits.sort((a, b) {
    final bUpdated = b.lastUpdated ?? DateTime(0);
    final aUpdated = a.lastUpdated ?? DateTime(0);
    return bUpdated.compareTo(aUpdated);
  });

  return pendingHabits;
}

/// Helper function to compute latest habit instance per template from a list of instances
/// This logic is extracted from ActivityInstanceService.getLatestHabitInstancePerTemplate
/// to allow computation from cached data without re-fetching from Firestore
List<ActivityInstanceRecord> _computeLatestHabitInstancePerTemplate(
    List<ActivityInstanceRecord> allHabitInstances) {
  // Group instances by templateId
  final Map<String, List<ActivityInstanceRecord>> instancesByTemplate = {};
  for (final instance in allHabitInstances) {
    final templateId = instance.templateId;
    (instancesByTemplate[templateId] ??= []).add(instance);
  }
  final List<ActivityInstanceRecord> latestInstances = [];
  for (final templateId in instancesByTemplate.keys) {
    final instances = instancesByTemplate[templateId]!;
    // Sort instances by due date (earliest first, nulls last)
    instances.sort((a, b) {
      if (a.dueDate == null && b.dueDate == null) return 0;
      if (a.dueDate == null) return 1;
      if (b.dueDate == null) return -1;
      return a.dueDate!.compareTo(b.dueDate!);
    });
    // Find the latest instance for this template
    ActivityInstanceRecord? latestInstance;
    // First, try to find the earliest pending instance (next upcoming)
    for (final instance in instances) {
      if (instance.status == 'pending') {
        latestInstance = instance;
        break;
      }
    }
    // If no pending instance found, use the latest completed instance
    if (latestInstance == null) {
      // Find the most recent completed/skipped instance
      for (final instance in instances.reversed) {
        if (instance.status == 'completed' || instance.status == 'skipped') {
          latestInstance = instance;
          break;
        }
      }
    }
    // If still no instance found, use the first one (fallback)
    if (latestInstance == null && instances.isNotEmpty) {
      latestInstance = instances.first;
    }
    if (latestInstance != null) {
      latestInstances.add(latestInstance);
    }
  }
  // Sort final list by due date (earliest first, nulls last)
  latestInstances.sort((a, b) {
    if (a.dueDate == null && b.dueDate == null) return 0;
    if (a.dueDate == null) return 1;
    if (b.dueDate == null) return -1;
    return a.dueDate!.compareTo(b.dueDate!);
  });
  return latestInstances;
}

/// Query to get all today's instances (current and overdue tasks and habits)
/// Uses cache to reduce redundant Firestore reads
@Deprecated(
  'Migration-only wrapper. Use ActivityInstanceService.getAllActiveInstances '
  'or TodayInstanceRepository hydration directly.',
)
Future<List<ActivityInstanceRecord>> queryAllInstances({
  required String userId,
}) async {
  try {
    return await _runWithInFlightDedupe<List<ActivityInstanceRecord>>(
      'queryAllInstances:$userId',
      () async {
        final cache = FirestoreCacheService();
        // Check cache first
        final cached = cache.getCachedAllInstances();
        if (cached != null) {
          return cached;
        }
        // Fetch from Firestore if cache miss
        final instances =
            await ActivityInstanceService.getAllActiveInstances(userId: userId);
        // Update cache
        cache.cacheAllInstances(instances);
        return instances;
      },
    );
  } catch (e) {
    return []; // Return empty list on error
  }
}

/// Query to get routines for a specific user
Future<List<RoutineRecord>> queryRoutineRecordOnce({
  required String userId,
}) async {
  try {
    final query = RoutineRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true)
        .orderBy('listOrder')
        .orderBy('name');
    final result = await query.get();
    final routines = result.docs.map((doc) {
      return RoutineRecord.fromSnapshot(doc);
    }).toList();
    // Fallback sort by listOrder locally if Firestore ordering fails
    routines.sort((a, b) {
      final orderCompare = a.listOrder.compareTo(b.listOrder);
      if (orderCompare != 0) return orderCompare;
      return a.name.compareTo(b.name);
    });
    return routines;
  } catch (e) {
    // Log index error if present
    logFirestoreIndexError(
      e,
      'Get routines (isActive + orderBy listOrder + orderBy name)',
      'routines',
    );
    if (e is FirebaseException) {
      // If orderBy fails (e.g., no index), fallback to local sort
      try {
        final query = RoutineRecord.collectionForUser(userId)
            .where('isActive', isEqualTo: true);
        final result = await query.get();
        final routines = result.docs.map((doc) {
          return RoutineRecord.fromSnapshot(doc);
        }).toList();
        routines.sort((a, b) {
          final orderCompare = a.listOrder.compareTo(b.listOrder);
          if (orderCompare != 0) return orderCompare;
          return a.name.compareTo(b.name);
        });
        return routines;
      } catch (e2) {
        rethrow;
      }
    }
    rethrow;
  }
}

/// Create a new habit
Future<DocumentReference> createActivity({
  required String name,
  required String categoryName,
  String? categoryId,
  required String trackingType,
  dynamic target,
  String? description,
  String? userId,
  required String categoryType, // 'habit' or 'task'
  // Task-specific parameters
  DateTime? dueDate,
  String? dueTime,
  bool isRecurring = false,
  String? unit,
  int priority = 1,
  List<int>? specificDays,
  // New frequency parameters
  String? frequencyType,
  int? everyXValue,
  String? everyXPeriodType,
  int? timesPerPeriod,
  String? periodType,
  DateTime? startDate,
  DateTime? endDate,
  List<Map<String, dynamic>>? reminders,
  int? timeEstimateMinutes,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final effectiveIsRecurring = categoryType == 'habit' ? true : isRecurring;
  final habitData = createActivityRecordData(
    name: name,
    categoryId: categoryId,
    categoryName: categoryName,
    trackingType: trackingType,
    target: target,
    description: description,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    categoryType: categoryType,
    // Task-specific fields
    dueDate: dueDate,
    dueTime: dueTime,
    isRecurring: effectiveIsRecurring,
    unit: unit,
    priority: priority,
    specificDays: specificDays,
    // Date range fields
    startDate: startDate ?? DateTime.now(),
    endDate: endDate,
    // New frequency fields
    frequencyType: frequencyType,
    everyXValue: everyXValue,
    everyXPeriodType: everyXPeriodType,
    timesPerPeriod: timesPerPeriod,
    periodType: periodType,
    reminders: reminders,
    timeEstimateMinutes: timeEstimateMinutes,
  );
  DocumentReference habitRef;
  try {
    habitRef = await ActivityRecord.collectionForUser(uid)
        .add(habitData)
        .timeout(const Duration(seconds: 10));
  } on TimeoutException {
    rethrow;
  } catch (_) {
    rethrow;
  }
  // Create initial activity instance
  // Optimize: Create ActivityRecord from data we already have instead of fetching
  try {
    final activity = ActivityRecord.getDocumentFromData(habitData, habitRef);
    // Create instance (already broadcasts optimistically and reconciles)
    await ActivityInstanceService.createActivityInstance(
      templateId: habitRef.id,
      dueDate: InstanceDateCalculator.calculateInitialDueDate(
        template: activity,
        explicitDueDate: dueDate,
      ),
      dueTime: dueTime,
      template: activity,
      userId: uid,
      skipOrderLookup: categoryType ==
          'task', // Skip order lookup for tasks to speed up quick add
    ).timeout(const Duration(seconds: 10));
  } catch (e) {
    // Surface instance creation errors so UI can display them
    rethrow;
  }
  // Invalidate template cache
  final cache = FirestoreCacheService();
  cache.invalidateTemplateCache(habitRef.id);

  ActivityTemplateEvents.broadcastTemplateUpdated(
    templateId: habitRef.id,
    context: {
      'action': 'created',
      'categoryType': categoryType,
      'hasDueTime': dueTime != null && dueTime.isNotEmpty,
      if (timeEstimateMinutes != null)
        'timeEstimateMinutes': timeEstimateMinutes,
    },
  );
  return habitRef;
}

/// Create a new category
Future<DocumentReference> createCategory({
  required String name,
  String? description,
  double weight = 1.0,
  required String color,
  String? userId,
  required String categoryType, // Must be 'habit' or 'task'
  bool isSystemCategory = false,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final existingCategories = await queryCategoriesRecordOnce(
    userId: uid,
    callerTag: 'backend.createCategory',
  );
  final nameExists = existingCategories.any((cat) =>
      cat.name.toString().trim().toLowerCase() ==
      name.toString().trim().toLowerCase());
  if (nameExists) {
    throw Exception('Category with name "$name" already exists!');
  }
  final categoryData = createCategoryRecordData(
    uid: uid,
    name: name,
    description: description,
    weight: weight,
    color: color,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    userId: uid,
    categoryType: categoryType,
    isSystemCategory: isSystemCategory,
  );
  final categoryRef =
      await CategoryRecord.collectionForUser(uid).add(categoryData);
  // Invalidate categories cache
  final cache = FirestoreCacheService();
  cache.invalidateCategoriesCache();
  return categoryRef;
}

/// Get or create the inbox category for a user
Future<CategoryRecord> getOrCreateInboxCategory({String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) {
    throw Exception('User not authenticated');
  }
  try {
    // Use simple query to avoid Firestore composite index requirements
    final allCategories = await queryTaskCategoriesOnce(
      userId: uid,
      callerTag: 'backend.getOrCreateInboxCategory',
    );
    // Find inbox category in memory
    final inboxCategory = allCategories.firstWhere(
      (c) => c.name == 'Inbox' && c.isSystemCategory,
      orElse: () => allCategories.firstWhere(
        (c) => c.name == 'Inbox',
        orElse: () => throw StateError('No inbox found'),
      ),
    );
    return inboxCategory;
  } catch (e) {
    // Create inbox category if it doesn't exist
    final inboxRef = await createCategory(
      name: 'Inbox',
      description: 'Default inbox for tasks',
      weight: 1.0,
      color: '#2F4F4F', // Dark Slate Gray (charcoal) for tasks
      userId: uid,
      categoryType: 'task',
      isSystemCategory: true,
    );
    return await CategoryRecord.getDocumentOnce(inboxRef);
  }
}

/// Get or create the "Others" default category for essential activities
Future<CategoryRecord> getOrCreateEssentialDefaultCategory(
    {String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) {
    throw Exception('User not authenticated');
  }
  try {
    // Use simple query to avoid Firestore composite index requirements
    final allCategories = await queryEssentialCategoriesOnce(
      userId: uid,
      callerTag: 'backend.getOrCreateEssentialDefaultCategory',
    );
    // Find "Others" category in memory
    final othersCategory = allCategories.firstWhere(
      (c) => c.name == 'Others' && c.isSystemCategory,
      orElse: () => allCategories.firstWhere(
        (c) => c.name == 'Others',
        orElse: () => throw StateError('No Others category found'),
      ),
    );
    return othersCategory;
  } catch (e) {
    // Create "Others" category if it doesn't exist
    final othersRef = await createCategory(
      name: 'Others',
      description: 'Default category for essential activities',
      weight: 1.0,
      color: '#808080', // Gray for essential activities
      userId: uid,
      categoryType: 'essential',
      isSystemCategory: true,
    );
    return await CategoryRecord.getDocumentOnce(othersRef);
  }
}

/// Query to get user-created (non-system) categories only
Future<List<CategoryRecord>> queryUserCategoriesOnce({
  required String userId,
  String? categoryType,
}) async {
  try {
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(
      userId: userId,
      callerTag: 'backend.queryUserCategoriesOnce',
    );
    // Filter in memory (no Firestore index needed)
    var filtered = allCategories.where((c) => !c.isSystemCategory);
    if (categoryType != null) {
      filtered = filtered.where((c) => c.categoryType == categoryType);
    }
    final result = filtered.toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  } catch (e) {
    return []; // Return empty list on error
  }
}

/// Update a task
Future<void> updateTask({
  required DocumentReference taskRef,
  String? title,
  String? description,
  String? status,
  DateTime? dueDate,
  int? priority,
  int? manualOrder,
  bool? isActive,
  DateTime? completedTime,
  String? categoryId,
  String? categoryName,
  dynamic currentValue,
  bool? isTimerActive,
  DateTime? timerStartTime,
  int? accumulatedTime,
}) async {
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };
  if (title != null) updateData['name'] = title;
  if (description != null) updateData['description'] = description;
  if (status != null) updateData['status'] = status;
  if (dueDate != null) updateData['dueDate'] = dueDate;
  if (priority != null) updateData['priority'] = priority;
  if (manualOrder != null) updateData['manualOrder'] = manualOrder;
  if (isActive != null) updateData['isActive'] = isActive;
  if (completedTime != null) updateData['completedTime'] = completedTime;
  if (categoryId != null) updateData['categoryId'] = categoryId;
  if (categoryName != null) updateData['categoryName'] = categoryName;
  if (currentValue != null) updateData['currentValue'] = currentValue;
  if (isTimerActive != null) updateData['isTimerActive'] = isTimerActive;
  if (timerStartTime != null) updateData['timerStartTime'] = timerStartTime;
  if (accumulatedTime != null) updateData['accumulatedTime'] = accumulatedTime;
  await taskRef.update(updateData);
}

/// Soft delete a task
Future<void> deleteTask(DocumentReference taskRef) async {
  await taskRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });
  // Also delete all instances for this task
  // TODO: Phase 6 - Implement with ActivityInstanceService
  /*
  try {
    await TaskInstanceService.deleteInstancesForTemplate(
      templateId: taskRef.id,
      templateType: 'task',
    );
  } catch (e) {
    // Don't fail the task deletion if instance deletion fails
  }
  */
}

/// Create a work session entry
Future<DocumentReference> createWorkSession({
  required String type, // 'habit' | 'task'
  required String refId,
  required DateTime startTime,
  required DateTime endTime,
  String? note,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final durationMs = endTime.difference(startTime).inMilliseconds;
  final sessionData = createWorkSessionRecordData(
    uid: uid,
    type: type,
    refId: refId,
    startTime: startTime,
    endTime: endTime,
    durationMs: durationMs,
    note: note,
    userId: uid,
  );
  return await WorkSessionRecord.collectionForUser(uid).add(sessionData);
}

/// Create a new routine
Future<DocumentReference> createRoutine({
  required String name,
  String? description,
  required List<String> itemIds,
  required List<String> itemOrder,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  // Get item names and types from the item IDs
  final itemNames = <String>[];
  final itemTypes = <String>[];
  for (final itemId in itemIds) {
    try {
      final activityDoc =
          await ActivityRecord.collectionForUser(uid).doc(itemId).get();
      if (activityDoc.exists) {
        final activityData = activityDoc.data() as Map<String, dynamic>?;
        if (activityData != null) {
          itemNames.add(activityData['name'] ?? 'Unknown Item');
          itemTypes.add(activityData['categoryType'] ?? 'habit');
        }
      }
    } catch (e) {
      itemNames.add('Unknown Item');
      itemTypes.add('habit');
    }
  }
  final routineData = createRoutineRecordData(
    uid: uid,
    name: name,
    description: description,
    itemIds: itemIds,
    itemNames: itemNames,
    itemOrder: itemOrder,
    itemTypes: itemTypes,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    userId: uid,
  );
  return await RoutineRecord.collectionForUser(uid).add(routineData);
}

/// Update a habit
Future<void> updateHabit({
  required DocumentReference habitRef,
  String? name,
  String? categoryName,
  String? trackingType,
  dynamic target,
  String? schedule,
  int? weeklyTarget,
  String? description,
  bool? isActive,
  int? manualOrder,
  int? priority,
  DateTime? snoozedUntil,
}) async {
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };
  if (name != null) updateData['name'] = name;
  if (categoryName != null) updateData['categoryName'] = categoryName;
  if (trackingType != null) updateData['trackingType'] = trackingType;
  if (target != null) updateData['target'] = target;
  if (schedule != null) updateData['schedule'] = schedule;
  if (weeklyTarget != null) updateData['weeklyTarget'] = weeklyTarget;
  if (description != null) updateData['description'] = description;
  if (isActive != null) updateData['isActive'] = isActive;
  if (manualOrder != null) updateData['manualOrder'] = manualOrder;
  if (priority != null) updateData['priority'] = priority;
  if (snoozedUntil != null) updateData['snoozedUntil'] = snoozedUntil;
  await habitRef.update(updateData);
}

/// Delete a habit (soft delete by setting isActive to false)
Future<void> deleteHabit(DocumentReference habitRef) async {
  await habitRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });
  // Also delete all instances for this habit
  // TODO: Phase 6 - Implement with ActivityInstanceService
  /*
  try {
    await TaskInstanceService.deleteInstancesForTemplate(
      templateId: habitRef.id,
      templateType: 'habit',
    );
  } catch (e) {
    // Don't fail the habit deletion if instance deletion fails
  }
  */
}

/// Update a category
Future<void> updateCategory({
  required String categoryId,
  String? name,
  String? description,
  double? weight,
  String? color,
  bool? isActive,
  String? userId,
  String? categoryType,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final categoryRef = CategoryRecord.collectionForUser(uid).doc(categoryId);
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };
  if (name != null) updateData['name'] = name;
  if (description != null) updateData['description'] = description;
  if (weight != null) updateData['weight'] = weight;
  if (color != null) updateData['color'] = color;
  if (isActive != null) updateData['isActive'] = isActive;
  if (categoryType != null) updateData['categoryType'] = categoryType;
  await categoryRef.update(updateData);
  // Invalidate categories cache
  final cache = FirestoreCacheService();
  cache.invalidateCategoriesCache();
}

/// Delete a category (soft delete by setting isActive to false)
Future<void> deleteCategory(String categoryId, {String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final categoryRef = CategoryRecord.collectionForUser(uid).doc(categoryId);
  await categoryRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });
  // Invalidate categories cache
  final cache = FirestoreCacheService();
  cache.invalidateCategoriesCache();
}

/// Update a routine
Future<void> updateRoutine({
  required String routineId,
  String? name,
  String? description,
  List<String>? itemIds,
  List<String>? itemOrder,
  bool? isActive,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final routineRef = RoutineRecord.collectionForUser(uid).doc(routineId);
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };
  if (name != null) updateData['name'] = name;
  if (description != null) updateData['description'] = description;
  if (itemOrder != null) updateData['itemOrder'] = itemOrder;
  if (isActive != null) updateData['isActive'] = isActive;
  if (itemIds != null) {
    updateData['itemIds'] = itemIds;
    // Update cached names and types
    final itemNames = <String>[];
    final itemTypes = <String>[];
    for (final itemId in itemIds) {
      try {
        final activityDoc =
            await ActivityRecord.collectionForUser(uid).doc(itemId).get();
        if (activityDoc.exists) {
          final activityData = activityDoc.data() as Map<String, dynamic>?;
          if (activityData != null) {
            itemNames.add(activityData['name'] ?? 'Unknown Item');
            itemTypes.add(activityData['categoryType'] ?? 'habit');
          }
        }
      } catch (e) {
        itemNames.add('Unknown Item');
        itemTypes.add('habit');
      }
    }
    updateData['itemNames'] = itemNames;
    updateData['itemTypes'] = itemTypes;
  }
  await routineRef.update(updateData);
}

/// Delete a routine (soft delete by setting isActive to false)
Future<void> deleteRoutine(String routineId, {String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final routineRef = RoutineRecord.collectionForUser(uid).doc(routineId);
  await routineRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });
}

// ==================== TASK INSTANCE MANAGEMENT ====================
// TODO: Phase 3 - Implement with ActivityInstanceService
/*
/// Complete a task instance and generate next occurrence if recurring
Future<void> completeTaskInstance({
  required String instanceId,
  dynamic finalValue,
  int? finalAccumulatedTime,
  String? notes,
  String? userId,
}) async {
  await TaskInstanceService.completeTaskInstance(
    instanceId: instanceId,
    finalValue: finalValue,
    finalAccumulatedTime: finalAccumulatedTime,
    notes: notes,
    userId: userId,
  );
}
/// Skip a task instance and generate next occurrence if recurring
Future<void> skipTaskInstance({
  required String instanceId,
  String? notes,
  String? userId,
}) async {
  await TaskInstanceService.skipTaskInstance(
    instanceId: instanceId,
    notes: notes,
    userId: userId,
  );
}
*/
// TODO: Phase 3 - Implement with ActivityInstanceService
/*
/// Complete a habit instance and generate next occurrence
Future<void> completeHabitInstance({
  required String instanceId,
  dynamic finalValue,
  int? finalAccumulatedTime,
  String? notes,
  String? userId,
}) async {
  await TaskInstanceService.completeHabitInstance(
    instanceId: instanceId,
    finalValue: finalValue,
    finalAccumulatedTime: finalAccumulatedTime,
    notes: notes,
    userId: userId,
  );
}
/// Skip a habit instance and generate next occurrence
Future<void> skipHabitInstance({
  required String instanceId,
  String? notes,
  String? userId,
}) async {
  await TaskInstanceService.skipHabitInstance(
    instanceId: instanceId,
    notes: notes,
    userId: userId,
  );
}
/// Update instance progress (for quantity/duration tracking)
Future<void> updateInstanceProgress({
  required String instanceId,
  required String instanceType, // 'task' or 'habit'
  dynamic currentValue,
  int? accumulatedTime,
  bool? isTimerActive,
  DateTime? timerStartTime,
  String? userId,
}) async {
  await TaskInstanceService.updateInstanceProgress(
    instanceId: instanceId,
    instanceType: instanceType,
    currentValue: currentValue,
    accumulatedTime: accumulatedTime,
    isTimerActive: isTimerActive,
    timerStartTime: timerStartTime,
    userId: userId,
  );
}
// ==================== ACTIVITY INSTANCE CONVENIENCE WRAPPERS ====================
/// Complete an activity instance
Future<void> completeActivityInstance({
  required String instanceId,
  dynamic finalValue,
  int? finalAccumulatedTime,
  String? notes,
  String? userId,
}) async {
  return ActivityInstanceService.completeInstance(
    instanceId: instanceId,
    finalValue: finalValue,
    finalAccumulatedTime: finalAccumulatedTime,
    notes: notes,
    userId: userId,
  );
}
/// Uncomplete an activity instance (mark as pending)
Future<void> uncompleteActivityInstance({
  required String instanceId,
  String? userId,
}) async {
  return ActivityInstanceService.uncompleteInstance(
    instanceId: instanceId,
    userId: userId,
  );
}
/// Update activity instance progress (for quantitative tracking)
Future<void> updateActivityInstanceProgress({
  required String instanceId,
  required dynamic currentValue,
  String? userId,
}) async {
  return ActivityInstanceService.updateInstanceProgress(
    instanceId: instanceId,
    currentValue: currentValue,
    userId: userId,
  );
}
/// Toggle activity instance timer (for time tracking)
Future<void> toggleActivityInstanceTimer({
  required String instanceId,
  String? userId,
}) async {
  return ActivityInstanceService.toggleInstanceTimer(
    instanceId: instanceId,
    userId: userId,
  );
}
/// Skip an activity instance
Future<void> skipActivityInstance({
  required String instanceId,
  String? notes,
  String? userId,
}) async {
  return ActivityInstanceService.skipInstance(
    instanceId: instanceId,
    notes: notes,
    userId: userId,
  );
}
/// Reschedule an activity instance
Future<void> rescheduleActivityInstance({
  required String instanceId,
  required DateTime newDueDate,
  String? userId,
}) async {
  return ActivityInstanceService.rescheduleInstance(
    instanceId: instanceId,
    newDueDate: newDueDate,
    userId: userId,
  );
}
/// Remove due date from an activity instance
Future<void> removeDueDateFromInstance({
  required String instanceId,
  String? userId,
}) async {
  return ActivityInstanceService.removeDueDateFromInstance(
    instanceId: instanceId,
    userId: userId,
  );
}
/// Skip all instances until a specific date
Future<void> skipActivityInstancesUntil({
  required String templateId,
  required DateTime untilDate,
  String? userId,
}) async {
  return ActivityInstanceService.skipInstancesUntil(
    templateId: templateId,
    untilDate: untilDate,
    userId: userId,
  );
}
/// Get updated instance data after changes
Future<ActivityInstanceRecord> getUpdatedActivityInstance({
  required String instanceId,
  String? userId,
}) async {
  return ActivityInstanceService.getUpdatedInstance(
    instanceId: instanceId,
    userId: userId,
  );
}
/// Snooze an activity instance until a specific date
Future<void> snoozeActivityInstance({
  required String instanceId,
  required DateTime snoozeUntil,
  String? userId,
}) async {
  return ActivityInstanceService.snoozeInstance(
    instanceId: instanceId,
    snoozeUntil: snoozeUntil,
    userId: userId,
  );
}
/// Unsnooze an activity instance (remove snooze)
Future<void> unsnoozeActivityInstance({
  required String instanceId,
  String? userId,
}) async {
  return ActivityInstanceService.unsnoozeInstance(
    instanceId: instanceId,
    userId: userId,
  );
}
/// Manually update lastDayValue for windowed habits (for testing/fixing)
Future<void> updateLastDayValuesForWindowedHabits({
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) {
    throw Exception('No authenticated user');
  }
  // Get all active windowed habit instances
  // Filter windowDuration in memory to match Index 2 prefix order
  try {
    final query = ActivityInstanceRecord.collectionForUser(uid)
        .where('templateCategoryType', isEqualTo: 'habit')
        .where('status', isEqualTo: 'pending');
    final querySnapshot = await query.get();
    final instances = querySnapshot.docs
        .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
        .where((instance) => instance.windowDuration > 1)
        .toList();
  if (instances.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  final now = DateTime.now();
  for (final instance in instances) {
    final instanceRef = instance.reference;
    batch.update(instanceRef, {
      'lastDayValue': instance.currentValue,
      'lastUpdated': now,
    });
  }
  await batch.commit();
}
*/
/// Update category metadata (name/color) and cascade to all templates and instances
Future<void> updateCategoryCascade({
  required String categoryId,
  required String userId,
  String? newCategoryName,
  String? newCategoryColor,
}) async {
  if (newCategoryName == null && newCategoryColor == null) {
    return;
  }
  try {
    // 1. Find all templates with this categoryId
    final templatesQuery = ActivityRecord.collectionForUser(userId)
        .where('categoryId', isEqualTo: categoryId);
    final templatesSnapshot = await templatesQuery.get();
    final templates = templatesSnapshot.docs;

    // We'll collect template IDs to update their instances reliably
    final List<String> templateIds = [];

    // 2. Update all templates
    final cache = FirestoreCacheService();
    for (final templateDoc in templates) {
      templateIds.add(templateDoc.id);
      try {
        final updateData = <String, dynamic>{
          'lastUpdated': DateTime.now(),
        };
        if (newCategoryName != null) {
          updateData['categoryName'] = newCategoryName;
        }
        await templateDoc.reference.update(updateData);
        // Invalidate template cache
        cache.invalidateTemplateCache(templateDoc.id);
      } catch (e) {
        // Log error but continue with other templates - individual template update failures are non-critical
        print('Error updating template category metadata: $e');
      }
    }

    // 3. Update all instances LINKED to these templates (Robust Cascade)
    // This ensures even if templateCategoryId is broken/stale on the instance,
    // if it belongs to the template, it gets updated and repaired.
    // Chunking to respect Firestore 'whereIn' limit of 10
    const chunkSize = 10;
    for (var i = 0; i < templateIds.length; i += chunkSize) {
      final end = (i + chunkSize < templateIds.length)
          ? i + chunkSize
          : templateIds.length;
      final chunk = templateIds.sublist(i, end);

      if (chunk.isEmpty) continue;

      try {
        final linkedInstancesQuery =
            ActivityInstanceRecord.collectionForUser(userId)
                .where('templateId', whereIn: chunk);
        final linkedInstancesSnapshot = await linkedInstancesQuery.get();
        final linkedInstances = linkedInstancesSnapshot.docs;

        // Process instances in smaller batches for writes
        const writeBatchSize = 20;
        for (int j = 0; j < linkedInstances.length; j += writeBatchSize) {
          final batch = linkedInstances.skip(j).take(writeBatchSize);
          await Future.wait(batch.map((instanceDoc) async {
            try {
              final updateData = <String, dynamic>{
                'lastUpdated': DateTime.now(),
                // Repair the link to the category ID as well, just in case it was lost
                'templateCategoryId': categoryId,
              };
              if (newCategoryName != null) {
                updateData['templateCategoryName'] = newCategoryName;
              }
              if (newCategoryColor != null) {
                updateData['templateCategoryColor'] = newCategoryColor;
              }
              await instanceDoc.reference.update(updateData);
            } catch (e) {
              // Continue on error
            }
          }));
        }
      } catch (e) {
        print('Error updating instances for chunk: $e');
      }
    }

    // Invalidate categories cache
    cache.invalidateCategoriesCache();

    // Notify all pages that categories have been updated
    final payload = <String, dynamic>{
      'categoryId': categoryId,
      if (newCategoryName != null) 'newCategoryName': newCategoryName,
      if (newCategoryColor != null) 'newCategoryColor': newCategoryColor,
    };
    NotificationCenter.post('categoryUpdated', payload);
  } catch (e) {
    throw e;
  }
}
