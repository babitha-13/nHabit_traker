import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'schema/timer_log_record.dart';
class TimerService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static Future<DocumentReference?> startTimer(
      {String? taskTitle, String? categoryColor}) async {
    final currentUserRef = currentUserReference;
    if (currentUserRef == null) {
      return null;
    }
    final timerLogData = createTimerLogRecordData(
      userId: currentUserRef.id,
      startTime: DateTime.now(),
      taskTitle: taskTitle,
      categoryColor: categoryColor,
    );
    final docRef = await _firestore.collection('timer_logs').add(timerLogData);
    return docRef;
  }
  static Future<void> pauseTimer(
      DocumentReference timerLogRef, Duration duration) async {
    final timerLogUpdateData = createTimerLogRecordData(
      pauseTime: DateTime.now(),
      durationSeconds: duration.inSeconds,
    );
    await timerLogRef.update(timerLogUpdateData);
  }
  static Future<List<TimerLogRecord>> getTimerLogsForCurrentUser() async {
    final currentUserRef = currentUserReference;
    if (currentUserRef == null) {
      return [];
    }
    final querySnapshot = await _firestore
        .collection('timer_logs')
        .where('user_id', isEqualTo: currentUserRef.id)
        .get();
    return querySnapshot.docs
        .map((doc) => TimerLogRecord.fromSnapshot(doc))
        .toList();
  }
}
