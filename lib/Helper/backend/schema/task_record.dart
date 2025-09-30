import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class TaskRecord extends FirestoreRecord {
  TaskRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // Fields
  String? _name;
  String get name => _name ?? '';
  bool hasTitle() => _name != null;

  String? _status; // incomplete | complete
  String get status => _status ?? 'incomplete';
  bool hasStatus() => _status != null;

  DateTime? _dueDate;
  DateTime? get dueDate => _dueDate;
  bool hasDueDate() => _dueDate != null;

  int? _priority; // 1-3 priority level
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

  // "unit" field for quantity tracking (e.g., "glasses", "pages").
  String? _unit;
  String get unit => _unit ?? '';
  bool hasUnit() => _unit != null;

  // "showInFloatingTimer" field.
  bool? _showInFloatingTimer;
  bool get showInFloatingTimer => _showInFloatingTimer ?? false;
  bool hasShowInFloatingTimer() => _showInFloatingTimer != null;

  // "accumulatedTime" field for duration tracking (in milliseconds).
  int? _accumulatedTime;
  int get accumulatedTime => _accumulatedTime ?? 0;
  bool hasAccumulatedTime() => _accumulatedTime != null;

  // Manual order for drag & drop
  int? _manualOrder;
  int get manualOrder => _manualOrder ?? 0;
  bool hasManualOrder() => _manualOrder != null;

  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  DateTime? _completedTime;
  DateTime? get completedTime => _completedTime;
  bool hasCompletedTime() => _completedTime != null;

  String? _categoryId;
  String get categoryId => _categoryId ?? '';
  bool hasCategoryId() => _categoryId != null;

  String? _categoryName;
  String get categoryName => _categoryName ?? '';
  bool hasCategoryName() => _categoryName != null;

  // "specificDays" field for weekly recurring tasks.
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

  // "snoozedUntil" field to hide task until this date.
  DateTime? _snoozedUntil;
  DateTime? get snoozedUntil => _snoozedUntil;
  bool hasSnoozedUntil() => _snoozedUntil != null;

  // "isRecurring" field to distinguish between one-time and recurring tasks.
  bool? _isRecurring;
  bool get isRecurring => _isRecurring ?? false;
  bool hasIsRecurring() => _isRecurring != null;

  // "frequency" field.
  int? _frequency;
  int get frequency => _frequency ?? 1;
  bool hasFrequency() => _frequency != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "lastUpdated" field.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;

  // "dayEndTime" field for tracking.
  int? _dayEndTime;
  int get dayEndTime => _dayEndTime ?? 0;
  bool hasDayEndTime() => _dayEndTime != null;

  // "currentValue" field for progress tracking.
  dynamic _currentValue;
  dynamic get currentValue => _currentValue;
  bool hasCurrentValue() => _currentValue != null;

  void _initializeFields() {
    _name = snapshotData['name'] as String?;
    _status = snapshotData['status'] as String?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _priority = snapshotData['priority'] as int?;
    _trackingType = snapshotData['trackingType'] as String?;
    _target = snapshotData['target'];
    _schedule = snapshotData['schedule'] as String?;
    _unit = snapshotData['unit'] as String?;
    _showInFloatingTimer = snapshotData['showInFloatingTimer'] as bool?;
    _accumulatedTime = snapshotData['accumulatedTime'] as int?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _completedTime = snapshotData['completedTime'] as DateTime?;
    _categoryId = snapshotData['categoryId'] as String?;
    _categoryName = snapshotData['categoryName'] as String?;
    _specificDays = (snapshotData['specificDays'] as List?)?.cast<int>();
    _isTimerActive = snapshotData['isTimerActive'] as bool?;
    _timerStartTime = snapshotData['timerStartTime'] as DateTime?;
    _snoozedUntil = snapshotData['snoozedUntil'] as DateTime?;
    _isRecurring = snapshotData['isRecurring'] as bool?;
    _frequency = snapshotData['frequency'] as int?;
    _description = snapshotData['description'] as String?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _dayEndTime = snapshotData['dayEndTime'] as int?;
    _currentValue = snapshotData['currentValue'];
    _manualOrder = snapshotData['manualOrder'] as int?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('tasks');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks');

  static Stream<TaskRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => TaskRecord.fromSnapshot(s));

  static Future<TaskRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => TaskRecord.fromSnapshot(s));

  static TaskRecord fromSnapshot(DocumentSnapshot snapshot) => TaskRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static TaskRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      TaskRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'TaskRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is TaskRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createTaskRecordData({
  String? title,
  String? description,
  String? status,
  DateTime? dueDate,
  int? priority,
  String? trackingType,
  dynamic target,
  String? schedule,
  String? unit,
  bool? showInFloatingTimer,
  int? accumulatedTime,
  int? manualOrder,
  bool? isActive,
  DateTime? createdTime,
  DateTime? completedTime,
  String? categoryId,
  String? categoryName,
  List<int>? specificDays,
  bool? isTimerActive,
  DateTime? timerStartTime,
  DateTime? snoozedUntil,
  bool? isRecurring,
  int? frequency,
  DateTime? lastUpdated,
  int? dayEndTime,
  dynamic currentValue,
}) {
  final firestoreData = mapToFirestore(<String, dynamic>{
    'name': title,
    'status': status,
    'dueDate': dueDate,
    'priority': priority,
    'trackingType': trackingType,
    'target': target,
    'schedule': schedule,
    'unit': unit,
    'showInFloatingTimer': showInFloatingTimer,
    'accumulatedTime': accumulatedTime,
    'manualOrder': manualOrder,
    'isActive': isActive,
    'createdTime': createdTime,
    'completedTime': completedTime,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'specificDays': specificDays,
    'isTimerActive': isTimerActive,
    'timerStartTime': timerStartTime,
    'snoozedUntil': snoozedUntil,
    'isRecurring': isRecurring,
    'frequency': frequency,
    'description': description,
    'lastUpdated': lastUpdated,
    'dayEndTime': dayEndTime,
    'currentValue': currentValue,
  }.withoutNulls);

  return firestoreData;
}

class TaskRecordDocumentEquality implements Equality<TaskRecord> {
  const TaskRecordDocumentEquality();

  @override
  bool equals(TaskRecord? e1, TaskRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.status == e2?.status &&
        e1?.dueDate == e2?.dueDate &&
        e1?.priority == e2?.priority &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.completedTime == e2?.completedTime &&
        e1?.categoryId == e2?.categoryId &&
        e1?.categoryName == e2?.categoryName;
  }

  @override
  int hash(TaskRecord? e) => const ListEquality().hash([
        e?.name,
        e?.status,
        e?.dueDate,
        e?.priority,
        e?.isActive,
        e?.createdTime,
        e?.completedTime,
        e?.categoryId,
        e?.categoryName,
      ]);

  @override
  bool isValidKey(Object? o) => o is TaskRecord;
}
