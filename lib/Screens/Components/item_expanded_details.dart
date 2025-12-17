import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class ItemExpandedDetails extends StatelessWidget {
  final ActivityInstanceRecord instance;
  final String? page;
  final String? subtitle;
  final bool isHabit;
  final bool isRecurring;
  final String frequencyDisplay;
  final bool? hasReminders;
  final String? reminderDisplayText;
  final VoidCallback? onEdit;

  const ItemExpandedDetails({
    Key? key,
    required this.instance,
    this.page,
    this.subtitle,
    required this.isHabit,
    required this.isRecurring,
    required this.frequencyDisplay,
    this.hasReminders,
    this.reminderDisplayText,
    this.onEdit,
  }) : super(key: key);

  bool _isQueuePageSubtitle(String subtitle) {
    // Check if subtitle contains category name pattern (common in queue page)
    final categoryName = instance.templateCategoryName;
    if (categoryName.isEmpty) return false;
    // Queue page subtitles often have category name with bullet separators or at start/end
    return subtitle.contains(' • $categoryName') ||
        subtitle.contains('$categoryName •') ||
        subtitle.startsWith('$categoryName ') ||
        subtitle == categoryName;
  }

  bool get _isNonProductive =>
      instance.templateCategoryType == 'non_productive';

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 2),
        child: Row(
          children: [
            // Show habit/task icon in expanded view
            if (!_isNonProductive) ...[
              Icon(
                isHabit ? Icons.flag : Icons.assignment,
                size: 12,
                color: theme.secondaryText.withOpacity(0.7),
              ),
              const SizedBox(width: 4),
            ],
            // Show category name (for queue page)
            if ((page == 'queue' || _isQueuePageSubtitle(subtitle ?? '')) &&
                instance.templateCategoryName.isNotEmpty) ...[
              Text(
                instance.templateCategoryName,
                style: theme.bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: theme.primaryText.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              // Add bullet separator if there's frequency or "one time" text to follow
              if (!_isNonProductive &&
                  ((isRecurring && frequencyDisplay.isNotEmpty) ||
                      (!isRecurring))) ...[
                Text(
                  '•',
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.primaryText.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ],
            // Show frequency if recurring, or "one time" if not recurring
            if (!_isNonProductive) ...[
              if (isRecurring && frequencyDisplay.isNotEmpty) ...[
                Text(
                  frequencyDisplay,
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.primaryText.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ] else if (isRecurring) ...[
                // Just show recurring indicator if no frequency text
                Icon(
                  Icons.repeat,
                  size: 12,
                  color: theme.secondaryText.withOpacity(0.7),
                ),
              ] else ...[
                // Show "one time" for non-recurring tasks
                Text(
                  'one time',
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.primaryText.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
            // Show reminder icon and times if reminders are configured
            if (hasReminders == true) ...[
              const SizedBox(width: 4),
              Text(
                '•',
                style: theme.bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: theme.primaryText.withOpacity(0.7),
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.notifications_active,
                size: 12,
                color: theme.secondaryText.withOpacity(0.7),
              ),
              if (reminderDisplayText != null &&
                  reminderDisplayText!.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(
                  reminderDisplayText!,
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.primaryText.withOpacity(0.7),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
