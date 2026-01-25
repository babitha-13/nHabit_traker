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
  // Instance-specific due time (stored as "HH:mm" in 24-hour format)
  String? _dueTime;
  String? get dueTime => _dueTime;
  bool hasDueTime() => _dueTime != null;
  // Use to track the original due date before rescheduling (for recurring tasks)
  DateTime? _originalDueDate;
  DateTime? get originalDueDate => _originalDueDate;
  bool hasOriginalDueDate() => _originalDueDate != null;
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
  // Differential progress tracking for windowed habits
  dynamic _lastDayValue;
  dynamic get lastDayValue => _lastDayValue;
  bool hasLastDayValue() => _lastDayValue != null;
  int? _accumulatedTime; // For duration tracking (milliseconds)
  int get accumulatedTime => _accumulatedTime ?? 0;
  bool hasAccumulatedTime() => _accumulatedTime != null;
  bool? _isTimerActive;
  bool get isTimerActive => _isTimerActive ?? false;
  bool hasIsTimerActive() => _isTimerActive != null;
  DateTime? _timerStartTime;
  DateTime? get timerStartTime => _timerStartTime;
  bool hasTimerStartTime() => _timerStartTime != null;
  // Time logging fields - NEW
  List<dynamic>? _timeLogSessions;
  List<Map<String, dynamic>> get timeLogSessions {
    if (_timeLogSessions == null) return [];
    return _timeLogSessions!.map((session) {
      return {
        'startTime': session['startTime'] as DateTime,
        'endTime': session['endTime'] as DateTime?,
        'durationMilliseconds': session['durationMilliseconds'] as int,
      };
    }).toList();
  }

  bool hasTimeLogSessions() => _timeLogSessions != null;
  DateTime? _currentSessionStartTime;
  DateTime? get currentSessionStartTime => _currentSessionStartTime;
  bool hasCurrentSessionStartTime() => _currentSessionStartTime != null;
  bool? _isTimeLogging;
  bool get isTimeLogging => _isTimeLogging ?? false;
  bool hasIsTimeLogging() => _isTimeLogging != null;
  int? _totalTimeLogged; // Sum of all sessions in milliseconds
  int get totalTimeLogged => _totalTimeLogged ?? 0;
  bool hasTotalTimeLogged() => _totalTimeLogged != null;
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
  String? _templateCategoryColor;
  String get templateCategoryColor => _templateCategoryColor ?? '';
  bool hasTemplateCategoryColor() => _templateCategoryColor != null;
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
  int? _templateTimeEstimateMinutes;
  int? get templateTimeEstimateMinutes => _templateTimeEstimateMinutes;
  bool hasTemplateTimeEstimateMinutes() => _templateTimeEstimateMinutes != null;
  // Template due time (denormalized from template)
  String? _templateDueTime;
  String? get templateDueTime => _templateDueTime;
  bool hasTemplateDueTime() => _templateDueTime != null;
  bool? _templateShowInFloatingTimer;
  bool get templateShowInFloatingTimer => _templateShowInFloatingTimer ?? false;
  bool hasTemplateShowInFloatingTimer() => _templateShowInFloatingTimer != null;
  // Template recurring flag (cached from template)
  bool? _templateIsRecurring;
  bool get templateIsRecurring => _templateIsRecurring ?? true;
  bool hasTemplateIsRecurring() => _templateIsRecurring != null;
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
  // Window fields for habit completion windows
  DateTime? _windowEndDate; // End of completion window
  DateTime? get windowEndDate => _windowEndDate;
  bool hasWindowEndDate() => _windowEndDate != null;
  int? _windowDuration; // Duration in days (cached from template)
  int get windowDuration => _windowDuration ?? 1;
  bool hasWindowDuration() => _windowDuration != null;
  // Snooze fields for temporarily hiding from queue
  DateTime? _snoozedUntil; // When snooze expires
  DateTime? get snoozedUntil => _snoozedUntil;
  bool hasSnoozedUntil() => _snoozedUntil != null;
  // Order fields for drag-to-reorder functionality (per page)
  int? _queueOrder; // Order position in Queue page
  int get queueOrder => _queueOrder ?? 0;
  bool hasQueueOrder() => _queueOrder != null;
  int? _habitsOrder; // Order position in Habits page
  int get habitsOrder => _habitsOrder ?? 0;
  bool hasHabitsOrder() => _habitsOrder != null;
  int? _tasksOrder; // Order position in Tasks page
  int get tasksOrder => _tasksOrder ?? 0;
  bool hasTasksOrder() => _tasksOrder != null;
  void _initializeFields() {
    _templateId = snapshotData['templateId'] as String?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _dueTime = snapshotData['dueTime'] as String?;
    _originalDueDate = snapshotData['originalDueDate'] as DateTime?;
    _status = snapshotData['status'] as String?;
    _completedAt = snapshotData['completedAt'] as DateTime?;
    _skippedAt = snapshotData['skippedAt'] as DateTime?;
    _currentValue = snapshotData['currentValue'];
    _lastDayValue = snapshotData['lastDayValue'];
    _accumulatedTime = snapshotData['accumulatedTime'] as int?;
    _isTimerActive = snapshotData['isTimerActive'] as bool?;
    _timerStartTime = snapshotData['timerStartTime'] as DateTime?;
    _timeLogSessions = snapshotData['timeLogSessions'] as List<dynamic>?;
    _currentSessionStartTime =
        snapshotData['currentSessionStartTime'] as DateTime?;
    _isTimeLogging = snapshotData['isTimeLogging'] as bool?;
    _totalTimeLogged = snapshotData['totalTimeLogged'] as int?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _isActive = snapshotData['isActive'] as bool?;
    _notes = snapshotData['notes'] as String?;
    _templateName = snapshotData['templateName'] as String?;
    _templateCategoryId = snapshotData['templateCategoryId'] as String?;
    _templateCategoryName = snapshotData['templateCategoryName'] as String?;
    _templateCategoryType = snapshotData['templateCategoryType'] as String?;
    _templateCategoryColor = snapshotData['templateCategoryColor'] as String?;
    _templatePriority = snapshotData['templatePriority'] as int?;
    _templateTrackingType = snapshotData['templateTrackingType'] as String?;
    _templateTarget = snapshotData['templateTarget'];
    _templateUnit = snapshotData['templateUnit'] as String?;
    _templateDescription = snapshotData['templateDescription'] as String?;
    _templateTimeEstimateMinutes =
        snapshotData['templateTimeEstimateMinutes'] as int?;
    _templateShowInFloatingTimer =
        snapshotData['templateShowInFloatingTimer'] as bool?;
    _templateIsRecurring = snapshotData['templateIsRecurring'] as bool?;
    _templateEveryXValue = snapshotData['templateEveryXValue'] as int?;
    _templateEveryXPeriodType =
        snapshotData['templateEveryXPeriodType'] as String?;
    _templateTimesPerPeriod = snapshotData['templateTimesPerPeriod'] as int?;
    _templatePeriodType = snapshotData['templatePeriodType'] as String?;
    _templateDueTime = snapshotData['templateDueTime'] as String?;
    _dayState = snapshotData['dayState'] as String?;
    _belongsToDate = snapshotData['belongsToDate'] as DateTime?;
    _closedAt = snapshotData['closedAt'] as DateTime?;
    _windowEndDate = snapshotData['windowEndDate'] as DateTime?;
    _windowDuration = snapshotData['windowDuration'] as int?;
    _snoozedUntil = snapshotData['snoozedUntil'] as DateTime?;
    _queueOrder = snapshotData['queueOrder'] as int?;
    _habitsOrder = snapshotData['habitsOrder'] as int?;
    _tasksOrder = snapshotData['tasksOrder'] as int?;
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
  String? dueTime,
  DateTime? originalDueDate,
  String? status,
  DateTime? completedAt,
  DateTime? skippedAt,
  dynamic currentValue,
  dynamic lastDayValue,
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
  String? templateCategoryColor,
  int? templatePriority,
  String? templateTrackingType,
  dynamic templateTarget,
  String? templateUnit,
  String? templateDescription,
  int? templateTimeEstimateMinutes,
  bool? templateShowInFloatingTimer,
  bool? templateIsRecurring,
  int? templateEveryXValue,
  String? templateEveryXPeriodType,
  int? templateTimesPerPeriod,
  String? templatePeriodType,
  String? templateDueTime,
  String? dayState,
  DateTime? belongsToDate,
  DateTime? closedAt,
  DateTime? windowEndDate,
  int? windowDuration,
  int? queueOrder,
  int? habitsOrder,
  int? tasksOrder,
  List<dynamic>? timeLogSessions,
  DateTime? currentSessionStartTime,
  bool? isTimeLogging,
  int? totalTimeLogged,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'templateId': templateId,
      'dueDate': dueDate,
      'dueTime': dueTime,
      'originalDueDate': originalDueDate,
      'status': status,
      'completedAt': completedAt,
      'skippedAt': skippedAt,
      'currentValue': currentValue,
      'lastDayValue': lastDayValue,
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
      'templateCategoryColor': templateCategoryColor,
      'templatePriority': templatePriority,
      'templateTrackingType': templateTrackingType,
      'templateTarget': templateTarget,
      'templateUnit': templateUnit,
      'templateDescription': templateDescription,
      'templateTimeEstimateMinutes': templateTimeEstimateMinutes,
      'templateShowInFloatingTimer': templateShowInFloatingTimer,
      'templateIsRecurring': templateIsRecurring,
      'templateEveryXValue': templateEveryXValue,
      'templateEveryXPeriodType': templateEveryXPeriodType,
      'templateTimesPerPeriod': templateTimesPerPeriod,
      'templatePeriodType': templatePeriodType,
      'templateDueTime': templateDueTime,
      'dayState': dayState,
      'belongsToDate': belongsToDate,
      'closedAt': closedAt,
      'windowEndDate': windowEndDate,
      'windowDuration': windowDuration,
      'queueOrder': queueOrder,
      'habitsOrder': habitsOrder,
      'tasksOrder': tasksOrder,
      'timeLogSessions': timeLogSessions,
      'currentSessionStartTime': currentSessionStartTime,
      'isTimeLogging': isTimeLogging,
      'totalTimeLogged': totalTimeLogged,
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
        e1?.originalDueDate == e2?.originalDueDate &&
        e1?.status == e2?.status &&
        e1?.completedAt == e2?.completedAt &&
        e1?.skippedAt == e2?.skippedAt &&
        e1?.currentValue == e2?.currentValue &&
        e1?.lastDayValue == e2?.lastDayValue &&
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
        e1?.templateTimeEstimateMinutes == e2?.templateTimeEstimateMinutes &&
        e1?.templateShowInFloatingTimer == e2?.templateShowInFloatingTimer &&
        e1?.templateEveryXValue == e2?.templateEveryXValue &&
        e1?.templateEveryXPeriodType == e2?.templateEveryXPeriodType &&
        e1?.templateTimesPerPeriod == e2?.templateTimesPerPeriod &&
        e1?.templatePeriodType == e2?.templatePeriodType &&
        e1?.dayState == e2?.dayState &&
        e1?.belongsToDate == e2?.belongsToDate &&
        e1?.closedAt == e2?.closedAt &&
        e1?.windowEndDate == e2?.windowEndDate &&
        e1?.windowDuration == e2?.windowDuration &&
        e1?.queueOrder == e2?.queueOrder &&
        e1?.habitsOrder == e2?.habitsOrder &&
        e1?.tasksOrder == e2?.tasksOrder &&
        e1?.timeLogSessions == e2?.timeLogSessions &&
        e1?.currentSessionStartTime == e2?.currentSessionStartTime &&
        e1?.isTimeLogging == e2?.isTimeLogging &&
        e1?.totalTimeLogged == e2?.totalTimeLogged;
  }

  @override
  int hash(ActivityInstanceRecord? e) => const ListEquality().hash([
        e?.templateId,
        e?.dueDate,
        e?.originalDueDate,
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
        e?.templateTimeEstimateMinutes,
        e?.templateShowInFloatingTimer,
        e?.templateEveryXValue,
        e?.templateEveryXPeriodType,
        e?.templateTimesPerPeriod,
        e?.templatePeriodType,
        e?.dayState,
        e?.belongsToDate,
        e?.closedAt,
        e?.windowEndDate,
        e?.windowDuration,
        e?.queueOrder,
        e?.habitsOrder,
        e?.tasksOrder,
        e?.timeLogSessions,
        e?.currentSessionStartTime,
        e?.isTimeLogging,
        e?.totalTimeLogged,
      ]);
}
