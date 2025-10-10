import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class ActivityRecord extends FirestoreRecord {
  ActivityRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

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

  // "priority" field (1-3 priority level).
  int? _priority;
  int get priority => _priority ?? 1;
  bool hasPriority() => _priority != null;

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
  String get schedule => _schedule ?? '';
  bool hasSchedule() => _schedule != null;

  // "frequency" field.
  int? _frequency;
  int? get frequency => _frequency;
  bool hasFrequency() => _frequency != null;

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
  List<int> get specificDays => _specificDays ?? const [];
  bool hasSpecificDays() => _specificDays != null;

  // New frequency fields
  String? _frequencyType;
  String get frequencyType => _frequencyType ?? '';
  bool hasFrequencyType() => _frequencyType != null;

  int? _everyXValue;
  int get everyXValue => _everyXValue ?? 1;
  bool hasEveryXValue() => _everyXValue != null;

  String? _everyXPeriodType;
  String get everyXPeriodType => _everyXPeriodType ?? '';
  bool hasEveryXPeriodType() => _everyXPeriodType != null;

  int? _timesPerPeriod;
  int get timesPerPeriod => _timesPerPeriod ?? 1;
  bool hasTimesPerPeriod() => _timesPerPeriod != null;

  String? _periodType;
  String get periodType => _periodType ?? '';
  bool hasPeriodType() => _periodType != null;

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

  // "snoozedUntil" field to hide habit from Task until this date (inclusive start next day).
  DateTime? _snoozedUntil;
  DateTime? get snoozedUntil => _snoozedUntil;
  bool hasSnoozedUntil() => _snoozedUntil != null;

  // "isRecurring" field: true for habits and recurring tasks, false for one-time tasks.
  bool? _isRecurring;
  bool get isRecurring => _isRecurring ?? true;
  bool hasIsRecurring() => _isRecurring != null;

  // "dueDate" field for one-time tasks.
  DateTime? _dueDate;
  DateTime? get dueDate => _dueDate;
  bool hasDueDate() => _dueDate != null;

  // "status" field for completion status ('incomplete' | 'complete').
  String? _status;
  String get status => _status ?? 'incomplete';
  bool hasStatus() => _status != null;

  // "startDate" field for habit start date.
  DateTime? _startDate;
  DateTime? get startDate => _startDate;
  bool hasStartDate() => _startDate != null;

  // "endDate" field for habit end date (null means perpetual).
  DateTime? _endDate;
  DateTime? get endDate => _endDate;
  bool hasEndDate() => _endDate != null;

  // "skippedDates" field for tracking explicit skips (snoozed days)
  List<DateTime>? _skippedDates;
  List<DateTime> get skippedDates => _skippedDates ?? [];
  bool hasSkippedDates() => _skippedDates != null;

  // "completedDates" field for tracking completion history.
  List<DateTime>? _completedDates;
  List<DateTime> get completedDates => _completedDates ?? [];
  bool hasCompletedDates() => _completedDates != null;

  // "weeklyTarget" field.
  int? _weeklyTarget;
  int get weeklyTarget => _weeklyTarget ?? 1;
  bool hasWeeklyTarget() => _weeklyTarget != null;

  String? _categoryType;
  String get categoryType => _categoryType ?? 'habit';
  bool hasCategoryType() => _categoryType != null;

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _categoryId = snapshotData['categoryId'] as String?;
    _categoryName = snapshotData['categoryName'] as String?;
    _impactLevel = snapshotData['impactLevel'] as String?;
    _completedDates =
        (snapshotData['completedDates'] as List?)?.cast<DateTime>();
    _weeklyTarget = snapshotData['weeklyTarget'] as int?;
    _priority = snapshotData['priority'] as int?;
    _trackingType = snapshotData['trackingType'] as String?;
    _target = snapshotData['target'];
    _schedule = snapshotData['schedule'] as String?;
    _frequency = snapshotData['frequency'] as int?;
    _description = snapshotData['description'] as String?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _userId = snapshotData['userId'] as String?;
    _unit = snapshotData['unit'] as String?;
    _currentValue = snapshotData['currentValue'];
    _dayEndTime = snapshotData['dayEndTime'] as int?;
    _specificDays = (snapshotData['specificDays'] as List?)?.cast<int>();
    _isTimerActive = snapshotData['isTimerActive'] as bool?;
    _timerStartTime = snapshotData['timerStartTime'] as DateTime?;
    _accumulatedTime = snapshotData['accumulatedTime'] as int?;
    _showInFloatingTimer = snapshotData['showInFloatingTimer'] as bool?;
    _manualOrder = snapshotData['manualOrder'] as int?;
    _snoozedUntil = snapshotData['snoozedUntil'] as DateTime?;
    _isRecurring = snapshotData['isRecurring'] as bool?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _status = snapshotData['status'] as String?;
    _startDate = snapshotData['startDate'] as DateTime?;
    _endDate = snapshotData['endDate'] as DateTime?;
    _skippedDates = (snapshotData['skippedDates'] as List?)?.cast<DateTime>();
    _categoryType = snapshotData['categoryType'] as String?;
    _frequencyType = snapshotData['frequencyType'] as String?;
    _everyXValue = snapshotData['everyXValue'] as int?;
    _everyXPeriodType = snapshotData['everyXPeriodType'] as String?;
    _timesPerPeriod = snapshotData['timesPerPeriod'] as int?;
    _periodType = snapshotData['periodType'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('activities');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('activities');

  static Stream<ActivityRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ActivityRecord.fromSnapshot(s));

  static Future<ActivityRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => ActivityRecord.fromSnapshot(s));

  static ActivityRecord fromSnapshot(DocumentSnapshot snapshot) {
    final snapshotData = snapshot.data() as Map<String, dynamic>;
    try {
      return ActivityRecord._(
        snapshot.reference,
        mapFromFirestore(snapshotData),
      );
    } catch (e) {
      print('ERROR parsing ActivityRecord: ${snapshot.id}');
      print('Data: $snapshotData');
      print('Error: $e');
      rethrow;
    }
  }

  static ActivityRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ActivityRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ActivityRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ActivityRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createActivityRecordData({
  String? name,
  String? categoryId,
  String? categoryName,
  String? categoryType,
  String? impactLevel,
  List<DateTime>? completedDates,
  int? weeklyTarget,
  List<DateTime>? skippedDates,
  int? priority,
  String? trackingType,
  dynamic target,
  String? schedule,
  int? frequency,
  String? description,
  bool? isActive,
  DateTime? createdTime,
  DateTime? lastUpdated,
  String? userId,
  String? unit,
  dynamic currentValue,
  int? dayEndTime,
  List<int>? specificDays,
  bool? isTimerActive,
  DateTime? timerStartTime,
  int? accumulatedTime,
  bool? showInFloatingTimer,
  int? manualOrder,
  DateTime? snoozedUntil,
  bool? isRecurring,
  DateTime? dueDate,
  String? status,
  DateTime? startDate,
  DateTime? endDate,
  String? frequencyType,
  int? everyXValue,
  String? everyXPeriodType,
  int? timesPerPeriod,
  String? periodType,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'name': name,
      'categoryId': categoryId,
      'categoryName': categoryName,
      'categoryType': categoryType,
      'impactLevel': impactLevel,
      'completedDates': completedDates,
      'weeklyTarget': weeklyTarget,
      'skippedDates': skippedDates,
      'priority': priority,
      'trackingType': trackingType,
      'target': target,
      'schedule': schedule,
      'frequency': frequency,
      'description': description,
      'isActive': isActive,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'userId': userId,
      'unit': unit,
      'currentValue': currentValue,
      'dayEndTime': dayEndTime,
      'specificDays': specificDays,
      'isTimerActive': isTimerActive,
      'timerStartTime': timerStartTime,
      'accumulatedTime': accumulatedTime,
      'showInFloatingTimer': showInFloatingTimer,
      'manualOrder': manualOrder,
      'snoozedUntil': snoozedUntil,
      'isRecurring': isRecurring,
      'dueDate': dueDate,
      'status': status,
      'startDate': startDate,
      'endDate': endDate,
      'frequencyType': frequencyType,
      'everyXValue': everyXValue,
      'everyXPeriodType': everyXPeriodType,
      'timesPerPeriod': timesPerPeriod,
      'periodType': periodType,
    }.withoutNulls,
  );

  return firestoreData;
}

class ActivityRecordDocumentEquality implements Equality<ActivityRecord> {
  const ActivityRecordDocumentEquality();

  @override
  bool equals(ActivityRecord? e1, ActivityRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.categoryId == e2?.categoryId &&
        e1?.categoryName == e2?.categoryName &&
        e1?.impactLevel == e2?.impactLevel &&
        e1?.priority == e2?.priority &&
        e1?.trackingType == e2?.trackingType &&
        e1?.target == e2?.target &&
        e1?.schedule == e2?.schedule &&
        e1?.frequency == e2?.frequency &&
        e1?.description == e2?.description &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.userId == e2?.userId &&
        e1?.unit == e2?.unit &&
        e1?.currentValue == e2?.currentValue &&
        e1?.dayEndTime == e2?.dayEndTime &&
        listEquals(e1?.specificDays, e2?.specificDays) &&
        listEquals(e1?.completedDates, e2?.completedDates) &&
        e1?.weeklyTarget == e2?.weeklyTarget &&
        e1?.isTimerActive == e2?.isTimerActive &&
        e1?.timerStartTime == e2?.timerStartTime &&
        e1?.accumulatedTime == e2?.accumulatedTime &&
        e1?.snoozedUntil == e2?.snoozedUntil &&
        e1?.isRecurring == e2?.isRecurring &&
        e1?.dueDate == e2?.dueDate &&
        e1?.status == e2?.status &&
        e1?.startDate == e2?.startDate &&
        e1?.endDate == e2?.endDate &&
        e1?.categoryType == e2?.categoryType &&
        e1?.frequencyType == e2?.frequencyType &&
        e1?.everyXValue == e2?.everyXValue &&
        e1?.everyXPeriodType == e2?.everyXPeriodType &&
        e1?.timesPerPeriod == e2?.timesPerPeriod &&
        e1?.periodType == e2?.periodType;
  }

  @override
  int hash(ActivityRecord? e) => const ListEquality().hash([
        e?.name,
        e?.categoryId,
        e?.categoryName,
        e?.impactLevel,
        e?.priority,
        e?.completedDates,
        e?.trackingType,
        e?.target,
        e?.schedule,
        e?.frequency,
        e?.description,
        e?.isActive,
        e?.createdTime,
        e?.lastUpdated,
        e?.userId,
        e?.unit,
        e?.weeklyTarget,
        e?.currentValue,
        e?.dayEndTime,
        e?.specificDays,
        e?.isTimerActive,
        e?.timerStartTime,
        e?.accumulatedTime,
        e?.snoozedUntil,
        e?.isRecurring,
        e?.dueDate,
        e?.status,
        e?.startDate,
        e?.endDate,
        e?.categoryType,
        e?.frequencyType,
        e?.everyXValue,
        e?.everyXPeriodType,
        e?.timesPerPeriod,
        e?.periodType
      ]);

  @override
  bool isValidKey(Object? o) => o is ActivityRecord;
}
