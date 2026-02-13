import 'dart:async';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class DailyProgressRecord extends FirestoreRecord {
  DailyProgressRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }
  // "userId" field.
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;
  // "date" field - normalized to 00:00:00
  DateTime? _date;
  DateTime? get date => _date;
  bool hasDate() => _date != null;
  // "targetPoints" field - total daily target for all habits
  double? _targetPoints;
  double get targetPoints => _targetPoints ?? 0.0;
  bool hasTargetPoints() => _targetPoints != null;
  // "earnedPoints" field - total points earned from habits
  double? _earnedPoints;
  double get earnedPoints => _earnedPoints ?? 0.0;
  bool hasEarnedPoints() => _earnedPoints != null;
  // "completionPercentage" field
  double? _completionPercentage;
  double get completionPercentage => _completionPercentage ?? 0.0;
  bool hasCompletionPercentage() => _completionPercentage != null;
  // "totalHabits" field - habits scheduled for this day
  int? _totalHabits;
  int get totalHabits => _totalHabits ?? 0;
  bool hasTotalHabits() => _totalHabits != null;
  // "completedHabits" field - fully completed
  int? _completedHabits;
  int get completedHabits => _completedHabits ?? 0;
  bool hasCompletedHabits() => _completedHabits != null;
  // "partialHabits" field - partial completion (e.g., 6/8 glasses)
  int? _partialHabits;
  int get partialHabits => _partialHabits ?? 0;
  bool hasPartialHabits() => _partialHabits != null;
  // "skippedHabits" field - auto-closed or manually skipped
  int? _skippedHabits;
  int get skippedHabits => _skippedHabits ?? 0;
  bool hasSkippedHabits() => _skippedHabits != null;
  // "totalTasks" field - tasks scheduled for this day
  int? _totalTasks;
  int get totalTasks => _totalTasks ?? 0;
  bool hasTotalTasks() => _totalTasks != null;
  // "completedTasks" field - fully completed
  int? _completedTasks;
  int get completedTasks => _completedTasks ?? 0;
  bool hasCompletedTasks() => _completedTasks != null;
  // "partialTasks" field - partial completion (e.g., 6/8 items)
  int? _partialTasks;
  int get partialTasks => _partialTasks ?? 0;
  bool hasPartialTasks() => _partialTasks != null;
  // "skippedTasks" field - manually skipped or rescheduled
  int? _skippedTasks;
  int get skippedTasks => _skippedTasks ?? 0;
  bool hasSkippedTasks() => _skippedTasks != null;
  // "taskTargetPoints" field - total daily target for all tasks
  double? _taskTargetPoints;
  double get taskTargetPoints => _taskTargetPoints ?? 0.0;
  bool hasTaskTargetPoints() => _taskTargetPoints != null;
  // "taskEarnedPoints" field - total points earned from tasks
  double? _taskEarnedPoints;
  double get taskEarnedPoints => _taskEarnedPoints ?? 0.0;
  bool hasTaskEarnedPoints() => _taskEarnedPoints != null;
  // "categoryBreakdown" field - per-category stats
  Map<String, dynamic>? _categoryBreakdown;
  Map<String, dynamic> get categoryBreakdown => _categoryBreakdown ?? {};
  bool hasCategoryBreakdown() => _categoryBreakdown != null;
  // "habitBreakdown" field - detailed breakdown of habits
  List<Map<String, dynamic>>? _habitBreakdown;
  List<Map<String, dynamic>> get habitBreakdown => _habitBreakdown ?? [];
  bool hasHabitBreakdown() => _habitBreakdown != null;
  // "taskBreakdown" field - detailed breakdown of tasks
  List<Map<String, dynamic>>? _taskBreakdown;
  List<Map<String, dynamic>> get taskBreakdown => _taskBreakdown ?? [];
  bool hasTaskBreakdown() => _taskBreakdown != null;
  // "createdAt" field
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;
  // "lastEditedAt" field - if user corrected historical data
  DateTime? _lastEditedAt;
  DateTime? get lastEditedAt => _lastEditedAt;
  bool hasLastEditedAt() => _lastEditedAt != null;
  // "cumulativeScoreSnapshot" field - cumulative score at end of day
  double? _cumulativeScoreSnapshot;
  double get cumulativeScoreSnapshot => _cumulativeScoreSnapshot ?? 0.0;
  bool hasCumulativeScoreSnapshot() => _cumulativeScoreSnapshot != null;
  // "dailyScoreGain" field - points gained/lost on this day
  double? _dailyScoreGain;
  double get dailyScoreGain => _dailyScoreGain ?? 0.0;
  bool hasDailyScoreGain() => _dailyScoreGain != null;
  // "decayPenalty" field
  double? _decayPenalty;
  double get decayPenalty => _decayPenalty ?? 0.0;
  bool hasDecayPenalty() => _decayPenalty != null;
  // "categoryNeglectPenalty" field
  double? _categoryNeglectPenalty;
  double get categoryNeglectPenalty => _categoryNeglectPenalty ?? 0.0;
  bool hasCategoryNeglectPenalty() => _categoryNeglectPenalty != null;
  // "consistencyBonus" field
  double? _consistencyBonus;
  double get consistencyBonus => _consistencyBonus ?? 0.0;
  bool hasConsistencyBonus() => _consistencyBonus != null;
  // "dailyPoints" field
  double? _dailyPoints;
  double get dailyPoints => _dailyPoints ?? 0.0;
  bool hasDailyPoints() => _dailyPoints != null;
  // "recoveryBonus" field
  double? _recoveryBonus;
  double get recoveryBonus => _recoveryBonus ?? 0.0;
  bool hasRecoveryBonus() => _recoveryBonus != null;
  void _initializeFields() {
    _userId = snapshotData['userId'] as String?;
    _date = snapshotData['date'] as DateTime?;
    _targetPoints = (snapshotData['targetPoints'] as num?)?.toDouble();
    _earnedPoints = (snapshotData['earnedPoints'] as num?)?.toDouble();
    _completionPercentage =
        (snapshotData['completionPercentage'] as num?)?.toDouble();
    _totalHabits = snapshotData['totalHabits'] as int?;
    _completedHabits = snapshotData['completedHabits'] as int?;
    _partialHabits = snapshotData['partialHabits'] as int?;
    _skippedHabits = snapshotData['skippedHabits'] as int?;
    _totalTasks = snapshotData['totalTasks'] as int?;
    _completedTasks = snapshotData['completedTasks'] as int?;
    _partialTasks = snapshotData['partialTasks'] as int?;
    _skippedTasks = snapshotData['skippedTasks'] as int?;
    _taskTargetPoints = (snapshotData['taskTargetPoints'] as num?)?.toDouble();
    _taskEarnedPoints = (snapshotData['taskEarnedPoints'] as num?)?.toDouble();
    _categoryBreakdown =
        snapshotData['categoryBreakdown'] as Map<String, dynamic>?;
    _habitBreakdown =
        (snapshotData['habitBreakdown'] as List?)?.cast<Map<String, dynamic>>();
    _taskBreakdown =
        (snapshotData['taskBreakdown'] as List?)?.cast<Map<String, dynamic>>();
    _createdAt = snapshotData['createdAt'] as DateTime?;
    _lastEditedAt = snapshotData['lastEditedAt'] as DateTime?;
    _cumulativeScoreSnapshot =
        (snapshotData['cumulativeScoreSnapshot'] as num?)?.toDouble();
    _dailyScoreGain = (snapshotData['dailyScoreGain'] as num?)?.toDouble();
    _decayPenalty = (snapshotData['decayPenalty'] as num?)?.toDouble();
    _categoryNeglectPenalty =
        (snapshotData['categoryNeglectPenalty'] as num?)?.toDouble();
    _consistencyBonus = (snapshotData['consistencyBonus'] as num?)?.toDouble();
    _dailyPoints = (snapshotData['dailyPoints'] as num?)?.toDouble();
    _recoveryBonus = (snapshotData['recoveryBonus'] as num?)?.toDouble();
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('daily_progress');
  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('daily_progress');
  static Stream<DailyProgressRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => DailyProgressRecord.fromSnapshot(s));
  static Future<DailyProgressRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => DailyProgressRecord.fromSnapshot(s));
  static DailyProgressRecord fromSnapshot(DocumentSnapshot snapshot) {
    final snapshotData = snapshot.data() as Map<String, dynamic>;
    try {
      return DailyProgressRecord._(
        snapshot.reference,
        mapFromFirestore(snapshotData),
      );
    } catch (e) {
      rethrow;
    }
  }

  static DailyProgressRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      DailyProgressRecord._(reference, mapFromFirestore(data));
  @override
  String toString() =>
      'DailyProgressRecord(reference: ${reference.path}, data: $snapshotData)';
  @override
  int get hashCode => reference.path.hashCode;
  @override
  bool operator ==(other) =>
      other is DailyProgressRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createDailyProgressRecordData({
  String? userId,
  DateTime? date,
  double? targetPoints,
  double? earnedPoints,
  double? completionPercentage,
  int? totalHabits,
  int? completedHabits,
  int? partialHabits,
  int? skippedHabits,
  int? totalTasks,
  int? completedTasks,
  int? partialTasks,
  int? skippedTasks,
  double? taskTargetPoints,
  double? taskEarnedPoints,
  Map<String, dynamic>? categoryBreakdown,
  List<Map<String, dynamic>>? habitBreakdown,
  List<Map<String, dynamic>>? taskBreakdown,
  DateTime? createdAt,
  DateTime? lastEditedAt,
  double? cumulativeScoreSnapshot,
  double? dailyScoreGain,
  double? effectiveGain,
  double? previousDayCumulativeScore,
  double? decayPenalty,
  double? categoryNeglectPenalty,
  double? consistencyBonus,
  double? dailyPoints,
  double? recoveryBonus,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'userId': userId,
      'date': date,
      'targetPoints': targetPoints,
      'earnedPoints': earnedPoints,
      'completionPercentage': completionPercentage,
      'totalHabits': totalHabits,
      'completedHabits': completedHabits,
      'partialHabits': partialHabits,
      'skippedHabits': skippedHabits,
      'totalTasks': totalTasks,
      'completedTasks': completedTasks,
      'partialTasks': partialTasks,
      'skippedTasks': skippedTasks,
      'taskTargetPoints': taskTargetPoints,
      'taskEarnedPoints': taskEarnedPoints,
      'categoryBreakdown': categoryBreakdown,
      'habitBreakdown': habitBreakdown,
      'taskBreakdown': taskBreakdown,
      'createdAt': createdAt,
      'lastEditedAt': lastEditedAt,
      'cumulativeScoreSnapshot': cumulativeScoreSnapshot,
      'dailyScoreGain': dailyScoreGain,
      'effectiveGain': effectiveGain,
      'previousDayCumulativeScore': previousDayCumulativeScore,
      'decayPenalty': decayPenalty,
      'categoryNeglectPenalty': categoryNeglectPenalty,
      'consistencyBonus': consistencyBonus,
      'dailyPoints': dailyPoints,
      'recoveryBonus': recoveryBonus,
    }.withoutNulls,
  );
  return firestoreData;
}

class DailyProgressRecordDocumentEquality
    implements Equality<DailyProgressRecord> {
  const DailyProgressRecordDocumentEquality();
  @override
  bool isValidKey(Object? o) => o is DailyProgressRecord;
  @override
  bool equals(DailyProgressRecord? e1, DailyProgressRecord? e2) {
    return e1?.userId == e2?.userId &&
        e1?.date == e2?.date &&
        e1?.targetPoints == e2?.targetPoints &&
        e1?.earnedPoints == e2?.earnedPoints &&
        e1?.completionPercentage == e2?.completionPercentage &&
        e1?.totalHabits == e2?.totalHabits &&
        e1?.completedHabits == e2?.completedHabits &&
        e1?.partialHabits == e2?.partialHabits &&
        e1?.skippedHabits == e2?.skippedHabits &&
        e1?.totalTasks == e2?.totalTasks &&
        e1?.completedTasks == e2?.completedTasks &&
        e1?.partialTasks == e2?.partialTasks &&
        e1?.skippedTasks == e2?.skippedTasks &&
        e1?.taskTargetPoints == e2?.taskTargetPoints &&
        e1?.taskEarnedPoints == e2?.taskEarnedPoints &&
        const MapEquality()
            .equals(e1?.categoryBreakdown, e2?.categoryBreakdown) &&
        e1?.createdAt == e2?.createdAt &&
        e1?.lastEditedAt == e2?.lastEditedAt &&
        e1?.cumulativeScoreSnapshot == e2?.cumulativeScoreSnapshot &&
        e1?.dailyScoreGain == e2?.dailyScoreGain &&
        e1?.decayPenalty == e2?.decayPenalty &&
        e1?.categoryNeglectPenalty == e2?.categoryNeglectPenalty &&
        e1?.consistencyBonus == e2?.consistencyBonus &&
        e1?.dailyPoints == e2?.dailyPoints &&
        e1?.recoveryBonus == e2?.recoveryBonus;
  }

  @override
  int hash(DailyProgressRecord? e) => const ListEquality().hash([
        e?.userId,
        e?.date,
        e?.targetPoints,
        e?.earnedPoints,
        e?.completionPercentage,
        e?.totalHabits,
        e?.completedHabits,
        e?.partialHabits,
        e?.skippedHabits,
        e?.totalTasks,
        e?.completedTasks,
        e?.partialTasks,
        e?.skippedTasks,
        e?.taskTargetPoints,
        e?.taskEarnedPoints,
        const MapEquality().hash(e?.categoryBreakdown),
        e?.createdAt,
        e?.lastEditedAt,
        e?.cumulativeScoreSnapshot,
        e?.dailyScoreGain,
        e?.decayPenalty,
        e?.categoryNeglectPenalty,
        e?.consistencyBonus,
        e?.dailyPoints,
        e?.recoveryBonus,
      ]);
}
