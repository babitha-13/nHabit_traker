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
    final query = HabitRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdTime', descending: true);
    final result = await query.get();
    return result.docs.map((doc) => HabitRecord.fromSnapshot(doc)).toList();
  } catch (e) {
    // Fallback if an index is missing: retry without orderBy
    print('queryHabitsRecordOnce: falling back without orderBy due to: $e');
    final fallbackQuery = HabitRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true);
    final result = await fallbackQuery.get();
    return result.docs.map((doc) => HabitRecord.fromSnapshot(doc)).toList();
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
    final query = CategoryRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true)
        .where('categoryType', isEqualTo: 'habit');

    final result = await query.get();
    final categories =
        result.docs.map((doc) => CategoryRecord.fromSnapshot(doc)).toList();

    // Sort in memory instead of in query
    categories.sort((a, b) => a.name.compareTo(b.name));
    return categories;
  } catch (e) {
    print('Error querying habit categories: $e');
    // Fallback: get all categories and filter in memory
    final allCategories = await queryCategoriesRecordOnce(userId: userId);
    return allCategories.where((c) => c.categoryType == 'habit').toList();
  }
}

/// Query to get task categories for a specific user
Future<List<CategoryRecord>> queryTaskCategoriesOnce({
  required String userId,
}) async {
  try {
    final query = CategoryRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true)
        .where('categoryType', isEqualTo: 'task');

    final result = await query.get();
    final categories =
        result.docs.map((doc) => CategoryRecord.fromSnapshot(doc)).toList();

    // Sort in memory instead of in query
    categories.sort((a, b) => a.name.compareTo(b.name));
    return categories;
  } catch (e) {
    print('Error querying task categories: $e');
    // Fallback: get all categories and filter in memory
    final allCategories = await queryCategoriesRecordOnce(userId: userId);
    return allCategories.where((c) => c.categoryType == 'task').toList();
  }
}

/// Query to get tasks for a specific user
Future<List<TaskRecord>> queryTasksRecordOnce({
  required String userId,
}) async {
  try {
    final query = TaskRecord.collectionForUser(userId)
        .where('isActive', isEqualTo: true)
        .orderBy('createdTime', descending: true);
    final result = await query.get();
    return result.docs.map((doc) => TaskRecord.fromSnapshot(doc)).toList();
  } catch (e) {
    // Fallback if an index is missing: retry without orderBy
    print('queryTasksRecordOnce: falling back without orderBy due to: $e');
    final fallbackQuery =
        TaskRecord.collectionForUser(userId).where('isActive', isEqualTo: true);
    final result = await fallbackQuery.get();
    return result.docs.map((doc) => TaskRecord.fromSnapshot(doc)).toList();
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
  required String impactLevel,
  required String trackingType,
  dynamic target,
  required String schedule,
  int weeklyTarget = 1,
  String? description,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  final habitData = createHabitRecordData(
    name: name,
    categoryName: categoryName,
    impactLevel: impactLevel,
    trackingType: trackingType,
    target: target,
    schedule: schedule,
    weeklyTarget: weeklyTarget,
    description: description,
    isActive: true,
    createdTime: DateTime.now(),
    lastUpdated: DateTime.now(),
  );

  return await HabitRecord.collectionForUser(uid).add(habitData);
}

/// Create a new category
Future<DocumentReference> createCategory({
  required String name,
  String? description,
  double weight = 1.0,
  String? color,
  String? userId,
  required String categoryType, // Must be 'habit' or 'task'
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
  );

  return await CategoryRecord.collectionForUser(uid).add(categoryData);
}

/// Create a default or new task (defaults to default category if none provided)
Future<DocumentReference> createTask({
  required String title,
  String? description,
  DateTime? dueDate,
  int priority =
      1, // Changed from 0 to 1 - all tasks should have at least 1 star
  String? categoryId,
  String? categoryName,
  String? habitId,
  String? userId,
}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';

  // Ensure we have a category; if not, fallback to default
  String resolvedCategoryName = categoryName ?? 'inbox';
  String resolvedCategoryId = categoryId ?? '';

  if (resolvedCategoryId.isEmpty) {
    // Try to find existing default category
    final defaultQuery = await CategoryRecord.collectionForUser(uid)
        .where('name', isEqualTo: 'inbox')
        .limit(1)
        .get();
    if (defaultQuery.docs.isNotEmpty) {
      resolvedCategoryId = defaultQuery.docs.first.id;
      resolvedCategoryName =
          (defaultQuery.docs.first.data() as Map<String, dynamic>)['name'] ??
              'inbox';
    } else {
      // Create default category for this user
      final newDefault = await createCategory(
        name: 'inbox',
        color: CategoryColorUtil.hexForName('inbox'),
        weight: 1.0,
        userId: uid,
        categoryType: 'task',
      );
      resolvedCategoryId = newDefault.id;
      resolvedCategoryName = 'inbox';
    }
  }

  final taskData = createTaskRecordData(
    title: title,
    description: description,
    status: 'incomplete',
    dueDate: dueDate,
    priority: priority,
    isActive: true,
    createdTime: DateTime.now(),
    categoryId: resolvedCategoryId,
    categoryName: resolvedCategoryName,
    habitId: habitId,
  );

  return await TaskRecord.collectionForUser(uid).add(taskData);
}

/// Migrate existing categories to have categoryType field
/// This should be called once to update old categories
Future<int> migrateCategoryTypes({String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) return 0;

  final query = await CategoryRecord.collectionForUser(uid).get();
  int updated = 0;
  for (final doc in query.docs) {
    final data = doc.data() as Map<String, dynamic>;
    final categoryType = data['categoryType'] as String?;

    // If categoryType is missing, set default to 'habit'
    if (categoryType == null || categoryType.isEmpty) {
      await doc.reference.update({
        'categoryType': 'habit', // Default to habit for existing categories
        'lastUpdated': DateTime.now(),
      });
      updated += 1;
      print('Migrated category ${data['name']} to habit type');
    }
  }
  return updated;
}

/// Normalize all existing category colors for the current user to the
/// Slate + Copper palette deterministically by category name.
/// Returns the number of categories updated.
Future<int> normalizeCategoryColors({String? userId}) async {
  final currentUser = FirebaseAuth.instance.currentUser;
  final uid = userId ?? currentUser?.uid ?? '';
  if (uid.isEmpty) return 0;

  final query = await CategoryRecord.collectionForUser(uid).get();
  int updated = 0;
  for (final doc in query.docs) {
    final data = doc.data() as Map<String, dynamic>;
    final name = (data['name'] ?? '').toString();
    if (name.isEmpty) continue;
    final desired = CategoryColorUtil.hexForName(name);
    final current = (data['color'] ?? '').toString();
    if (current != desired) {
      await doc.reference.update({
        'color': desired,
        'lastUpdated': DateTime.now(),
      });
      updated += 1;
    }
  }
  return updated;
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
  String? habitId,
}) async {
  final updateData = <String, dynamic>{
    'lastUpdated': DateTime.now(),
  };

  if (title != null) updateData['title'] = title;
  if (description != null) updateData['description'] = description;
  if (status != null) updateData['status'] = status;
  if (dueDate != null) updateData['dueDate'] = dueDate;
  if (priority != null) updateData['priority'] = priority;
  if (manualOrder != null) updateData['manualOrder'] = manualOrder;
  if (isActive != null) updateData['isActive'] = isActive;
  if (completedTime != null) updateData['completedTime'] = completedTime;
  if (categoryId != null) updateData['categoryId'] = categoryId;
  if (categoryName != null) updateData['categoryName'] = categoryName;
  if (habitId != null) updateData['habitId'] = habitId;

  await taskRef.update(updateData);
}

/// Soft delete a task
Future<void> deleteTask(DocumentReference taskRef) async {
  await taskRef.update({
    'isActive': false,
    'lastUpdated': DateTime.now(),
  });
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
  String? impactLevel,
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
  if (impactLevel != null) updateData['impactLevel'] = impactLevel;
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
