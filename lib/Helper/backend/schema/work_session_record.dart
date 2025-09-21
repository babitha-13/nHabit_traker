import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class WorkSessionRecord extends FirestoreRecord {
  WorkSessionRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  String? _type; // 'habit' | 'task'
  String get type => _type ?? 'habit';
  bool hasType() => _type != null;

  String? _refId; // id of habit or task
  String get refId => _refId ?? '';
  bool hasRefId() => _refId != null;

  DateTime? _startTime;
  DateTime? get startTime => _startTime;
  bool hasStartTime() => _startTime != null;

  DateTime? _endTime;
  DateTime? get endTime => _endTime;
  bool hasEndTime() => _endTime != null;

  int? _durationMs;
  int get durationMs => _durationMs ?? 0;
  bool hasDurationMs() => _durationMs != null;

  String? _note;
  String get note => _note ?? '';
  bool hasNote() => _note != null;

  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;

  void _initializeFields() {
    _uid = snapshotData['uid'] as String?;
    _type = snapshotData['type'] as String?;
    _refId = snapshotData['refId'] as String?;
    _startTime = snapshotData['startTime'] as DateTime?;
    _endTime = snapshotData['endTime'] as DateTime?;
    _durationMs = snapshotData['durationMs'] as int?;
    _note = snapshotData['note'] as String?;
    _userId = snapshotData['userId'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('sessions');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('sessions');

  static Stream<WorkSessionRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => WorkSessionRecord.fromSnapshot(s));

  static Future<WorkSessionRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => WorkSessionRecord.fromSnapshot(s));

  static WorkSessionRecord fromSnapshot(DocumentSnapshot snapshot) =>
      WorkSessionRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static WorkSessionRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      WorkSessionRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'WorkSessionRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is WorkSessionRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createWorkSessionRecordData({
  String? uid,
  String? type,
  String? refId,
  DateTime? startTime,
  DateTime? endTime,
  int? durationMs,
  String? note,
  String? userId,
}) {
  final firestoreData = mapToFirestore(<String, dynamic>{
    'uid': uid,
    'type': type,
    'refId': refId,
    'startTime': startTime,
    'endTime': endTime,
    'durationMs': durationMs,
    'note': note,
    'userId': userId,
  }.withoutNulls);

  return firestoreData;
}

class WorkSessionRecordDocumentEquality implements Equality<WorkSessionRecord> {
  const WorkSessionRecordDocumentEquality();

  @override
  bool equals(WorkSessionRecord? e1, WorkSessionRecord? e2) {
    return e1?.uid == e2?.uid &&
        e1?.type == e2?.type &&
        e1?.refId == e2?.refId &&
        e1?.startTime == e2?.startTime &&
        e1?.endTime == e2?.endTime &&
        e1?.durationMs == e2?.durationMs &&
        e1?.note == e2?.note &&
        e1?.userId == e2?.userId;
  }

  @override
  int hash(WorkSessionRecord? e) => const ListEquality().hash([
        e?.uid,
        e?.type,
        e?.refId,
        e?.startTime,
        e?.endTime,
        e?.durationMs,
        e?.note,
        e?.userId,
      ]);

  @override
  bool isValidKey(Object? o) => o is WorkSessionRecord;
}
