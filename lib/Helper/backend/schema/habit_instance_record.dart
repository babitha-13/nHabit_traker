import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class HabitInstanceRecord extends FirestoreRecord {
  HabitInstanceRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // Reference to the template habit
  String? _templateId;
  String get templateId => _templateId ?? '';
  bool hasTemplateId() => _templateId != null;

  // Instance-specific fields
  DateTime? _dueDate;
  DateTime? get dueDate => _dueDate;
  bool hasDueDate() => _dueDate != null;

  String? _status; // 'pending', 'completed', 'skipped'
  String get status => _status ?? 'pending';
  bool hasStatus() => _status != null;

  DateTime? _completedAt;
  DateTime? get completedAt => _completedAt;
  bool hasCompletedAt() => _completedAt != null;

  DateTime? _skippedAt;
  DateTime? get skippedAt => _skippedAt;
  bool hasSkippedAt() => _skippedAt != null;

  // Progress tracking for quantity/duration habits
  dynamic _currentValue;
  dynamic get currentValue => _currentValue;
  bool hasCurrentValue() => _currentValue != null;

  int? _accumulatedTime; // For duration tracking (milliseconds)
  int get accumulatedTime => _accumulatedTime ?? 0;
  bool hasAccumulatedTime() => _accumulatedTime != null;

  bool? _isTimerActive;
  bool get isTimerActive => _isTimerActive ?? false;
  bool hasIsTimerActive() => _isTimerActive != null;

  DateTime? _timerStartTime;
  DateTime? get timerStartTime => _timerStartTime;
  bool hasTimerStartTime() => _timerStartTime != null;

  // Metadata
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;

  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  // User notes for this specific instance
  String? _notes;
  String get notes => _notes ?? '';
  bool hasNotes() => _notes != null;

  // Template data cached for quick access (denormalized)
  String? _templateName;
  String get templateName => _templateName ?? '';
  bool hasTemplateName() => _templateName != null;

  String? _templateCategoryId;
  String get templateCategoryId => _templateCategoryId ?? '';
  bool hasTemplateCategoryId() => _templateCategoryId != null;

  String? _templateCategoryName;
  String get templateCategoryName => _templateCategoryName ?? '';
  bool hasTemplateCategoryName() => _templateCategoryName != null;

  int? _templatePriority;
  int get templatePriority => _templatePriority ?? 1;
  bool hasTemplatePriority() => _templatePriority != null;

  String? _templateTrackingType;
  String get templateTrackingType => _templateTrackingType ?? 'binary';
  bool hasTemplateTrackingType() => _templateTrackingType != null;

  dynamic _templateTarget;
  dynamic get templateTarget => _templateTarget;
  bool hasTemplateTarget() => _templateTarget != null;

  String? _templateUnit;
  String get templateUnit => _templateUnit ?? '';
  bool hasTemplateUnit() => _templateUnit != null;

  // Template frequency fields (cached from template)
  int? _templateEveryXValue;
  int get templateEveryXValue => _templateEveryXValue ?? 1;
  bool hasTemplateEveryXValue() => _templateEveryXValue != null;

  String? _templateEveryXPeriodType;
  String get templateEveryXPeriodType => _templateEveryXPeriodType ?? '';
  bool hasTemplateEveryXPeriodType() => _templateEveryXPeriodType != null;

  int? _templateTimesPerPeriod;
  int get templateTimesPerPeriod => _templateTimesPerPeriod ?? 1;
  bool hasTemplateTimesPerPeriod() => _templateTimesPerPeriod != null;

  String? _templatePeriodType;
  String get templatePeriodType => _templatePeriodType ?? '';
  bool hasTemplatePeriodType() => _templatePeriodType != null;

  // Habit-specific day state tracking

  String? _dayState; // 'open', 'closed' (habits only)
  String get dayState => _dayState ?? 'open';
  bool hasDayState() => _dayState != null;

  // Supporting fields for habits
  DateTime? _belongsToDate; // Normalized date this counts for (habits only)
  DateTime? get belongsToDate => _belongsToDate;
  bool hasBelongsToDate() => _belongsToDate != null;

  DateTime? _closedAt; // When dayState changed to 'closed'
  DateTime? get closedAt => _closedAt;
  bool hasClosedAt() => _closedAt != null;

  void _initializeFields() {
    _templateId = snapshotData['templateId'] as String?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _status = snapshotData['status'] as String?;
    _completedAt = snapshotData['completedAt'] as DateTime?;
    _skippedAt = snapshotData['skippedAt'] as DateTime?;
    _currentValue = snapshotData['currentValue'];
    _accumulatedTime = snapshotData['accumulatedTime'] as int?;
    _isTimerActive = snapshotData['isTimerActive'] as bool?;
    _timerStartTime = snapshotData['timerStartTime'] as DateTime?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _isActive = snapshotData['isActive'] as bool?;
    _notes = snapshotData['notes'] as String?;
    _templateName = snapshotData['templateName'] as String?;
    _templateCategoryId = snapshotData['templateCategoryId'] as String?;
    _templateCategoryName = snapshotData['templateCategoryName'] as String?;
    _templatePriority = snapshotData['templatePriority'] as int?;
    _templateTrackingType = snapshotData['templateTrackingType'] as String?;
    _templateTarget = snapshotData['templateTarget'];
    _templateUnit = snapshotData['templateUnit'] as String?;
    _templateEveryXValue = snapshotData['templateEveryXValue'] as int?;
    _templateEveryXPeriodType =
        snapshotData['templateEveryXPeriodType'] as String?;
    _templateTimesPerPeriod = snapshotData['templateTimesPerPeriod'] as int?;
    _templatePeriodType = snapshotData['templatePeriodType'] as String?;
    _dayState = snapshotData['dayState'] as String?;
    _belongsToDate = snapshotData['belongsToDate'] as DateTime?;
    _closedAt = snapshotData['closedAt'] as DateTime?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('habit_instances');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('habit_instances');

  static Stream<HabitInstanceRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => HabitInstanceRecord.fromSnapshot(s));

  static Future<HabitInstanceRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => HabitInstanceRecord.fromSnapshot(s));

  static HabitInstanceRecord fromSnapshot(DocumentSnapshot snapshot) =>
      HabitInstanceRecord._(
        snapshot.reference,
        snapshot.data() as Map<String, dynamic>,
      );

  static HabitInstanceRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      HabitInstanceRecord._(reference, data);

  @override
  String toString() =>
      'HabitInstanceRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is HabitInstanceRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createActivityInstanceRecordData({
  String? templateId,
  DateTime? dueDate,
  String? status,
  DateTime? completedAt,
  DateTime? skippedAt,
  dynamic currentValue,
  int? accumulatedTime,
  bool? isTimerActive,
  DateTime? timerStartTime,
  DateTime? createdTime,
  DateTime? lastUpdated,
  bool? isActive,
  String? notes,
  String? templateName,
  String? templateCategoryId,
  String? templateCategoryName,
  int? templatePriority,
  String? templateTrackingType,
  dynamic templateTarget,
  String? templateUnit,
  String? templateDescription,
  bool? templateShowInFloatingTimer,
  bool? templateIsRecurring,
  int? templateEveryXValue,
  String? templateEveryXPeriodType,
  int? templateTimesPerPeriod,
  String? templatePeriodType,
  String? dayState,
  DateTime? belongsToDate,
  DateTime? closedAt,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'templateId': templateId,
      'dueDate': dueDate,
      'status': status,
      'completedAt': completedAt,
      'skippedAt': skippedAt,
      'currentValue': currentValue,
      'accumulatedTime': accumulatedTime,
      'isTimerActive': isTimerActive,
      'timerStartTime': timerStartTime,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'isActive': isActive,
      'notes': notes,
      'templateName': templateName,
      'templateCategoryId': templateCategoryId,
      'templateCategoryName': templateCategoryName,
      'templatePriority': templatePriority,
      'templateTrackingType': templateTrackingType,
      'templateTarget': templateTarget,
      'templateUnit': templateUnit,
      'templateDescription': templateDescription,
      'templateShowInFloatingTimer': templateShowInFloatingTimer,
      'templateIsRecurring': templateIsRecurring,
      'templateEveryXValue': templateEveryXValue,
      'templateEveryXPeriodType': templateEveryXPeriodType,
      'templateTimesPerPeriod': templateTimesPerPeriod,
      'templatePeriodType': templatePeriodType,
      'dayState': dayState,
      'belongsToDate': belongsToDate,
      'closedAt': closedAt,
    }.withoutNulls,
  );

  return firestoreData;
}

class HabitInstanceRecordDocumentEquality
    implements Equality<HabitInstanceRecord> {
  const HabitInstanceRecordDocumentEquality();

  @override
  bool isValidKey(Object? o) => o is HabitInstanceRecord;

  @override
  bool equals(HabitInstanceRecord? e1, HabitInstanceRecord? e2) {
    return e1?.templateId == e2?.templateId &&
        e1?.dueDate == e2?.dueDate &&
        e1?.status == e2?.status &&
        e1?.completedAt == e2?.completedAt &&
        e1?.skippedAt == e2?.skippedAt &&
        e1?.currentValue == e2?.currentValue &&
        e1?.accumulatedTime == e2?.accumulatedTime &&
        e1?.isTimerActive == e2?.isTimerActive &&
        e1?.timerStartTime == e2?.timerStartTime &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.isActive == e2?.isActive &&
        e1?.notes == e2?.notes &&
        e1?.templateName == e2?.templateName &&
        e1?.templateCategoryId == e2?.templateCategoryId &&
        e1?.templateCategoryName == e2?.templateCategoryName &&
        e1?.templatePriority == e2?.templatePriority &&
        e1?.templateTrackingType == e2?.templateTrackingType &&
        e1?.templateTarget == e2?.templateTarget &&
        e1?.templateUnit == e2?.templateUnit;
  }

  @override
  int hash(HabitInstanceRecord? e) => const ListEquality().hash([
        e?.templateId,
        e?.dueDate,
        e?.status,
        e?.completedAt,
        e?.skippedAt,
        e?.currentValue,
        e?.accumulatedTime,
        e?.isTimerActive,
        e?.timerStartTime,
        e?.createdTime,
        e?.lastUpdated,
        e?.isActive,
        e?.notes,
        e?.templateName,
        e?.templateCategoryId,
        e?.templateCategoryName,
        e?.templatePriority,
        e?.templateTrackingType,
        e?.templateTarget,
        e?.templateUnit,
      ]);
}
