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
  String get schedule => _schedule ?? 'daily';
  bool hasSchedule() => _schedule != null;

  // "frequency" field.
  int? _frequency;
  int get frequency => _frequency ?? 1;
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
  List<int> get specificDays => _specificDays ?? [];
  bool hasSpecificDays() => _specificDays != null;

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

  // "isRecurring" field to distinguish between tasks (false) and habits (true).
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

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _categoryId = snapshotData['categoryId'] as String?;
    _categoryName = snapshotData['categoryName'] as String?;
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
  String? name,
  String? categoryId,
  String? categoryName,
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
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'name': name,
      'categoryId': categoryId,
      'categoryName': categoryName,
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
    }.withoutNulls,
  );

  return firestoreData;
}

class HabitRecordDocumentEquality implements Equality<HabitRecord> {
  const HabitRecordDocumentEquality();

  @override
  bool equals(HabitRecord? e1, HabitRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.categoryId == e2?.categoryId &&
        e1?.categoryName == e2?.categoryName &&
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
        e1?.isTimerActive == e2?.isTimerActive &&
        e1?.timerStartTime == e2?.timerStartTime &&
        e1?.accumulatedTime == e2?.accumulatedTime &&
        e1?.snoozedUntil == e2?.snoozedUntil &&
        e1?.isRecurring == e2?.isRecurring &&
        e1?.dueDate == e2?.dueDate &&
        e1?.status == e2?.status;
  }

  @override
  int hash(HabitRecord? e) => const ListEquality().hash([
        e?.name,
        e?.categoryId,
        e?.categoryName,
        e?.priority,
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
      ]);

  @override
  bool isValidKey(Object? o) => o is HabitRecord;
}
