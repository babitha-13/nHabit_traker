import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Centralized IST day-boundary utilities.
/// All day-end/catch-up scheduling should use this service.
class IstDayBoundaryService {
  static const String _istZoneName = 'Asia/Kolkata';
  static bool _initialized = false;
  static tz.Location? _istLocation;

  static void _ensureInitialized() {
    if (_initialized) return;
    tz_data.initializeTimeZones();
    _istLocation = tz.getLocation(_istZoneName);
    _initialized = true;
  }

  static tz.Location get _ist {
    _ensureInitialized();
    return _istLocation!;
  }

  /// Public IST location handle for advanced timezone operations.
  static tz.Location get istLocation => _ist;

  /// Current instant represented in IST.
  static tz.TZDateTime nowIst() {
    return tz.TZDateTime.now(_ist);
  }

  /// Convert any instant to IST timezone representation.
  static tz.TZDateTime toIst(DateTime instant) {
    return tz.TZDateTime.from(instant, _ist);
  }

  /// IST start-of-day for an arbitrary instant.
  static tz.TZDateTime startOfDayIst(DateTime instant) {
    final istInstant = toIst(instant);
    return tz.TZDateTime(
      _ist,
      istInstant.year,
      istInstant.month,
      istInstant.day,
    );
  }

  /// IST start-of-day for "today".
  static tz.TZDateTime todayStartIst() {
    final now = nowIst();
    return tz.TZDateTime(_ist, now.year, now.month, now.day);
  }

  /// IST start-of-day for "yesterday".
  static tz.TZDateTime yesterdayStartIst() {
    return todayStartIst().subtract(const Duration(days: 1));
  }

  /// Next 00:05 IST instant in absolute time.
  static tz.TZDateTime nextIst005() {
    final now = nowIst();
    var next = tz.TZDateTime(_ist, now.year, now.month, now.day, 0, 5);
    if (!now.isBefore(next)) {
      final tomorrow = now.add(const Duration(days: 1));
      next = tz.TZDateTime(
          _ist, tomorrow.year, tomorrow.month, tomorrow.day, 0, 5);
    }
    return next;
  }

  /// True when current IST time is >= 00:05 IST.
  static bool hasReachedIst005() {
    final now = nowIst();
    final threshold = tz.TZDateTime(_ist, now.year, now.month, now.day, 0, 5);
    return !now.isBefore(threshold);
  }

  /// Format any instant as `YYYY-MM-DD` in IST.
  static String formatDateKeyIst(DateTime instant) {
    final istInstant = tz.TZDateTime.from(instant, _ist);
    final year = istInstant.year;
    final month = istInstant.month.toString().padLeft(2, '0');
    final day = istInstant.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
