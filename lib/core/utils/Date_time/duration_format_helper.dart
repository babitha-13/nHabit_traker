/// Shared helpers for formatting durations and stopwatch-like times.
class DurationFormatHelper {
  /// Format a stopwatch-style duration from milliseconds.
  /// Examples: "1:23:45" (1 hour 23 min 45 sec), "5:30" (5 min 30 sec).
  static String formatStopwatch(int milliseconds) {
    final totalSeconds = milliseconds ~/ 1000;
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  /// Format a duration (milliseconds) as a compact minute label. Example: "125min".
  static String formatMinutesLabel(int milliseconds) {
    final totalMinutes = milliseconds ~/ 60000;
    return '${totalMinutes}min';
  }

  /// Format a Duration into human-readable hours/minutes. Example: "2h 5m".
  static String formatHuman(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    return hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';
  }
}
