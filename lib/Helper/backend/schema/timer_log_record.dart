import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';

import 'util/firestore_util.dart';

class TimerLogRecord extends FirestoreRecord {
  TimerLogRecord._(
    super.reference,
    super.data,
  ) {
    _initializeFields();
  }

  // "user_id" field.
  String? _userId;
  String get userId => _userId ?? '';
  bool hasUserId() => _userId != null;

  // "start_time" field.
  DateTime? _startTime;
  DateTime? get startTime => _startTime;
  bool hasStartTime() => _startTime != null;

  // "pause_time" field.
  DateTime? _pauseTime;
  DateTime? get pauseTime => _pauseTime;
  bool hasPauseTime() => _pauseTime != null;

  // "task_title" field.
  String? _taskTitle;
  String get taskTitle => _taskTitle ?? '';
  bool hasTaskTitle() => _taskTitle != null;

  // "duration_seconds" field.
  int? _durationSeconds;
  int get durationSeconds => _durationSeconds ?? 0;
  bool hasDurationSeconds() => _durationSeconds != null;

  // "category_color" field.
  String? _categoryColor;
  String get categoryColor => _categoryColor ?? '#2196F3'; // Default blue
  bool hasCategoryColor() => _categoryColor != null;

  void _initializeFields() {
    _userId = snapshotData['user_id'] as String?;
    _startTime = snapshotData['start_time'] as DateTime?;
    _pauseTime = snapshotData['pause_time'] as DateTime?;
    _taskTitle = snapshotData['task_title'] as String?;
    _durationSeconds = snapshotData['duration_seconds'] as int?;
    _categoryColor = snapshotData['category_color'] as String?;
  }

  static CollectionReference get collection =>
      FirebaseFirestore.instance.collection('timer_logs');

  static Stream<TimerLogRecord> getDocument(DocumentReference ref) =>
      ref.snapshots().map((s) => TimerLogRecord.fromSnapshot(s));

  static Future<TimerLogRecord> getDocumentOnce(DocumentReference ref) =>
      ref.get().then((s) => TimerLogRecord.fromSnapshot(s));

  static TimerLogRecord fromSnapshot(DocumentSnapshot snapshot) =>
      TimerLogRecord._(
        snapshot.reference,
        mapFromFirestore(snapshot.data() as Map<String, dynamic>),
      );

  static TimerLogRecord getDocumentFromData(
    Map<String, dynamic> data,
    DocumentReference reference,
  ) =>
      TimerLogRecord._(reference, mapFromFirestore(data));

  @override
  String toString() =>
      'TimerLogRecord(reference: ${reference.path}, data: $snapshotData)';

  @override
  int get hashCode => reference.path.hashCode;

  @override
  bool operator ==(other) =>
      other is TimerLogRecord &&
      reference.path.hashCode == other.reference.path.hashCode;
}

Map<String, dynamic> createTimerLogRecordData({
  String? userId,
  DateTime? startTime,
  DateTime? pauseTime,
  String? taskTitle,
  int? durationSeconds,
  String? categoryColor,
}) {
  final firestoreData = mapToFirestore(<String, dynamic>{
    'user_id': userId,
    'start_time': startTime,
    'pause_time': pauseTime,
    'task_title': taskTitle,
    'duration_seconds': durationSeconds,
    'category_color': categoryColor,
  }.withoutNulls);

  return firestoreData;
}

class TimerLogRecordDocumentEquality implements Equality<TimerLogRecord> {
  const TimerLogRecordDocumentEquality();

  @override
  bool equals(TimerLogRecord? e1, TimerLogRecord? e2) {
    return e1?.userId == e2?.userId &&
        e1?.startTime == e2?.startTime &&
        e1?.pauseTime == e2?.pauseTime &&
        e1?.taskTitle == e2?.taskTitle &&
        e1?.durationSeconds == e2?.durationSeconds &&
        e1?.categoryColor == e2?.categoryColor;
  }

  @override
  int hash(TimerLogRecord? e) => const ListEquality().hash([
        e?.userId,
        e?.startTime,
        e?.pauseTime,
        e?.taskTitle,
        e?.durationSeconds,
        e?.categoryColor,
      ]);

  @override
  bool isValidKey(Object? o) => o is TimerLogRecord;
}
