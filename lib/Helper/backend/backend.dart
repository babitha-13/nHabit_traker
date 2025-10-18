import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/category_color_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/backend/schema/work_session_record.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/date_service.dart';
import 'package:habit_tracker/Helper/backend/activity_instance_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/instance_date_calculator.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

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

Future<int> queryCollectionCount(
  Query collection, {
  Query Function(Query)? queryBuilder,
  int limit = -1,
}) async {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0) {
    query = query.limit(limit);
  }

  try {
    final snapshot = await query.count().get();
    return snapshot.count ?? 0;
  } catch (err) {
    print('Error querying $collection: $err');
    return 0;
  }
}

Stream<List<T>> queryCollection<T>(
  Query collection,
  RecordBuilder<T> recordBuilder, {
  Query Function(Query)? queryBuilder,
  int limit = -1,
  bool singleRecord = false,
}) {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0 || singleRecord) {
    query = query.limit(singleRecord ? 1 : limit);
  }
  return query.snapshots().handleError((err) {
    print('Error querying $collection: $err');
  }).map((s) => s.docs
      .map(
        (d) => safeGet(
          () => recordBuilder(d),
          (e) => print('Error serializing doc ${d.reference.path}:\n$e'),
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
}) {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection);
  if (limit > 0 || singleRecord) {
    query = query.limit(singleRecord ? 1 : limit);
  }

  return query.get().then((s) => s.docs
      .map(
        (d) => safeGet(
          () => recordBuilder(d),
          (e) => print('Error serializing doc ${d.reference.path}:\n$e'),
        ),
      )
      .where((d) => d != null)
      .map((d) => d!)
      .toList());
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
}) async {
  final builder = queryBuilder ?? (q) => q;
  var query = builder(collection).limit(pageSize);
  if (nextPageMarker != null) {
    query = query.startAfterDocument(nextPageMarker);
  }
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
          (e) => print('Error serializing doc ${d.reference.path}:\n$e'),
        ),
      )
      .where((d) => d != null)
      .map((d) => d!)
      .toList();
  final data = getDocs(docSnapshot);
  final dataStream = docSnapshotStream?.map(getDocs);
  final nextPageToken = docSnapshot.docs.isEmpty ? null : docSnapshot.docs.last;
  return FFFirestorePage(data, dataStream, nextPageToken);
}

// Creates a Firestore document representing the logged in user if it doesn't yet exist
Future maybeCreateUser(User user) async {
  try {
    print('maybeCreateUser: Starting for user ${user.uid}');

    // Add a small delay to ensure user is fully authenticated
    await Future.delayed(const Duration(milliseconds: 500));

    final userRecord = UsersRecord.collection.doc(user.uid);
    print('maybeCreateUser: Checking if user exists');

    final userExists = await userRecord.get().then((u) => u.exists);
    print('maybeCreateUser: User exists: $userExists');

    if (userExists) {
      print('maybeCreateUser: Getting existing user document');
      currentUserDocument = await UsersRecord.getDocumentOnce(userRecord);
      print('maybeCreateUser: Existing user document retrieved');
      return;
    }

    print('maybeCreateUser: Creating new user document');
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

    print('maybeCreateUser: Setting user data in Firestore');
    print('maybeCreateUser: User data: $userData');

    await userRecord.set(userData);
    print('maybeCreateUser: User data set successfully');

    currentUserDocument = UsersRecord.getDocumentFromData(userData, userRecord);
    print('maybeCreateUser: User document created and assigned');
  } catch (e) {
    print('maybeCreateUser: Error occurred: $e');
    print('maybeCreateUser: Error type: ${e.runtimeType}');
    print(
        'maybeCreateUser: Current user: ${FirebaseAuth.instance.currentUser?.uid}');
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
}) async {
  try {
    // Use simple query without orderBy to avoid Firestore composite index requirements
    final query = ActivityRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true);
    final result = await query.get();
    final habits =
        result.docs.map((doc) => ActivityRecord.fromSnapshot(doc)).toList();

    // Filter habits based on date boundaries
    final today = DateService.todayStart;
    final activeHabits =
        habits.where((habit) => isHabitActiveByDate(habit, today)).toList();

    // Sort in memory instead of in query
    activeHabits.sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
    return activeHabits;
  } catch (e) {
    print('Error querying habits: $e');
    return []; // Return empty list on error
  }
}

/// Query to get categories for a specific user
Future<List<CategoryRecord>> queryCategoriesRecordOnce({
  required String userId,
}) async {
  final query = CategoryRecord.collectionForUser(userId)
      .where('isActive', isEqualTo: true)
      .orderBy('name');

  final result = await query.get();
  return result.docs.map((doc) => CategoryRecord.fromSnapshot(doc)).toList();
}

/// Query to get habit categories for a specific user
Future<List<CategoryRecord>> queryHabitCategoriesOnce({
  required String userId,
}) async {
  try {
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(userId: userId);

    // Filter in memory (no Firestore index needed)
    final habitCategories =
        allCategories.where((c) => c.categoryType == 'habit').toList();

    // Sort in memory
    habitCategories.sort((a, b) => a.name.compareTo(b.name));
    return habitCategories;
  } catch (e) {
    print('Error querying habit categories: $e');
    return []; // Return empty list on error
  }
}

/// Query to get task categories for a specific user
Future<List<CategoryRecord>> queryTaskCategoriesOnce({
  required String userId,
}) async {
  try {
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(userId: userId);

    // Filter in memory (no Firestore index needed)
    final taskCategories =
        allCategories.where((c) => c.categoryType == 'task').toList();

    // Sort in memory
    taskCategories.sort((a, b) => a.name.compareTo(b.name));
    return taskCategories;
  } catch (e) {
    print('Error querying task categories: $e');
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
  } catch (e) {
    print('Error querying today\'s task instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get all task instances (active and completed) for Recent Completions
Future<List<ActivityInstanceRecord>> queryAllTaskInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getAllTaskInstances(userId: userId);
  } catch (e) {
    print('Error querying all task instances: $e');
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
  } catch (e) {
    print('Error querying today\'s habit instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get current habit instances for Habits page (no future instances)
/// Only shows instances whose window includes today
Future<List<ActivityInstanceRecord>> queryCurrentHabitInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getCurrentHabitInstances(
        userId: userId);
  } catch (e) {
    print('Error querying current habit instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get all habit instances for Habits page (all dates and statuses)
/// Shows complete view of all habits regardless of window or status
Future<List<ActivityInstanceRecord>> queryAllHabitInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getAllHabitInstances(userId: userId);
  } catch (e) {
    print('Error querying all habit instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get all today's instances (current and overdue tasks and habits)
Future<List<ActivityInstanceRecord>> queryAllInstances({
  required String userId,
}) async {
  try {
    return await ActivityInstanceService.getAllActiveInstances(userId: userId);
  } catch (e) {
    print('Error querying all today\'s instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get sequences for a specific user
Future<List<SequenceRecord>> querySequenceRecordOnce({
  required String userId,
}) async {
  final query = SequenceRecord.collectionForUser(userId)
      .where('isActive', isEqualTo: true)
      .orderBy('name');

  final result = await query.get();
  return result.docs.map((doc) => SequenceRecord.fromSnapshot(doc)).toList();
}

/// Create a new habit
Future<DocumentReference> createActivity({
  required String name,
  required String categoryName,
  required String trackingType,
  dynamic target,
  String? description,
  String? userId,
  required String categoryType, // 'habit' or 'task'

  // Task-specific parameters
  DateTime? dueDate,
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
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  final effectiveIsRecurring = categoryType == 'habit' ? true : isRecurring;

  final habitData = createActivityRecordData(
    name: name,
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
  );

  final habitRef = await ActivityRecord.collectionForUser(uid).add(habitData);

  // Create initial activity instance
  try {
    print('Creating activity instance for template: ${habitRef.id}');
    final activity = await ActivityRecord.getDocumentOnce(habitRef);
    print('Activity template loaded: ${activity.name}');

    final instanceRef = await ActivityInstanceService.createActivityInstance(
      templateId: habitRef.id,
      dueDate: InstanceDateCalculator.calculateInitialDueDate(
        template: activity,
        explicitDueDate: dueDate,
      ),
      template: activity,
      userId: uid,
    );
    print('Activity instance created successfully: ${instanceRef.id}');

    // Get the created instance and broadcast the event
    try {
      final instance = await ActivityInstanceService.getUpdatedInstance(
        instanceId: instanceRef.id,
      );
      InstanceEvents.broadcastInstanceCreated(instance);
    } catch (e) {
      print('Error broadcasting instance creation: $e');
    }
  } catch (e) {
    print('Error creating initial activity instance: $e');
    print('Stack trace: ${StackTrace.current}');
    // Don't fail the activity creation if instance creation fails
  }

  return habitRef;
}

/// Create a new category
Future<DocumentReference> createCategory({
  required String name,
  String? description,
  double weight = 1.0,
  String? color,
  String? userId,
  required String categoryType, // Must be 'habit' or 'task'
  bool isSystemCategory = false,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  final existingCategories = await queryCategoriesRecordOnce(userId: uid);
  final nameExists = existingCategories.any((cat) =>
      cat.name.toString().trim().toLowerCase() ==
      name.toString().trim().toLowerCase());

  if (nameExists) {
    throw Exception('Category with name "$name" already exists!');
  }
  final resolvedColor = color ?? CategoryColorUtil.hexForName(name);

  final categoryData = createCategoryRecordData(
    uid: uid,
    name: name,
    description: description,
    weight: weight,
    color: resolvedColor,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    userId: uid,
    categoryType: categoryType,
    isSystemCategory: isSystemCategory,
  );

  return await CategoryRecord.collectionForUser(uid).add(categoryData);
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
    final allCategories = await queryTaskCategoriesOnce(userId: uid);

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
      userId: uid,
      categoryType: 'task',
      isSystemCategory: true,
    );

    return await CategoryRecord.getDocumentOnce(inboxRef);
  }
}

/// Query to get user-created (non-system) categories only
Future<List<CategoryRecord>> queryUserCategoriesOnce({
  required String userId,
  String? categoryType,
}) async {
  try {
    // Use simple query and filter in memory to avoid Firestore composite index requirements
    final allCategories = await queryCategoriesRecordOnce(userId: userId);

    // Filter in memory (no Firestore index needed)
    var filtered = allCategories.where((c) => !c.isSystemCategory);
    if (categoryType != null) {
      filtered = filtered.where((c) => c.categoryType == categoryType);
    }

    final result = filtered.toList();
    result.sort((a, b) => a.name.compareTo(b.name));
    return result;
  } catch (e) {
    print('Error querying user categories: $e');
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
    print('Error deleting task instances: $e');
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

/// Create a new sequence
Future<DocumentReference> createSequence({
  required String name,
  String? description,
  required List<String> habitIds,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  // Get habit names from the habit IDs
  final habitNames = <String>[];
  for (final habitId in habitIds) {
    try {
      final habitDoc =
          await ActivityRecord.collectionForUser(uid).doc(habitId).get();
      if (habitDoc.exists) {
        final habitData = habitDoc.data() as Map<String, dynamic>?;
        if (habitData != null) {
          habitNames.add(habitData['name'] ?? 'Unknown Habit');
        }
      }
    } catch (e) {
      print('Error getting habit name for ID $habitId: $e');
      habitNames.add('Unknown Habit');
    }
  }

  final sequenceData = createSequenceRecordData(
    uid: uid,
    name: name,
    description: description,
    habitIds: habitIds,
    habitNames: habitNames,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    userId: uid,
  );

  return await SequenceRecord.collectionForUser(uid).add(sequenceData);
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
    print('Error deleting habit instances: $e');
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
}

/// Update a sequence
Future<void> updateSequence({
  required String sequenceId,
  String? name,
  String? description,
  List<String>? habitIds,
  List<String>? habitNames,
  bool? isActive,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  final sequenceRef = SequenceRecord.collectionForUser(uid).doc(sequenceId);
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };

  if (name != null) updateData['name'] = name;
  if (description != null) updateData['description'] = description;
  if (habitIds != null) updateData['habitIds'] = habitIds;
  if (habitNames != null) updateData['habitNames'] = habitNames;
  if (isActive != null) updateData['isActive'] = isActive;

  await sequenceRef.update(updateData);
}

/// Delete a sequence (soft delete by setting isActive to false)
Future<void> deleteSequence(String sequenceId, {String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  final sequenceRef = SequenceRecord.collectionForUser(uid).doc(sequenceId);
  await sequenceRef.update({
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
  final query = ActivityInstanceRecord.collectionForUser(uid)
      .where('templateCategoryType', isEqualTo: 'habit')
      .where('status', isEqualTo: 'pending')
      .where('windowDuration', isGreaterThan: 1);

  final querySnapshot = await query.get();
  final instances = querySnapshot.docs
      .map((doc) => ActivityInstanceRecord.fromSnapshot(doc))
      .toList();

  print('Backend: Found ${instances.length} windowed habits to update lastDayValue');

  if (instances.isEmpty) return;

  final batch = FirebaseFirestore.instance.batch();
  final now = DateTime.now();

  for (final instance in instances) {
    final instanceRef = instance.reference;
    batch.update(instanceRef, {
      'lastDayValue': instance.currentValue,
      'lastUpdated': now,
    });

    print('Backend: Updated lastDayValue for ${instance.templateName} to ${instance.currentValue}');
  }

  await batch.commit();
  print('Backend: Updated lastDayValue for ${instances.length} windowed habits');
}
*/

/// Update category name and cascade to all templates and instances
Future<void> updateCategoryNameCascade({
  required String categoryId,
  required String newCategoryName,
  required String userId,
}) async {
  try {
    print('DEBUG: Starting category name cascade update');
    print('DEBUG: Category ID: $categoryId');
    print('DEBUG: New name: $newCategoryName');

    // 1. Find all templates with this categoryId
    final templatesQuery = ActivityRecord.collectionForUser(userId)
        .where('categoryId', isEqualTo: categoryId);
    final templatesSnapshot = await templatesQuery.get();
    final templates = templatesSnapshot.docs;

    print('DEBUG: Found ${templates.length} templates to update');

    // 2. Update all templates
    int templateSuccessCount = 0;
    for (final templateDoc in templates) {
      try {
        await templateDoc.reference.update({
          'categoryName': newCategoryName,
          'lastUpdated': DateTime.now(),
        });
        templateSuccessCount++;
      } catch (e) {
        print('ERROR: Failed to update template ${templateDoc.id}: $e');
      }
    }

    print('DEBUG: Updated $templateSuccessCount/${templates.length} templates');

    // 3. Find ALL instances (pending AND completed) with this categoryId
    final instancesQuery = ActivityInstanceRecord.collectionForUser(userId)
        .where('templateCategoryId', isEqualTo: categoryId);
    final instancesSnapshot = await instancesQuery.get();
    final instances = instancesSnapshot.docs;

    print(
        'DEBUG: Found ${instances.length} instances to update (all statuses)');

    // 4. Update all instances in batches
    const batchSize = 10;
    int instanceSuccessCount = 0;
    int instanceFailureCount = 0;

    for (int i = 0; i < instances.length; i += batchSize) {
      final batch = instances.skip(i).take(batchSize);

      final results = await Future.wait(batch.map((instanceDoc) async {
        try {
          await instanceDoc.reference.update({
            'templateCategoryName': newCategoryName,
            'lastUpdated': DateTime.now(),
          });
          return true;
        } catch (e) {
          print('ERROR: Failed to update instance ${instanceDoc.id}: $e');
          return false;
        }
      }));

      for (final result in results) {
        if (result) {
          instanceSuccessCount++;
        } else {
          instanceFailureCount++;
        }
      }
    }

    print('DEBUG: Updated $instanceSuccessCount/${instances.length} instances');
    print('DEBUG: Failed: $instanceFailureCount');
    print('DEBUG: Category name cascade update completed');

    // Notify all pages that categories have been updated
    NotificationCenter.post('categoryUpdated', {
      'categoryId': categoryId,
      'newCategoryName': newCategoryName,
    });
  } catch (e) {
    print('ERROR: Category name cascade update failed: $e');
    throw e;
  }
}
