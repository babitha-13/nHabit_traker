import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/backend/schema/util/schema_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class SequenceRecord extends FirestoreRecord {
  SequenceRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "uid" field.
  String? _uid;
  String get uid => _uid ?? '';
  bool hasUid() => _uid != null;

  // "name" field.
  String? _name;
  String get name => _name ?? '';
  bool hasName() => _name != null;

  // "description" field.
  String? _description;
  String get description => _description ?? '';
  bool hasDescription() => _description != null;

  // "habitIds" field.
  List<String>? _habitIds;
  List<String> get habitIds => _habitIds ?? [];
  bool hasHabitIds() => _habitIds != null;

  // "habitNames" field.
  List<String>? _habitNames;
  List<String> get habitNames => _habitNames ?? [];
  bool hasHabitNames() => _habitNames != null;

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
    _uid = snapshotData['uid'] as String?;
    _name = snapshotData['name'] as String?;
    _description = snapshotData['description'] as String?;
    _habitIds = getDataList(snapshotData['habitIds']);
    _habitNames = getDataList(snapshotData['habitNames']);
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _lastUpdated = snapshotData['lastUpdated'] as DateTime?;
    _userId = snapshotData['userId'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('sequences');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('sequences');

  static Stream<SequenceRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => SequenceRecord.fromSnapshot(s));

  static Future<SequenceRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => SequenceRecord.fromSnapshot(s));

  static SequenceRecord fromSnapshot(DocumentSnapshot snapshot) =>
      SequenceRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static SequenceRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      SequenceRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'SequenceRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is SequenceRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createSequenceRecordData({
  String? uid,
  String? name,
  String? description,
  List<String>? habitIds,
  List<String>? habitNames,
  bool? isActive,
  DateTime? createdTime,
  DateTime? lastUpdated,
  String? userId,
}) {
  final firestoreData = mapToFirestore(
    <String, dynamic>{
      'uid': uid,
      'name': name,
      'description': description,
      'habitIds': habitIds,
      'habitNames': habitNames,
      'isActive': isActive,
      'createdTime': createdTime,
      'lastUpdated': lastUpdated,
      'userId': userId,
    }.withoutNulls,
  );

  return firestoreData;
}

class SequenceRecordDocumentEquality implements Equality<SequenceRecord> {
  const SequenceRecordDocumentEquality();

  @override
  bool equals(SequenceRecord? e1, SequenceRecord? e2) {
    return e1?.uid == e2?.uid &&
        e1?.name == e2?.name &&
        e1?.description == e2?.description &&
        listEquals(e1?.habitIds, e2?.habitIds) &&
        listEquals(e1?.habitNames, e2?.habitNames) &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.lastUpdated == e2?.lastUpdated &&
        e1?.userId == e2?.userId;
  }

  @override
  int hash(SequenceRecord? e) => const ListEquality().hash([
        e?.uid,
        e?.name,
        e?.description,
        e?.habitIds,
        e?.habitNames,
        e?.isActive,
        e?.createdTime,
        e?.lastUpdated,
        e?.userId,
      ]);

  @override
  bool isValidKey(Object? o) => o is SequenceRecord;
}
