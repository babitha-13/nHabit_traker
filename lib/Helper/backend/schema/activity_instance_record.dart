import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class ActivityInstanceRecord extends FirestoreRecord {
  ActivityInstanceRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // Reference to the template activity
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

  // Progress tracking for quantity/duration activities
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

  String? _templateCategoryType;
  String get templateCategoryType => _templateCategoryType ?? 'habit';
  bool hasTemplateCategoryType() => _templateCategoryType != null;

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

  String? _templateDescription;
  String get templateDescription => _templateDescription ?? '';
  bool hasTemplateDescription() => _templateDescription != null;

  bool? _templateShowInFloatingTimer;
  bool get templateShowInFloatingTimer => _templateShowInFloatingTimer ?? false;
  bool hasTemplateShowInFloatingTimer() => _templateShowInFloatingTimer != null;

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
    _templateCategoryType = snapshotData['templateCategoryType'] as String?;
    _templatePriority = snapshotData['templatePriority'] as int?;
    _templateTrackingType = snapshotData['templateTrackingType'] as String?;
    _templateTarget = snapshotData['templateTarget'];
    _templateUnit = snapshotData['templateUnit'] as String?;
    _templateDescription = snapshotData['templateDescription'] as String?;
    _templateShowInFloatingTimer =
        snapshotData['templateShowInFloatingTimer'] as bool?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('activity_instances');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('activity_instances');

  static Stream<ActivityInstanceRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => ActivityInstanceRecord.fromSnapshot(s));

  static Future<ActivityInstanceRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => ActivityInstanceRecord.fromSnapshot(s));

  static ActivityInstanceRecord fromSnapshot(DocumentSnapshot snapshot) {
    final snapshotData = snapshot.data() as Map<String, dynamic>;
    try {
      return ActivityInstanceRecord._(
        snapshot.reference,
        mapFromFirestore(snapshotData),
      );
    } catch (e) {
      print('Error creating ActivityInstanceRecord from snapshot: $e');
      rethrow;
    }
  }

  static ActivityInstanceRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      ActivityInstanceRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'ActivityInstanceRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is ActivityInstanceRecord &&
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
  String? templateCategoryType,
  int? templatePriority,
  String? templateTrackingType,
  dynamic templateTarget,
  String? templateUnit,
  String? templateDescription,
  bool? templateShowInFloatingTimer,
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
      'templateCategoryType': templateCategoryType,
      'templatePriority': templatePriority,
      'templateTrackingType': templateTrackingType,
      'templateTarget': templateTarget,
      'templateUnit': templateUnit,
      'templateDescription': templateDescription,
      'templateShowInFloatingTimer': templateShowInFloatingTimer,
    }.withoutNulls,
  );

  return firestoreData;
}

class ActivityInstanceRecordDocumentEquality
    implements Equality<ActivityInstanceRecord> {
  const ActivityInstanceRecordDocumentEquality();

  @override
  bool isValidKey(Object? o) => o is ActivityInstanceRecord;

  @override
  bool equals(ActivityInstanceRecord? e1, ActivityInstanceRecord? e2) {
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
        e1?.templateCategoryType == e2?.templateCategoryType &&
        e1?.templatePriority == e2?.templatePriority &&
        e1?.templateTrackingType == e2?.templateTrackingType &&
        e1?.templateTarget == e2?.templateTarget &&
        e1?.templateUnit == e2?.templateUnit &&
        e1?.templateDescription == e2?.templateDescription &&
        e1?.templateShowInFloatingTimer == e2?.templateShowInFloatingTimer;
  }

  @override
  int hash(ActivityInstanceRecord? e) => const ListEquality().hash([
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
        e?.templateCategoryType,
        e?.templatePriority,
        e?.templateTrackingType,
        e?.templateTarget,
        e?.templateUnit,
        e?.templateDescription,
        e?.templateShowInFloatingTimer,
      ]);
}
