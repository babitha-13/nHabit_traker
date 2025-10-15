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

  // "categoryBreakdown" field - per-category stats
  Map<String, dynamic>? _categoryBreakdown;
  Map<String, dynamic> get categoryBreakdown => _categoryBreakdown ?? {};
  bool hasCategoryBreakdown() => _categoryBreakdown != null;

  // "createdAt" field
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "lastEditedAt" field - if user corrected historical data
  DateTime? _lastEditedAt;
  DateTime? get lastEditedAt => _lastEditedAt;
  bool hasLastEditedAt() => _lastEditedAt != null;

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
    _categoryBreakdown =
        snapshotData['categoryBreakdown'] as Map<String, dynamic>?;
    _createdAt = snapshotData['createdAt'] as DateTime?;
    _lastEditedAt = snapshotData['lastEditedAt'] as DateTime?;
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
      print('Error creating DailyProgressRecord from snapshot: $e');
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
  Map<String, dynamic>? categoryBreakdown,
  DateTime? createdAt,
  DateTime? lastEditedAt,
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
      'categoryBreakdown': categoryBreakdown,
      'createdAt': createdAt,
      'lastEditedAt': lastEditedAt,
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
        const MapEquality()
            .equals(e1?.categoryBreakdown, e2?.categoryBreakdown) &&
        e1?.createdAt == e2?.createdAt &&
        e1?.lastEditedAt == e2?.lastEditedAt;
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
        const MapEquality().hash(e?.categoryBreakdown),
        e?.createdAt,
        e?.lastEditedAt,
      ]);
}
