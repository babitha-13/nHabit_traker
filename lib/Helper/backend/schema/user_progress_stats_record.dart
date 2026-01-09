import 'dart:async';
import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class UserProgressStatsRecord extends FirestoreRecord {
  UserProgressStatsRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "userId" field
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;

  // "cumulativeScore" field - main cumulative progress score
  double? _cumulativeScore;
  double get cumulativeScore => _cumulativeScore ?? 0.0;
  bool hasCumulativeScore() => _cumulativeScore != null;

  // "lastCalculationDate" field - when score was last updated
  DateTime? _lastCalculationDate;
  DateTime? get lastCalculationDate => _lastCalculationDate;
  bool hasLastCalculationDate() => _lastCalculationDate != null;

  // "historicalHighScore" field - highest score ever achieved
  double? _historicalHighScore;
  double get historicalHighScore => _historicalHighScore ?? 0.0;
  bool hasHistoricalHighScore() => _historicalHighScore != null;

  // "totalDaysTracked" field - number of days contributing to score
  int? _totalDaysTracked;
  int get totalDaysTracked => _totalDaysTracked ?? 0;
  bool hasTotalDaysTracked() => _totalDaysTracked != null;

  // "currentStreak" field - current consistency streak (days >= 80%)
  int? _currentStreak;
  int get currentStreak => _currentStreak ?? 0;
  bool hasCurrentStreak() => _currentStreak != null;

  // "longestStreak" field - longest consistency streak achieved
  int? _longestStreak;
  int get longestStreak => _longestStreak ?? 0;
  bool hasLongestStreak() => _longestStreak != null;

  // "lastDailyGain" field - points gained/lost on last calculation
  double? _lastDailyGain;
  double get lastDailyGain => _lastDailyGain ?? 0.0;
  bool hasLastDailyGain() => _lastDailyGain != null;

  // "consecutiveLowDays" field - consecutive days with completion < 50%
  int? _consecutiveLowDays;
  int get consecutiveLowDays => _consecutiveLowDays ?? 0;
  bool hasConsecutiveLowDays() => _consecutiveLowDays != null;

  // "achievedMilestones" field - bitmask tracking achieved milestones
  int? _achievedMilestones;
  int get achievedMilestones => _achievedMilestones ?? 0;
  bool hasAchievedMilestones() => _achievedMilestones != null;

  // "createdAt" field
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "lastUpdatedAt" field
  DateTime? _lastUpdatedAt;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  bool hasLastUpdatedAt() => _lastUpdatedAt != null;

  // Aggregate statistics fields
  // "averageDailyScore7Day" field - 7-day average daily score gain
  double? _averageDailyScore7Day;
  double get averageDailyScore7Day => _averageDailyScore7Day ?? 0.0;
  bool hasAverageDailyScore7Day() => _averageDailyScore7Day != null;

  // "averageDailyScore30Day" field - 30-day average daily score gain
  double? _averageDailyScore30Day;
  double get averageDailyScore30Day => _averageDailyScore30Day ?? 0.0;
  bool hasAverageDailyScore30Day() => _averageDailyScore30Day != null;

  // "bestDailyScoreGain" field - highest single day gain
  double? _bestDailyScoreGain;
  double get bestDailyScoreGain => _bestDailyScoreGain ?? 0.0;
  bool hasBestDailyScoreGain() => _bestDailyScoreGain != null;

  // "worstDailyScoreGain" field - lowest single day gain
  double? _worstDailyScoreGain;
  double get worstDailyScoreGain => _worstDailyScoreGain ?? 0.0;
  bool hasWorstDailyScoreGain() => _worstDailyScoreGain != null;

  // "positiveDaysCount7Day" field - count of positive days in last 7 days
  int? _positiveDaysCount7Day;
  int get positiveDaysCount7Day => _positiveDaysCount7Day ?? 0;
  bool hasPositiveDaysCount7Day() => _positiveDaysCount7Day != null;

  // "positiveDaysCount30Day" field - count of positive days in last 30 days
  int? _positiveDaysCount30Day;
  int get positiveDaysCount30Day => _positiveDaysCount30Day ?? 0;
  bool hasPositiveDaysCount30Day() => _positiveDaysCount30Day != null;

  // "scoreGrowthRate7Day" field - average daily growth rate (7-day)
  double? _scoreGrowthRate7Day;
  double get scoreGrowthRate7Day => _scoreGrowthRate7Day ?? 0.0;
  bool hasScoreGrowthRate7Day() => _scoreGrowthRate7Day != null;

  // "scoreGrowthRate30Day" field - average daily growth rate (30-day)
  double? _scoreGrowthRate30Day;
  double get scoreGrowthRate30Day => _scoreGrowthRate30Day ?? 0.0;
  bool hasScoreGrowthRate30Day() => _scoreGrowthRate30Day != null;

  // "averageCumulativeScore7Day" field - 7-day rolling average of cumulative score
  double? _averageCumulativeScore7Day;
  double get averageCumulativeScore7Day => _averageCumulativeScore7Day ?? 0.0;
  bool hasAverageCumulativeScore7Day() => _averageCumulativeScore7Day != null;

  // "averageCumulativeScore30Day" field - 30-day rolling average of cumulative score
  double? _averageCumulativeScore30Day;
  double get averageCumulativeScore30Day => _averageCumulativeScore30Day ?? 0.0;
  bool hasAverageCumulativeScore30Day() => _averageCumulativeScore30Day != null;

  // "lastAggregateStatsCalculationDate" field - when aggregate stats were last calculated
  DateTime? _lastAggregateStatsCalculationDate;
  DateTime? get lastAggregateStatsCalculationDate => _lastAggregateStatsCalculationDate;
  bool hasLastAggregateStatsCalculationDate() => _lastAggregateStatsCalculationDate != null;

  void _initializeFields() {
    _userId = snapshotData['userId'] as String?;
    _cumulativeScore = (snapshotData['cumulativeScore'] as num?)?.toDouble();
    _lastCalculationDate = snapshotData['lastCalculationDate'] as DateTime?;
    _historicalHighScore =
        (snapshotData['historicalHighScore'] as num?)?.toDouble();
    _totalDaysTracked = snapshotData['totalDaysTracked'] as int?;
    _currentStreak = snapshotData['currentStreak'] as int?;
    _longestStreak = snapshotData['longestStreak'] as int?;
    _lastDailyGain = (snapshotData['lastDailyGain'] as num?)?.toDouble();
    _consecutiveLowDays = snapshotData['consecutiveLowDays'] as int?;
    _achievedMilestones = snapshotData['achievedMilestones'] as int?;
    _createdAt = snapshotData['createdAt'] as DateTime?;
    _lastUpdatedAt = snapshotData['lastUpdatedAt'] as DateTime?;
    _averageDailyScore7Day = (snapshotData['averageDailyScore7Day'] as num?)?.toDouble();
    _averageDailyScore30Day = (snapshotData['averageDailyScore30Day'] as num?)?.toDouble();
    _bestDailyScoreGain = (snapshotData['bestDailyScoreGain'] as num?)?.toDouble();
    _worstDailyScoreGain = (snapshotData['worstDailyScoreGain'] as num?)?.toDouble();
    _positiveDaysCount7Day = snapshotData['positiveDaysCount7Day'] as int?;
    _positiveDaysCount30Day = snapshotData['positiveDaysCount30Day'] as int?;
    _scoreGrowthRate7Day = (snapshotData['scoreGrowthRate7Day'] as num?)?.toDouble();
    _scoreGrowthRate30Day = (snapshotData['scoreGrowthRate30Day'] as num?)?.toDouble();
    _averageCumulativeScore7Day = (snapshotData['averageCumulativeScore7Day'] as num?)?.toDouble();
    _averageCumulativeScore30Day = (snapshotData['averageCumulativeScore30Day'] as num?)?.toDouble();
    _lastAggregateStatsCalculationDate = snapshotData['lastAggregateStatsCalculationDate'] as DateTime?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('user_progress_stats');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('progress_stats');

  static Stream<UserProgressStatsRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => UserProgressStatsRecord.fromSnapshot(s));

  static Future<UserProgressStatsRecord> getDocumentOnce(
          DocumentReference ref) async {
    final snapshot = await ref.get();
    if (!snapshot.exists) {
      throw Exception('Document does not exist: ${ref.path}');
    }
    return UserProgressStatsRecord.fromSnapshot(snapshot);
  }

  static UserProgressStatsRecord fromSnapshot(DocumentSnapshot snapshot) {
    final snapshotData = snapshot.data();
    if (snapshotData == null) {
      throw Exception('Document does not exist: ${snapshot.reference.path}');
    }
    try {
      return UserProgressStatsRecord._(
        snapshot.reference,
        mapFromFirestore(snapshotData as Map<String, dynamic>),
      );
    } catch (e) {
      rethrow;
    }
  }

  static UserProgressStatsRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      UserProgressStatsRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'UserProgressStatsRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is UserProgressStatsRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createUserProgressStatsRecordData({
  String? userId,
  double? cumulativeScore,
  DateTime? lastCalculationDate,
  double? historicalHighScore,
  int? totalDaysTracked,
  int? currentStreak,
  int? longestStreak,
  double? lastDailyGain,
  int? consecutiveLowDays,
  int? achievedMilestones,
  DateTime? createdAt,
  DateTime? lastUpdatedAt,
  double? averageDailyScore7Day,
  double? averageDailyScore30Day,
  double? bestDailyScoreGain,
  double? worstDailyScoreGain,
  int? positiveDaysCount7Day,
  int? positiveDaysCount30Day,
  double? scoreGrowthRate7Day,
  double? scoreGrowthRate30Day,
  double? averageCumulativeScore7Day,
  double? averageCumulativeScore30Day,
  DateTime? lastAggregateStatsCalculationDate,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'userId': userId,
      'cumulativeScore': cumulativeScore,
      'lastCalculationDate': lastCalculationDate,
      'historicalHighScore': historicalHighScore,
      'totalDaysTracked': totalDaysTracked,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastDailyGain': lastDailyGain,
      'consecutiveLowDays': consecutiveLowDays,
      'achievedMilestones': achievedMilestones,
      'createdAt': createdAt,
      'lastUpdatedAt': lastUpdatedAt,
      'averageDailyScore7Day': averageDailyScore7Day,
      'averageDailyScore30Day': averageDailyScore30Day,
      'bestDailyScoreGain': bestDailyScoreGain,
      'worstDailyScoreGain': worstDailyScoreGain,
      'positiveDaysCount7Day': positiveDaysCount7Day,
      'positiveDaysCount30Day': positiveDaysCount30Day,
      'scoreGrowthRate7Day': scoreGrowthRate7Day,
      'scoreGrowthRate30Day': scoreGrowthRate30Day,
      'averageCumulativeScore7Day': averageCumulativeScore7Day,
      'averageCumulativeScore30Day': averageCumulativeScore30Day,
      'lastAggregateStatsCalculationDate': lastAggregateStatsCalculationDate,
    }.withoutNulls,
  );
  return firestoreData;
}

class UserProgressStatsRecordDocumentEquality
    implements Equality<UserProgressStatsRecord> {
  const UserProgressStatsRecordDocumentEquality();

  @override
  bool isValidKey(Object? o) => o is UserProgressStatsRecord;

  @override
  bool equals(UserProgressStatsRecord? e1, UserProgressStatsRecord? e2) {
    return e1?.userId == e2?.userId &&
        e1?.cumulativeScore == e2?.cumulativeScore &&
        e1?.lastCalculationDate == e2?.lastCalculationDate &&
        e1?.historicalHighScore == e2?.historicalHighScore &&
        e1?.totalDaysTracked == e2?.totalDaysTracked &&
        e1?.currentStreak == e2?.currentStreak &&
        e1?.longestStreak == e2?.longestStreak &&
        e1?.lastDailyGain == e2?.lastDailyGain &&
        e1?.consecutiveLowDays == e2?.consecutiveLowDays &&
        e1?.achievedMilestones == e2?.achievedMilestones &&
        e1?.createdAt == e2?.createdAt &&
        e1?.lastUpdatedAt == e2?.lastUpdatedAt &&
        e1?.averageDailyScore7Day == e2?.averageDailyScore7Day &&
        e1?.averageDailyScore30Day == e2?.averageDailyScore30Day &&
        e1?.bestDailyScoreGain == e2?.bestDailyScoreGain &&
        e1?.worstDailyScoreGain == e2?.worstDailyScoreGain &&
        e1?.positiveDaysCount7Day == e2?.positiveDaysCount7Day &&
        e1?.positiveDaysCount30Day == e2?.positiveDaysCount30Day &&
        e1?.scoreGrowthRate7Day == e2?.scoreGrowthRate7Day &&
        e1?.scoreGrowthRate30Day == e2?.scoreGrowthRate30Day &&
        e1?.averageCumulativeScore7Day == e2?.averageCumulativeScore7Day &&
        e1?.averageCumulativeScore30Day == e2?.averageCumulativeScore30Day &&
        e1?.lastAggregateStatsCalculationDate == e2?.lastAggregateStatsCalculationDate;
  }

  @override
  int hash(UserProgressStatsRecord? e) => const ListEquality().hash([
        e?.userId,
        e?.cumulativeScore,
        e?.lastCalculationDate,
        e?.historicalHighScore,
        e?.totalDaysTracked,
        e?.currentStreak,
        e?.longestStreak,
        e?.lastDailyGain,
        e?.consecutiveLowDays,
        e?.achievedMilestones,
        e?.createdAt,
        e?.lastUpdatedAt,
        e?.averageDailyScore7Day,
        e?.averageDailyScore30Day,
        e?.bestDailyScoreGain,
        e?.worstDailyScoreGain,
        e?.positiveDaysCount7Day,
        e?.positiveDaysCount30Day,
        e?.scoreGrowthRate7Day,
        e?.scoreGrowthRate30Day,
        e?.averageCumulativeScore7Day,
        e?.averageCumulativeScore30Day,
        e?.lastAggregateStatsCalculationDate,
      ]);
}
