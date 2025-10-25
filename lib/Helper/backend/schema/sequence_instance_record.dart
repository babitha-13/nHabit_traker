import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
class SequenceInstanceRecord extends FirestoreRecord {
  SequenceInstanceRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }
  // "sequenceId" field - reference to sequence template.
  String? _sequenceId;
  String get sequenceId => _sequenceId ?? '';
  bool hasSequenceId() => _sequenceId != null;
  // "date" field - which day this instance is for.
  DateTime? _date;
  DateTime? get date => _date;
  bool hasDate() => _date != null;
  // "itemInstanceIds" field - map of activity ID to instance ID for that day.
  Map<String, String>? _itemInstanceIds;
  Map<String, String> get itemInstanceIds => _itemInstanceIds ?? {};
  bool hasItemInstanceIds() => _itemInstanceIds != null;
  // "status" field - overall sequence status.
  String? _status;
  String get status => _status ?? 'pending';
  bool hasStatus() => _status != null;
  // "startedAt" field - when sequence was started.
  DateTime? _startedAt;
  DateTime? get startedAt => _startedAt;
  bool hasStartedAt() => _startedAt != null;
  // "completedAt" field - when sequence was completed.
  DateTime? _completedAt;
  DateTime? get completedAt => _completedAt;
  bool hasCompletedAt() => _completedAt != null;
  // "isActive" field.
  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;
  // "createdTime" field.
  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;
  // "lastUpdated" field.
  DateTime? _lastUpdated;
  DateTime? get lastUpdated => _lastUpdated;
  bool hasLastUpdated() => _lastUpdated != null;
  // "userId" field.
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;
  void _initializeFields() {
    _sequenceId = snapshotData['sequenceId'] as String?;
    _date = snapshotData['date'] as DateTime?;
    _itemInstanceIds =
        (snapshotData['itemInstanceIds'] as Map<String, dynamic>?)
            ?.cast<String, String>();
    _status = snapshotData['status'] as String?;
    _startedAt = snapshotData['startedAt'] as DateTime?;
    _completedAt = snapshotData['completedAt'] as DateTime?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _userId = snapshotData['userId'] as String?;
  }
  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('sequence_instances');
  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('sequence_instances');
  static Stream<SequenceInstanceRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => SequenceInstanceRecord.fromSnapshot(s));
  static Future<SequenceInstanceRecord> getDocumentOnce(
          DocumentReference ref) =>
      ref.get().then((s) => SequenceInstanceRecord.fromSnapshot(s));
  static SequenceInstanceRecord fromSnapshot(DocumentSnapshot snapshot) =>
      SequenceInstanceRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );
  static SequenceInstanceRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      SequenceInstanceRecord._(reference, mapFromFirestore(data));
  @override
  String toString() =>
      'SequenceInstanceRecord(reference: ${reference.path}, data: $snapshotData)';
  @override
  int get hashCode => reference.path.hashCode;
  @override
  bool operator ==(other) =>
      other is SequenceInstanceRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}
Map<String, dynamic> createSequenceInstanceRecordData({
  String? sequenceId,
  DateTime? date,
  Map<String, String>? itemInstanceIds,
  String? status,
  DateTime? startedAt,
  DateTime? completedAt,
  bool? isActive,
  DateTime? createdTime,
  DateTime? lastUpdated,
  String? userId,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'sequenceId': sequenceId,
      'date': date,
      'itemInstanceIds': itemInstanceIds,
      'status': status,
      'startedAt': startedAt,
      'completedAt': completedAt,
      'isActive': isActive,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'userId': userId,
    }.withoutNulls,
  );
  return firestoreData;
}
class SequenceInstanceRecordDocumentEquality
    implements Equality<SequenceInstanceRecord> {
  const SequenceInstanceRecordDocumentEquality();
  @override
  bool equals(SequenceInstanceRecord? e1, SequenceInstanceRecord? e2) {
    return e1?.sequenceId == e2?.sequenceId &&
        e1?.date == e2?.date &&
        mapEquals(e1?.itemInstanceIds, e2?.itemInstanceIds) &&
        e1?.status == e2?.status &&
        e1?.startedAt == e2?.startedAt &&
        e1?.completedAt == e2?.completedAt &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.userId == e2?.userId;
  }
  @override
  int hash(SequenceInstanceRecord? e) => const ListEquality().hash([
        e?.sequenceId,
        e?.date,
        e?.itemInstanceIds,
        e?.status,
        e?.startedAt,
        e?.completedAt,
        e?.isActive,
        e?.createdTime,
        e?.lastUpdated,
        e?.userId,
      ]);
  @override
  bool isValidKey(Object? o) => o is SequenceInstanceRecord;
}
