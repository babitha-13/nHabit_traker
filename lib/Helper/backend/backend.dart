import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/category_color_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_record.dart';
import 'package:habit_tracker/Helper/backend/schema/users_record.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/backend/schema/work_session_record.dart';
import 'package:habit_tracker/Helper/backend/schema/task_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_instance_record.dart';
import 'package:habit_tracker/Helper/backend/task_instance_service.dart';
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

/// Query to get habits for a specific user
Future<List<HabitRecord>> queryHabitsRecordOnce({
  required String userId,
}) async {
  try {
    // Use simple query without orderBy to avoid Firestore composite index requirements
    final query = HabitRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true);
    final result = await query.get();
    final habits =
    result.docs.map((doc) => HabitRecord.fromSnapshot(doc)).toList();

    // Sort in memory instead of in query
    habits.sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
    return habits;
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

/// Query to get tasks for a specific user (LEGACY - use queryTodaysTaskInstances for active tasks)
Future<List<TaskRecord>> queryTasksRecordOnce({
  required String userId,
}) async {
  try {
    // Use simple query without orderBy to avoid Firestore composite index requirements
    final query =
    TaskRecord.collectionForUser(userId).where('isActive', isEqualTo: true);
    final result = await query.get();
    final tasks =
    result.docs.map((doc) => TaskRecord.fromSnapshot(doc)).toList();

    // Sort in memory instead of in query
    tasks.sort((a, b) => b.createdTime!.compareTo(a.createdTime!));
    return tasks;
  } catch (e) {
    print('Error querying tasks: $e');
    return []; // Return empty list on error
  }
}

/// Query to get today's task instances (current and overdue)
/// This is the main function to use for displaying active tasks to users
Future<List<TaskInstanceRecord>> queryTodaysTaskInstances({
  required String userId,
}) async {
  try {
    return await TaskInstanceService.getTodaysTaskInstances(userId: userId);
  } catch (e) {
    print('Error querying today\'s task instances: $e');
    return []; // Return empty list on error
  }
}

/// Query to get today's habit instances (current and overdue)
/// This is the main function to use for displaying active habits to users
Future<List<HabitInstanceRecord>> queryTodaysHabitInstances({
  required String userId,
}) async {
  try {
    return await TaskInstanceService.getTodaysHabitInstances(userId: userId);
  } catch (e) {
    print('Error querying today\'s habit instances: $e');
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
Future<DocumentReference> createHabit({
  required String name,
  required String categoryName,
  required String trackingType,
  dynamic target,
  required String schedule,
  int frequency = 1,
  String? description,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  final habitData = createHabitRecordData(
    name: name,
    categoryName: categoryName,
    trackingType: trackingType,
    target: target,
    schedule: schedule,
    frequency: frequency,
    description: description,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
    categoryType: 'habit',
  );

  final habitRef = await HabitRecord.collectionForUser(uid).add(habitData);

  // Create initial habit instance
  try {
    final habit = await HabitRecord.getDocumentOnce(habitRef);
    await TaskInstanceService.initializeHabitInstances(
      templateId: habitRef.id,
      template: habit,
      userId: uid,
    );
  } catch (e) {
    print('Error creating initial habit instance: $e');
    // Don't fail the habit creation if instance creation fails
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

  if ((currentValue != null || accumulatedTime != null) && status != 'incomplete') {
    try {
      final taskDoc = await taskRef.get();
      if (taskDoc.exists) {
        final task = TaskRecord.fromSnapshot(taskDoc);
        if (task.status != 'complete' && task.target != null) {
          bool shouldComplete = false;

          if (task.trackingType == 'binary' && currentValue == true) {
            shouldComplete = true;
          } else if (task.trackingType == 'quantitative') {
            final progress = (currentValue ?? task.currentValue) ?? 0;
            final target = task.target ?? 0;
            shouldComplete = progress >= target;
          } else if (task.trackingType == 'time') {
            final totalMs = accumulatedTime ?? task.accumulatedTime;
            final targetMs = (task.target ?? 0) * 60000;
            shouldComplete = totalMs >= targetMs;
          }

          if (shouldComplete) {
            updateData['status'] = 'complete';
            updateData['completedTime'] = DateTime.now();
          }
        }
      }
    } catch (e) {
      // Ignore errors
    }
  }


  await taskRef.update(updateData);
}

/// Soft delete a task
Future<void> deleteTask(DocumentReference taskRef) async {
  await taskRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });

  // Also delete all instances for this task
  try {
    await TaskInstanceService.deleteInstancesForTemplate(
      templateId: taskRef.id,
      templateType: 'task',
    );
  } catch (e) {
    print('Error deleting task instances: $e');
    // Don't fail the task deletion if instance deletion fails
  }
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
      await HabitRecord.collectionForUser(uid).doc(habitId).get();
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
  try {
    await TaskInstanceService.deleteInstancesForTemplate(
      templateId: habitRef.id,
      templateType: 'habit',
    );
  } catch (e) {
    print('Error deleting habit instances: $e');
    // Don't fail the habit deletion if instance deletion fails
  }
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

// ==================== MIGRATION FUNCTIONS ====================

/// Migrate existing tasks and habits to the new instance system
/// This should be called once to convert existing data
Future<Map<String, int>> migrateToInstanceSystem({String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) return {'tasks': 0, 'habits': 0, 'errors': 0};

  int tasksMigrated = 0;
  int habitsMigrated = 0;
  int errors = 0;

  try {
    // Migrate existing tasks
    final tasks = await queryTasksRecordOnce(userId: uid);
    for (final task in tasks) {
      try {
        await TaskInstanceService.initializeTaskInstances(
          templateId: task.reference.id,
          template: task,
          userId: uid,
        );
        tasksMigrated++;
      } catch (e) {
        print('Error migrating task ${task.name}: $e');
        errors++;
      }
    }

    // Migrate existing habits
    final habits = await queryHabitsRecordOnce(userId: uid);
    for (final habit in habits) {
      try {
        await TaskInstanceService.initializeHabitInstances(
          templateId: habit.reference.id,
          template: habit,
          userId: uid,
        );
        habitsMigrated++;
      } catch (e) {
        print('Error migrating habit ${habit.name}: $e');
        errors++;
      }
    }

    print(
        'Migration completed: $tasksMigrated tasks, $habitsMigrated habits, $errors errors');
    return {
      'tasks': tasksMigrated,
      'habits': habitsMigrated,
      'errors': errors,
    };
  } catch (e) {
    print('Error during migration: $e');
    return {
      'tasks': tasksMigrated,
      'habits': habitsMigrated,
      'errors': errors + 1
    };
  }
}
