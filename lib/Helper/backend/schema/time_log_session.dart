/// Model for individual time logging sessions
/// Represents a single work session with start/end times and duration
class TimeLogSession {
  final DateTime startTime;
  final DateTime? endTime;
  final int durationMilliseconds;
  const TimeLogSession({
    required this.startTime,
    this.endTime,
    required this.durationMilliseconds,
  });
  /// Create session from Firestore data
  static TimeLogSession fromMap(Map<String, dynamic> map) {
    return TimeLogSession(
      startTime: map['startTime'] as DateTime,
      endTime: map['endTime'] as DateTime?,
      durationMilliseconds: map['durationMilliseconds'] as int,
    );
  }
  /// Convert to Firestore format
  Map<String, dynamic> toMap() {
    return {
      'startTime': startTime,
      'endTime': endTime,
      'durationMilliseconds': durationMilliseconds,
    };
  }
  /// Get duration as Duration object
  Duration get duration => Duration(milliseconds: durationMilliseconds);
  /// Check if session is completed (has end time)
  bool get isCompleted => endTime != null;
  /// Get formatted duration string
  String get formattedDuration {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) {
      return '${hours}h ${minutes}m';
    }
    return '${minutes}m';
  }
  @override
  String toString() {
    return 'TimeLogSession(start: $startTime, end: $endTime, duration: $formattedDuration)';
  }
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TimeLogSession &&
        startTime == other.startTime &&
        endTime == other.endTime &&
        durationMilliseconds == other.durationMilliseconds;
  }
  @override
  int get hashCode {
    return startTime.hashCode ^
        endTime.hashCode ^
        durationMilliseconds.hashCode;
  }
}
