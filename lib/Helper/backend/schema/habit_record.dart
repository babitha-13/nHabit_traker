import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class HabitRecord extends FirestoreRecord {
  HabitRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "categoryId" field.
  String? _categoryId;
  String get categoryId => _categoryId ?? '';
  bool hasCategoryId() => _categoryId != null;

  // "categoryName" field.
  String? _categoryName;
  String get categoryName => _categoryName ?? '';
  bool hasCategoryName() => _categoryName != null;

  // "impactLevel" field.
  String? _impactLevel;
  String get impactLevel => _impactLevel ?? 'Medium';
  bool hasImpactLevel() => _impactLevel != null;

  // "trackingType" field.
  String? _trackingType;
  String get trackingType => _trackingType ?? 'binary';
  bool hasTrackingType() => _trackingType != null;

  // "target" field.
  dynamic _target;
  dynamic get target => _target;
  bool hasTarget() => _target != null;

  // "schedule" field.
  String? _schedule;
  String get schedule => _schedule ?? 'daily';
  bool hasSchedule() => _schedule != null;

  // "weeklyTarget" field.
  int? _weeklyTarget;
  int get weeklyTarget => _weeklyTarget ?? 1;
  bool hasWeeklyTarget() => _weeklyTarget != null;

  int? _weight;
  int get weight => _weight ?? 1;
  bool hasweight() => _weight !=null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "isActive" field.
  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  // "createdTime" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  // "lastUpdated" field.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;

  // "userId" field.
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;

  // "unit" field for quantity tracking (e.g., "glasses", "pages").
  String? _unit;
  String get unit => _unit ?? '';
  bool hasUnit() => _unit != null;

  // "currentValue" field to track daily progress.
  dynamic _currentValue;
  dynamic get currentValue => _currentValue;
  bool hasCurrentValue() => _currentValue != null;

  // "dayEndTime" field for custom day boundaries (in minutes from midnight).
  int? _dayEndTime;
  int get dayEndTime => _dayEndTime ?? 0; // 0 = midnight (12 AM)
  bool hasDayEndTime() => _dayEndTime != null;

  // "specificDays" field for weekly scheduling (list of day indices: 1=Monday, 7=Sunday).
  List<int>? _specificDays;
  List<int> get specificDays => _specificDays ?? [];
  bool hasSpecificDays() => _specificDays != null;

  // "lastCompletedDate" field for frequency tracking.
  DateTime? _lastCompletedDate;
  DateTime? get lastCompletedDate => _lastCompletedDate;
  bool hasLastCompletedDate() => _lastCompletedDate != null;

  // "completedDates" field for tracking completion history.
  List<DateTime>? _completedDates;
  List<DateTime> get completedDates => _completedDates ?? [];
  bool hasCompletedDates() => _completedDates != null;

  // "skippedDates" field for tracking explicit skips (snoozed days)
  List<DateTime>? _skippedDates;
  List<DateTime> get skippedDates => _skippedDates ?? [];
  bool hasSkippedDates() => _skippedDates != null;

  // "isTimerActive" field for duration tracking.
  bool? _isTimerActive;
  bool get isTimerActive => _isTimerActive ?? false;
  bool hasIsTimerActive() => _isTimerActive != null;

  // "timerStartTime" field for duration tracking.
  DateTime? _timerStartTime;
  DateTime? get timerStartTime => _timerStartTime;
  bool hasTimerStartTime() => _timerStartTime != null;

  // "accumulatedTime" field for duration tracking (in milliseconds).
  int? _accumulatedTime;
  int get accumulatedTime => _accumulatedTime ?? 0;
  bool hasAccumulatedTime() => _accumulatedTime != null;

  // "showInFloatingTimer" persisted control for floating timer visibility.
  bool? _showInFloatingTimer;
  bool get showInFloatingTimer => _showInFloatingTimer ?? false;
  bool hasShowInFloatingTimer() => _showInFloatingTimer != null;

  // Manual order for drag & drop
  int? _manualOrder;
  int get manualOrder => _manualOrder ?? 0;
  bool hasManualOrder() => _manualOrder != null;

  // "priority" field to mirror tasks' 3-star importance (0-3).
  int? _priority;
  int get priority => _priority ?? 0;
  bool hasPriority() => _priority != null;

  // "snoozedUntil" field to hide habit from Task until this date (inclusive start next day).
  DateTime? _snoozedUntil;
  DateTime? get snoozedUntil => _snoozedUntil;
  bool hasSnoozedUntil() => _snoozedUntil != null;

  // "isRecurring" field to distinguish between tasks (false) and habits (true).
  bool? _isRecurring;
  bool get isRecurring => _isRecurring ?? true;
  bool hasIsRecurring() => _isRecurring != null;

  // "dueDate" field for one-time tasks.
  DateTime? _dueDate;
  DateTime? get dueDate => _dueDate;
  bool hasDueDate() => _dueDate != null;

  // "taskStatus" field for task completion status ('todo' | 'doing' | 'done').
  String? _taskStatus;
  String get taskStatus => _taskStatus ?? 'incomplete';
  bool hasTaskStatus() => _taskStatus != null;

  void _initializeFields() {
    _weight =snapshotData['weight'] as int?;
    _uid = snapshotData['uid'] as String?;
    _name = snapshotData['name'] as String?;
    _categoryId = snapshotData['categoryId'] as String?;
    _categoryName = snapshotData['categoryName'] as String?;
    _impactLevel = snapshotData['impactLevel'] as String?;
    _trackingType = snapshotData['trackingType'] as String?;
    _target = snapshotData['target'];
    _schedule = snapshotData['schedule'] as String?;
    _weeklyTarget = snapshotData['weeklyTarget'] as int?;
    _description = snapshotData['description'] as String?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _userId = snapshotData['userId'] as String?;
    _unit = snapshotData['unit'] as String?;
    _currentValue = snapshotData['currentValue'];
    _dayEndTime = snapshotData['dayEndTime'] as int?;
    _specificDays = (snapshotData['specificDays'] as List?)?.cast<int>();
    _lastCompletedDate = snapshotData['lastCompletedDate'] as DateTime?;
    _completedDates =
        (snapshotData['completedDates'] as List?)?.cast<DateTime>();
    _skippedDates = (snapshotData['skippedDates'] as List?)?.cast<DateTime>();
    _isTimerActive = snapshotData['isTimerActive'] as bool?;
    _timerStartTime = snapshotData['timerStartTime'] as DateTime?;
    _accumulatedTime = snapshotData['accumulatedTime'] as int?;
    _showInFloatingTimer = snapshotData['showInFloatingTimer'] as bool?;
    _manualOrder = snapshotData['manualOrder'] as int?;
    _priority = snapshotData['priority'] as int?;
    _snoozedUntil = snapshotData['snoozedUntil'] as DateTime?;
    _isRecurring = snapshotData['isRecurring'] as bool?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _taskStatus = snapshotData['taskStatus'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('habits');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('habits');

  static Stream<HabitRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => HabitRecord.fromSnapshot(s));

  static Future<HabitRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => HabitRecord.fromSnapshot(s));

  static HabitRecord fromSnapshot(DocumentSnapshot snapshot) => HabitRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static HabitRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      HabitRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'HabitRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is HabitRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createHabitRecordData({
  int? weight,
  String? uid,
  String? name,
  String? categoryId,
  String? categoryName,
  String? impactLevel,
  String? trackingType,
  dynamic target,
  String? schedule,
  int? weeklyTarget,
  String? description,
  bool? isActive,
  DateTime? createdTime,
  DateTime? lastUpdated,
  String? userId,
  String? unit,
  dynamic currentValue,
  int? dayEndTime,
  List<int>? specificDays,
  DateTime? lastCompletedDate,
  List<DateTime>? completedDates,
  List<DateTime>? skippedDates,
  bool? isTimerActive,
  DateTime? timerStartTime,
  int? accumulatedTime,
  bool? showInFloatingTimer,
  int? manualOrder,
  int? priority,
  DateTime? snoozedUntil,
  bool? isRecurring,
  DateTime? dueDate,
  String? taskStatus,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'weight': weight,
      'uid': uid,
      'name': name,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'impactLevel': impactLevel,
      'trackingType': trackingType,
      'target': target,
      'schedule': schedule,
      'weeklyTarget': weeklyTarget,
      'description': description,
      'isActive': isActive,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'userId': userId,
      'unit': unit,
      'currentValue': currentValue,
      'dayEndTime': dayEndTime,
      'specificDays': specificDays,
      'lastCompletedDate': lastCompletedDate,
      'completedDates': completedDates,
      'skippedDates': skippedDates,
      'isTimerActive': isTimerActive,
      'timerStartTime': timerStartTime,
      'accumulatedTime': accumulatedTime,
      'showInFloatingTimer': showInFloatingTimer,
      'manualOrder': manualOrder,
      'priority': priority,
      'snoozedUntil': snoozedUntil,
      'isRecurring': isRecurring,
      'dueDate': dueDate,
      'taskStatus': taskStatus,
    }.withoutNulls,
  );

  return firestoreData;
}

class HabitRecordDocumentEquality implements Equality<HabitRecord> {
  const HabitRecordDocumentEquality();

  @override
  bool equals(HabitRecord? e1, HabitRecord? e2) {
    return e1?.weight == e2?.weight &&
      e1?.uid == e2?.uid &&
        e1?.name == e2?.name &&
        e1?.categoryId == e2?.categoryId &&
        e1?.categoryName == e2?.categoryName &&
        e1?.impactLevel == e2?.impactLevel &&
        e1?.trackingType == e2?.trackingType &&
        e1?.target == e2?.target &&
        e1?.schedule == e2?.schedule &&
        e1?.weeklyTarget == e2?.weeklyTarget &&
        e1?.description == e2?.description &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.userId == e2?.userId &&
        e1?.unit == e2?.unit &&
        e1?.currentValue == e2?.currentValue &&
        e1?.dayEndTime == e2?.dayEndTime &&
        listEquals(e1?.specificDays, e2?.specificDays) &&
        e1?.lastCompletedDate == e2?.lastCompletedDate &&
        listEquals(e1?.completedDates, e2?.completedDates) &&
        e1?.isTimerActive == e2?.isTimerActive &&
        e1?.timerStartTime == e2?.timerStartTime &&
        e1?.accumulatedTime == e2?.accumulatedTime &&
        e1?.priority == e2?.priority &&
        e1?.snoozedUntil == e2?.snoozedUntil &&
        e1?.isRecurring == e2?.isRecurring &&
        e1?.dueDate == e2?.dueDate &&
        e1?.taskStatus == e2?.taskStatus;
  }

  @override
  int hash(HabitRecord? e) => const ListEquality().hash([
        e?.weight,
        e?.uid,
        e?.name,
        e?.categoryId,
        e?.categoryName,
        e?.impactLevel,
        e?.trackingType,
        e?.target,
        e?.schedule,
        e?.weeklyTarget,
        e?.description,
        e?.isActive,
        e?.createdTime,
        e?.lastUpdated,
        e?.userId,
        e?.unit,
        e?.currentValue,
        e?.dayEndTime,
        e?.specificDays,
        e?.lastCompletedDate,
        e?.completedDates,
        e?.isTimerActive,
        e?.timerStartTime,
        e?.accumulatedTime,
        e?.priority,
        e?.snoozedUntil,
        e?.isRecurring,
        e?.dueDate,
        e?.taskStatus,
      ]);

  @override
  bool isValidKey(Object? o) => o is HabitRecord;
}
