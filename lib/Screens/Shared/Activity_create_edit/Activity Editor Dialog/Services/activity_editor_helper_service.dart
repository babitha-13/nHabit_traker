import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Activity%20Editor%20Dialog/activity_editor_dialog.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/Frequency_config/frequency_config_dialog.dart';

/// Helper service for activity editor shared utilities
class ActivityEditorHelperService {
  static const String createNewCategoryValue = 'CREATE_NEW_CATEGORY_SPECIAL_VALUE';

  /// Check if this is an essential activity
  static bool isEssential(ActivityEditorDialogState state) {
    if (state.widget.isEssential != null) return state.widget.isEssential!;
    return state.widget.activity?.categoryType == 'essential';
  }

  /// Get the categories to use - prefer loaded categories, fallback to widget categories
  static List<CategoryRecord> getCategories(ActivityEditorDialogState state) {
    return state.loadedCategories.isNotEmpty ? state.loadedCategories : state.widget.categories;
  }

  /// Check if recurring
  static bool isRecurring(ActivityEditorDialogState state) {
    return state.quickIsTaskRecurring && state.frequencyConfig != null;
  }

  /// Get the valid category ID for the dropdown
  /// Returns null if no category is selected or if the selected category is invalid
  static String? getValidCategoryId(ActivityEditorDialogState state) {
    if (state.selectedCategoryId == null) return null;
    final categories = getCategories(state);
    final isValid = categories.any((c) => c.reference.id == state.selectedCategoryId);
    return isValid ? state.selectedCategoryId : null;
  }

  /// Check if the current activity is a time-target activity
  static bool isTimeTarget(ActivityEditorDialogState state) {
    return state.selectedTrackingType == 'time' &&
        state.targetDuration.inMinutes > 0;
  }

  /// List equality check helper
  static bool listEquals<T>(List<T>? a, List<T>? b) {
    if (a == null) return b == null;
    if (b == null || a.length != b.length) return false;
    for (int index = 0; index < a.length; index += 1) {
      if (a[index] != b[index]) return false;
    }
    return true;
  }
}
