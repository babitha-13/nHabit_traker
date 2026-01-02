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
  final bool showCategoryOnExpansion;
  final VoidCallback? onEdit;
  final int? timeEstimateMinutes;

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
    this.showCategoryOnExpansion = false,
    this.onEdit,
    this.timeEstimateMinutes,
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

  bool get _isessential => instance.templateCategoryType == 'essential';

  String? get _timeEstimateDisplay {
    final minutes = timeEstimateMinutes ?? instance.templateTimeEstimateMinutes;
    if (minutes == null || minutes <= 0) return null;
    if (minutes < 60) {
      return '$minutes min est';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    final hourLabel = hours == 1 ? 'hr' : 'hrs';
    if (remainingMinutes == 0) {
      return '$hours $hourLabel est';
    }
    return '$hours $hourLabel $remainingMinutes min est';
  }

  Widget _buildSeparator(FlutterFlowTheme theme) {
    return Text(
      '•',
      style: theme.bodySmall.override(
        fontFamily: 'Readex Pro',
        color: theme.primaryText.withOpacity(0.7),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildCategoryChip(FlutterFlowTheme theme) {
    return Text(
      instance.templateCategoryName,
      style: theme.bodySmall.override(
        fontFamily: 'Readex Pro',
        color: theme.primaryText.withOpacity(0.7),
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _buildFrequencyChip(FlutterFlowTheme theme) {
    final textStyle = theme.bodySmall.override(
      fontFamily: 'Readex Pro',
      color: theme.primaryText.withOpacity(0.7),
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    if (isRecurring && frequencyDisplay.isNotEmpty) {
      return Text(frequencyDisplay, style: textStyle);
    }
    if (isRecurring) {
      return Icon(
        Icons.repeat,
        size: 12,
        color: theme.secondaryText.withOpacity(0.7),
      );
    }
    return Text('one time', style: textStyle);
  }

  Widget _buildTimeEstimateChip(FlutterFlowTheme theme, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.timelapse,
          size: 12,
          color: theme.secondaryText.withOpacity(0.7),
        ),
        const SizedBox(width: 2),
        Text(
          text,
          style: theme.bodySmall.override(
            fontFamily: 'Readex Pro',
            color: theme.primaryText.withOpacity(0.7),
            fontSize: 13,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildReminderChip(FlutterFlowTheme theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.notifications_active,
          size: 12,
          color: theme.secondaryText.withOpacity(0.7),
        ),
        if (reminderDisplayText != null && reminderDisplayText!.isNotEmpty) ...[
          const SizedBox(width: 2),
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
    );
  }

  List<Widget> _buildInfoChips(FlutterFlowTheme theme, String? timeEstimate) {
    final chips = <Widget>[];
    void addChip(Widget chip) {
      if (chips.isNotEmpty) {
        chips.add(_buildSeparator(theme));
      }
      chips.add(chip);
    }

    final showCategory = (page == 'queue' ||
            _isQueuePageSubtitle(subtitle ?? '') ||
            showCategoryOnExpansion) &&
        instance.templateCategoryName.isNotEmpty;

    if (showCategory) {
      addChip(_buildCategoryChip(theme));
    }
    if (!_isessential) {
      addChip(_buildFrequencyChip(theme));
    }
    if (timeEstimate != null) {
      addChip(_buildTimeEstimateChip(theme, timeEstimate));
    }
    if (hasReminders == true) {
      addChip(_buildReminderChip(theme));
    }

    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final timeEstimateDisplay = _timeEstimateDisplay;

    return InkWell(
      onTap: onEdit,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 0, horizontal: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (!_isessential) ...[
              Icon(
                isHabit ? Icons.flag : Icons.assignment,
                size: 12,
                color: theme.secondaryText.withOpacity(0.7),
              ),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: _buildInfoChips(theme, timeEstimateDisplay),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
