import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class GoalRecord extends FirestoreRecord {
  GoalRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "whatToAchieve" field.
  String? _whatToAchieve;
  String get whatToAchieve => _whatToAchieve ?? '';
  bool hasWhatToAchieve() => _whatToAchieve != null;

  // "byWhen" field.
  String? _byWhen;
  String get byWhen => _byWhen ?? '';
  bool hasByWhen() => _byWhen != null;

  // "why" field.
  String? _why;
  String get why => _why ?? '';
  bool hasWhy() => _why != null;

  // "how" field.
  String? _how;
  String get how => _how ?? '';
  bool hasHow() => _how != null;

  // "thingsToAvoid" field.
  String? _thingsToAvoid;
  String get thingsToAvoid => _thingsToAvoid ?? '';
  bool hasThingsToAvoid() => _thingsToAvoid != null;

  // "lastShownAt" field.
  DateTime? _lastShownAt;
  DateTime? get lastShownAt => _lastShownAt;
  bool hasLastShownAt() => _lastShownAt != null;

  // "createdAt" field.
  DateTime? _createdAt;
  DateTime? get createdAt => _createdAt;
  bool hasCreatedAt() => _createdAt != null;

  // "lastUpdated" field.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;

  // "isActive" field.
  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  void _initializeFields() {
    _whatToAchieve = snapshotData['whatToAchieve'] as String?;
    _byWhen = snapshotData['byWhen'] as String?;
    _why = snapshotData['why'] as String?;
    _how = snapshotData['how'] as String?;
    _thingsToAvoid = snapshotData['thingsToAvoid'] as String?;
    _lastShownAt = snapshotData['lastShownAt'] as DateTime?;
    _createdAt = snapshotData['createdAt'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _isActive = snapshotData['isActive'] as bool?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('goals');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('goals');

  static Stream<GoalRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => GoalRecord.fromSnapshot(s));

  static Future<GoalRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => GoalRecord.fromSnapshot(s));

  static GoalRecord fromSnapshot(DocumentSnapshot snapshot) => GoalRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static GoalRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      GoalRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'GoalRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is GoalRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createGoalRecordData({
  String? whatToAchieve,
  String? byWhen,
  String? why,
  String? how,
  String? thingsToAvoid,
  DateTime? lastShownAt,
  DateTime? createdAt,
  DateTime? lastUpdated,
  bool? isActive,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'whatToAchieve': whatToAchieve,
      'byWhen': byWhen,
      'why': why,
      'how': how,
      'thingsToAvoid': thingsToAvoid,
      'lastShownAt': lastShownAt,
      'createdAt': createdAt,
      'lastUpdated': lastUpdated,
      'isActive': isActive,
    }.withoutNulls,
  );

  return firestoreData;
}

class GoalRecordDocumentEquality implements Equality<GoalRecord> {
  const GoalRecordDocumentEquality();

  @override
  bool equals(GoalRecord? e1, GoalRecord? e2) {
    return e1?.whatToAchieve == e2?.whatToAchieve &&
        e1?.byWhen == e2?.byWhen &&
        e1?.why == e2?.why &&
        e1?.how == e2?.how &&
        e1?.thingsToAvoid == e2?.thingsToAvoid &&
        e1?.lastShownAt == e2?.lastShownAt &&
        e1?.createdAt == e2?.createdAt &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.isActive == e2?.isActive;
  }

  @override
  int hash(GoalRecord? e) => const ListEquality().hash([
        e?.whatToAchieve,
        e?.byWhen,
        e?.why,
        e?.how,
        e?.thingsToAvoid,
        e?.lastShownAt,
        e?.createdAt,
        e?.lastUpdated,
        e?.isActive,
      ]);

  @override
  bool isValidKey(Object? o) => o is GoalRecord;
}
