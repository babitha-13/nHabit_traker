import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/util/firestore_util.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

class TaskRecord extends FirestoreRecord {
  TaskRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // Fields
  String? _name;
  String get name => _name ?? '';
  bool hasTitle() => _name != null;

  String? _status; // todo | doing | done
  String get status => _status ?? 'incomplete';
  bool hasStatus() => _status != null;

  DateTime? _dueDate;
  DateTime? get dueDate => _dueDate;
  bool hasDueDate() => _dueDate != null;

  int? _priority; // 0 = none/low
  int get priority => _priority ?? 0;
  bool hasPriority() => _priority != null;

  // Manual order for drag & drop
  int? _manualOrder;
  int get manualOrder => _manualOrder ?? 0;
  bool hasManualOrder() => _manualOrder != null;

  bool? _isActive;
  bool get isActive => _isActive ?? true;
  bool hasIsActive() => _isActive != null;

  DateTime? _createdTime;
  DateTime? get createdTime => _createdTime;
  bool hasCreatedTime() => _createdTime != null;

  DateTime? _completedTime;
  DateTime? get completedTime => _completedTime;
  bool hasCompletedTime() => _completedTime != null;

  String? _categoryId;
  String get categoryId => _categoryId ?? '';
  bool hasCategoryId() => _categoryId != null;

  String? _categoryName;
  String get categoryName => _categoryName ?? '';
  bool hasCategoryName() => _categoryName != null;

  String? _habitId; // optional link to a habit
  String get habitId => _habitId ?? '';
  bool hasHabitId() => _habitId != null;

  void _initializeFields() {
    _name = snapshotData['title'] as String?;
    _status = snapshotData['status'] as String?;
    _dueDate = snapshotData['dueDate'] as DateTime?;
    _priority = snapshotData['priority'] as int?;
    _isActive = snapshotData['isActive'] as bool?;
    _createdTime = snapshotData['createdTime'] as DateTime?;
    _completedTime = snapshotData['completedTime'] as DateTime?;
    _categoryId = snapshotData['categoryId'] as String?;
    _categoryName = snapshotData['categoryName'] as String?;
    _habitId = snapshotData['habitId'] as String?;
    _manualOrder = snapshotData['manualOrder'] as int?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('tasks');

  static CollectionReference collectionForUser(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('tasks');

  static Stream<TaskRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => TaskRecord.fromSnapshot(s));

  static Future<TaskRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => TaskRecord.fromSnapshot(s));

  static TaskRecord fromSnapshot(DocumentSnapshot snapshot) => TaskRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static TaskRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      TaskRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'TaskRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is TaskRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createTaskRecordData({
  String? title,
  String? description,
  String? status,
  DateTime? dueDate,
  int? priority,
  int? manualOrder,
  bool? isActive,
  DateTime? createdTime,
  DateTime? completedTime,
  String? categoryId,
  String? categoryName,
  String? habitId,
}) {
  final firestoreData = mapToFirestore(<String, dynamic>{
    'title': title,
    'description': description,
    'status': status,
    'dueDate': dueDate,
    'priority': priority,
    'manualOrder': manualOrder,
    'isActive': isActive,
    'createdTime': createdTime,
    'completedTime': completedTime,
    'categoryId': categoryId,
    'categoryName': categoryName,
    'habitId': habitId,
  }.withoutNulls);

  return firestoreData;
}

class TaskRecordDocumentEquality implements Equality<TaskRecord> {
  const TaskRecordDocumentEquality();

  @override
  bool equals(TaskRecord? e1, TaskRecord? e2) {
    return e1?.name == e2?.name &&
        e1?.status == e2?.status &&
        e1?.dueDate == e2?.dueDate &&
        e1?.priority == e2?.priority &&
        e1?.isActive == e2?.isActive &&
        e1?.createdTime == e2?.createdTime &&
        e1?.completedTime == e2?.completedTime &&
        e1?.categoryId == e2?.categoryId &&
        e1?.categoryName == e2?.categoryName &&
        e1?.habitId == e2?.habitId;
  }

  @override
  int hash(TaskRecord? e) => const ListEquality().hash([
        e?.name,
        e?.status,
        e?.dueDate,
        e?.priority,
        e?.isActive,
        e?.createdTime,
        e?.completedTime,
        e?.categoryId,
        e?.categoryName,
        e?.habitId,
      ]);

  @override
  bool isValidKey(Object? o) => o is TaskRecord;
}
