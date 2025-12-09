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

  // "createdAt" field
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "lastUpdatedAt" field
  DateTime? _lastUpdatedAt;
  DateTime? get lastUpdatedAt => _lastUpdatedAt;
  bool hasLastUpdatedAt() => _lastUpdatedAt != null;

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
    _createdAt = snapshotData['createdAt'] as DateTime?;
    _lastUpdatedAt = snapshotData['lastUpdatedAt'] as DateTime?;
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
  DateTime? createdAt,
  DateTime? lastUpdatedAt,
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
      'createdAt': createdAt,
      'lastUpdatedAt': lastUpdatedAt,
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
        e1?.createdAt == e2?.createdAt &&
        e1?.lastUpdatedAt == e2?.lastUpdatedAt;
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
        e?.createdAt,
        e?.lastUpdatedAt,
      ]);
}
