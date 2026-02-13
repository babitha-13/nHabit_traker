import 'package:habit_tracker/core/utils/Date_time/ist_day_boundary_service.dart';

/// Format date as YYYY-MM-DD in IST.
/// Matches TypeScript `formatDateKeyIST` for consistent document IDs.
String formatDateKeyIST(DateTime date) {
  return IstDayBoundaryService.formatDateKeyIst(date);
}
