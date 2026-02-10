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
  // New field names (preferred)
  // "averageDailyGain7Day" field - 7-day average daily effective gain
  double? _averageDailyGain7Day;
  double get averageDailyGain7Day => _averageDailyGain7Day ?? 0.0;
  bool hasAverageDailyGain7Day() => _averageDailyGain7Day != null;

  // "averageDailyGain30Day" field - 30-day average daily effective gain
  double? _averageDailyGain30Day;
  double get averageDailyGain30Day => _averageDailyGain30Day ?? 0.0;
  bool hasAverageDailyGain30Day() => _averageDailyGain30Day != null;

  // "bestDailyGain" field - highest single day gain
  double? _bestDailyGain;
  double get bestDailyGain => _bestDailyGain ?? 0.0;
  bool hasBestDailyGain() => _bestDailyGain != null;

  // "worstDailyGain" field - lowest single day gain
  double? _worstDailyGain;
  double get worstDailyGain => _worstDailyGain ?? 0.0;
  bool hasWorstDailyGain() => _worstDailyGain != null;

  // Backward compatibility getters (deprecated, use new names)
  @Deprecated('Use averageDailyGain7Day instead')
  double get averageDailyScore7Day => _averageDailyGain7Day ?? _averageDailyScore7Day ?? 0.0;
  @Deprecated('Use averageDailyGain30Day instead')
  double get averageDailyScore30Day => _averageDailyGain30Day ?? _averageDailyScore30Day ?? 0.0;
  @Deprecated('Use bestDailyGain instead')
  double get bestDailyScoreGain => _bestDailyGain ?? _bestDailyScoreGain ?? 0.0;
  @Deprecated('Use worstDailyGain instead')
  double get worstDailyScoreGain => _worstDailyGain ?? _worstDailyScoreGain ?? 0.0;

  // Old field names (kept for backward compatibility during migration)
  double? _averageDailyScore7Day;
  double? _averageDailyScore30Day;
  double? _bestDailyScoreGain;
  double? _worstDailyScoreGain;

  // "positiveDaysCount7Day" field - count of positive days in last 7 days
  int? _positiveDaysCount7Day;
  int get positiveDaysCount7Day => _positiveDaysCount7Day ?? 0;
  bool hasPositiveDaysCount7Day() => _positiveDaysCount7Day != null;

  // "positiveDaysCount30Day" field - count of positive days in last 30 days
  int? _positiveDaysCount30Day;
  int get positiveDaysCount30Day => _positiveDaysCount30Day ?? 0;
  bool hasPositiveDaysCount30Day() => _positiveDaysCount30Day != null;

  // "averageCumulativeScore7Day" field - 7-day rolling average of cumulative score
  double? _averageCumulativeScore7Day;
  double get averageCumulativeScore7Day => _averageCumulativeScore7Day ?? 0.0;
  bool hasAverageCumulativeScore7Day() => _averageCumulativeScore7Day != null;

  // "averageCumulativeScore30Day" field - 30-day rolling average of cumulative score
  double? _averageCumulativeScore30Day;
  double get averageCumulativeScore30Day => _averageCumulativeScore30Day ?? 0.0;
  bool hasAverageCumulativeScore30Day() => _averageCumulativeScore30Day != null;

  // "lastProcessedDate" field - date when cloud function last processed day-end for this user
  DateTime? _lastProcessedDate;
  DateTime? get lastProcessedDate => _lastProcessedDate;
  bool hasLastProcessedDate() => _lastProcessedDate != null;

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
    // Read from new field names first, fallback to old names for backward compatibility
    _averageDailyGain7Day = 
      (snapshotData['averageDailyGain7Day'] as num?)?.toDouble() ??
      (snapshotData['averageDailyScore7Day'] as num?)?.toDouble();
    _averageDailyGain30Day = 
      (snapshotData['averageDailyGain30Day'] as num?)?.toDouble() ??
      (snapshotData['averageDailyScore30Day'] as num?)?.toDouble();
    _bestDailyGain = 
      (snapshotData['bestDailyGain'] as num?)?.toDouble() ??
      (snapshotData['bestDailyScoreGain'] as num?)?.toDouble();
    _worstDailyGain = 
      (snapshotData['worstDailyGain'] as num?)?.toDouble() ??
      (snapshotData['worstDailyScoreGain'] as num?)?.toDouble();
    
    // Keep old fields for backward compatibility
    _averageDailyScore7Day = (snapshotData['averageDailyScore7Day'] as num?)?.toDouble();
    _averageDailyScore30Day = (snapshotData['averageDailyScore30Day'] as num?)?.toDouble();
    _bestDailyScoreGain = (snapshotData['bestDailyScoreGain'] as num?)?.toDouble();
    _worstDailyScoreGain = (snapshotData['worstDailyScoreGain'] as num?)?.toDouble();
    
    _positiveDaysCount7Day = snapshotData['positiveDaysCount7Day'] as int?;
    _positiveDaysCount30Day = snapshotData['positiveDaysCount30Day'] as int?;
    _averageCumulativeScore7Day = (snapshotData['averageCumulativeScore7Day'] as num?)?.toDouble();
    _averageCumulativeScore30Day = (snapshotData['averageCumulativeScore30Day'] as num?)?.toDouble();
    _lastProcessedDate = snapshotData['lastProcessedDate'] as DateTime?;
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
  double? averageDailyGain7Day,
  double? averageDailyGain30Day,
  double? bestDailyGain,
  double? worstDailyGain,
  int? positiveDaysCount7Day,
  int? positiveDaysCount30Day,
  // Backward compatibility parameters
  double? averageDailyScore7Day,
  double? averageDailyScore30Day,
  double? bestDailyScoreGain,
  double? worstDailyScoreGain,
  double? averageCumulativeScore7Day,
  double? averageCumulativeScore30Day,
  DateTime? lastProcessedDate,
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
      'averageDailyGain7Day': averageDailyGain7Day ?? averageDailyScore7Day,
      'averageDailyGain30Day': averageDailyGain30Day ?? averageDailyScore30Day,
      'bestDailyGain': bestDailyGain ?? bestDailyScoreGain,
      'worstDailyGain': worstDailyGain ?? worstDailyScoreGain,
      'positiveDaysCount7Day': positiveDaysCount7Day,
      'positiveDaysCount30Day': positiveDaysCount30Day,
      // Also write old field names for backward compatibility during migration
      'averageDailyScore7Day': averageDailyGain7Day ?? averageDailyScore7Day,
      'averageDailyScore30Day': averageDailyGain30Day ?? averageDailyScore30Day,
      'bestDailyScoreGain': bestDailyGain ?? bestDailyScoreGain,
      'worstDailyScoreGain': worstDailyGain ?? worstDailyScoreGain,
      'averageCumulativeScore7Day': averageCumulativeScore7Day,
      'averageCumulativeScore30Day': averageCumulativeScore30Day,
      'lastProcessedDate': lastProcessedDate,
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
        e1?.averageDailyGain7Day == e2?.averageDailyGain7Day &&
        e1?.averageDailyGain30Day == e2?.averageDailyGain30Day &&
        e1?.bestDailyGain == e2?.bestDailyGain &&
        e1?.worstDailyGain == e2?.worstDailyGain &&
        e1?.positiveDaysCount7Day == e2?.positiveDaysCount7Day &&
        e1?.positiveDaysCount30Day == e2?.positiveDaysCount30Day &&
        e1?.averageCumulativeScore7Day == e2?.averageCumulativeScore7Day &&
        e1?.averageCumulativeScore30Day == e2?.averageCumulativeScore30Day &&
        e1?.lastProcessedDate == e2?.lastProcessedDate;
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
        e?.averageDailyGain7Day,
        e?.averageDailyGain30Day,
        e?.bestDailyGain,
        e?.worstDailyGain,
        e?.positiveDaysCount7Day,
        e?.positiveDaysCount30Day,
        e?.averageCumulativeScore7Day,
        e?.averageCumulativeScore30Day,
        e?.lastProcessedDate,
      ]);
}
