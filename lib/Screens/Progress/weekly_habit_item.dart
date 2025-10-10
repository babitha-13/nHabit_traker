import 'package:flutter/material.dart';
// import 'package:go_router/go_router.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/utils/neumorphic_container.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/createHabit/create_habit.dart';

class WeeklyHabitItem extends StatefulWidget {
  final ActivityRecord habit;
  final Future<void> Function() onRefresh;
  final void Function(ActivityRecord deletedHabit)? onHabitDeleted;
  final String? categoryColorHex;

  const WeeklyHabitItem({
    Key? key,
    required this.habit,
    required this.onRefresh,
    this.onHabitDeleted,
    this.categoryColorHex,
  }) : super(key: key);

  @override
  State<WeeklyHabitItem> createState() => _WeeklyHabitItemState();
}

class _WeeklyHabitItemState extends State<WeeklyHabitItem>
    with SingleTickerProviderStateMixin {
  bool _isUpdating = false;
  late final AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..repeat();
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  Color? get _categoryTintColor {
    final hex = widget.categoryColorHex;
    if (hex == null || hex.isEmpty) return null;
    try {
      final base = Color(int.parse(hex.replaceFirst('#', '0xFF')));
      return base.withOpacity(0.06);
    } catch (_) {
      return null;
    }
  }

  // Calculate weekly targets and progress
  Map<String, dynamic> get _weeklyData {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));

    // Calculate weekly target based on habit schedule
    double weeklyTarget; // use minutes or hours depending on type
    final trackingType = widget.habit.trackingType;
    // base target for one occurrence (minutes for time, units for others)
    final dynamic targetDyn = HabitTrackingUtil.getTarget(widget.habit);
    final int baseTarget =
        (trackingType == 'time' || trackingType == 'quantitative')
            ? (targetDyn is num
                ? targetDyn.toInt()
                : int.tryParse(targetDyn?.toString() ?? '0') ?? 0)
            : 0; // not used for binary
    if (widget.habit.schedule == 'daily') {
      // Daily habits: 7 times per week
      weeklyTarget = trackingType == 'binary' ? 7 : baseTarget * 7.0;
    } else if (widget.habit.schedule == 'weekly') {
      // Weekly habits: use the weeklyTarget or specific days count
      if (widget.habit.specificDays.isNotEmpty) {
        weeklyTarget = trackingType == 'binary'
            ? widget.habit.specificDays.length.toDouble()
            : baseTarget * widget.habit.specificDays.length.toDouble();
      } else {
        weeklyTarget = trackingType == 'binary'
            ? (widget.habit.frequency ?? 1).toDouble()
            : baseTarget * (widget.habit.frequency ?? 1).toDouble();
      }
    } else {
      // Monthly habits: approximate to weekly
      weeklyTarget = trackingType == 'binary'
          ? ((widget.habit.frequency ?? 1) * 7 / 30)
          : (baseTarget * (widget.habit.frequency ?? 1) * 7 / 30);
    }

    // Calculate weekly progress
    double weeklyProgress = 0;

    if (trackingType == 'binary') {
      // Count completed days this week
      // Note: completedDates tracking moved to separate completion records
      final completedDates = <DateTime>[];
      final count = completedDates.where((date) {
        return date.isAfter(startOfWeek.subtract(Duration(days: 1))) &&
            date.isBefore(now.add(Duration(days: 1)));
      }).length;
      weeklyProgress = count.toDouble();
    } else if (widget.habit.trackingType == 'quantitative') {
      // Sum up daily progress for this week
      // For now, we'll use current progress as a placeholder
      // In a real implementation, we'd track daily progress history
      weeklyProgress =
          (HabitTrackingUtil.getCurrentProgress(widget.habit) as num?)
                  ?.toDouble() ??
              0.0;
    } else if (widget.habit.trackingType == 'time') {
      // Progress and target should be in hours for weekly view
      // Compute current total milliseconds including running time
      int totalMs = widget.habit.accumulatedTime;
      if (widget.habit.isTimerActive && widget.habit.timerStartTime != null) {
        totalMs += DateTime.now()
            .difference(widget.habit.timerStartTime!)
            .inMilliseconds;
      }
      final progressHours = totalMs / 1000 / 60 / 60; // ms -> hours
      final targetHours =
          weeklyTarget / 60.0; // baseTarget minutes -> hours weekly
      return {
        'target': targetHours,
        'progress': progressHours,
        'unit': 'hr',
      };
    }

    return {
      'target': weeklyTarget,
      'progress': weeklyProgress,
      'unit': trackingType == 'time'
          ? 'hr'
          : (widget.habit.unit.isNotEmpty ? widget.habit.unit : 'times'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final weeklyData = _weeklyData;
    final double progress = (weeklyData['progress'] as num).toDouble();
    final double target = (weeklyData['target'] as num).toDouble();
    final unit = weeklyData['unit'] as String;
    final progressPercentage =
        target > 0 ? (progress / target).clamp(0.0, 1.0) : 0.0;

    return GestureDetector(
      onLongPressStart: (details) async {
        final overlay =
            Overlay.of(context).context.findRenderObject() as RenderBox;
        final tapPosition = details.globalPosition;
        final selected = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            tapPosition.dx,
            tapPosition.dy,
            overlay.size.width - tapPosition.dx,
            overlay.size.height - tapPosition.dy,
          ),
          items: [
            const PopupMenuItem<String>(
              value: 'edit',
              child: ListTile(leading: Icon(Icons.edit), title: Text('Edit')),
            ),
            const PopupMenuItem<String>(
              value: 'copy',
              child:
                  ListTile(leading: Icon(Icons.copy), title: Text('Duplicate')),
            ),
            PopupMenuItem<String>(
              value: 'delete',
              child: ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('Delete'),
                textColor: FlutterFlowTheme.of(context).error,
                iconColor: FlutterFlowTheme.of(context).error,
              ),
            ),
          ],
        );
        if (selected == 'edit') {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) =>
                  createActivityPage(habitToEdit: widget.habit),
            ),
          );
        } else if (selected == 'copy') {
          await _copyHabitWeekly();
        } else if (selected == 'delete') {
          final shouldDelete = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Delete Habit'),
              content:
                  Text('Delete "${widget.habit.name}"? This cannot be undone.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: TextButton.styleFrom(
                    foregroundColor: FlutterFlowTheme.of(context).error,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            ),
          );
          if (shouldDelete == true) {
            try {
              await deleteHabit(widget.habit.reference);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Habit deleted')),
                );
              }
              widget.onHabitDeleted?.call(widget.habit);
              await widget.onRefresh();
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error deleting habit: $e')),
                );
              }
            }
          }
        }
      },
      child: NeumorphicContainer(
        compact: true,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Stack(
          children: [
            if (_categoryTintColor != null)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: _categoryTintColor,
                  ),
                ),
              ),
            SizedBox(
              height: 36,
              child: Stack(
                children: [
                  // Title
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.habit.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FlutterFlowTheme.of(context).titleSmall.override(
                            fontFamily: 'Readex Pro',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                    ),
                  ),

                  // Right-side controls or compact badge
                  if (widget.habit.trackingType == 'binary')
                    Align(
                      alignment: Alignment.centerRight,
                      child: _buildBinaryWeeklyControl(
                          progress.toInt(), target.toInt()),
                    )
                  else
                    Positioned(
                      right: 0,
                      top: 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color:
                              FlutterFlowTheme.of(context).secondaryBackground,
                          border: Border.all(
                              color: FlutterFlowTheme.of(context).alternate,
                              width: 1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          () {
                            if (unit == 'hr') {
                              return '${progress.toStringAsFixed(1)}/${target.toStringAsFixed(1)}h';
                            }
                            final pct = target > 0
                                ? ((progress / target) * 100).round()
                                : 0;
                            return '$pct%';
                          }(),
                          style:
                              FlutterFlowTheme.of(context).bodySmall.override(
                                    fontFamily: 'Readex Pro',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                    ),

                  // Underline-style progress with optional shimmer
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                        color: FlutterFlowTheme.of(context).alternate,
                        borderRadius: BorderRadius.circular(2),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: progressPercentage,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: _getImpactLevelColor(),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            if (widget.habit.trackingType == 'time' &&
                                widget.habit.isTimerActive)
                              Align(
                                alignment: Alignment(
                                    -1 + 2 * _shimmerController.value, 0),
                                child: FractionallySizedBox(
                                  widthFactor: 0.25,
                                  heightFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.centerLeft,
                                        end: Alignment.centerRight,
                                        colors: [
                                          Colors.white.withOpacity(0.0),
                                          Colors.white.withOpacity(0.35),
                                          Colors.white.withOpacity(0.0),
                                        ],
                                        stops: const [0.0, 0.5, 1.0],
                                      ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyHabitWeekly() async {
    try {
      await createActivity(
        name: widget.habit.name,
        categoryName: widget.habit.categoryName.isNotEmpty
            ? widget.habit.categoryName
            : 'default',
        trackingType: widget.habit.trackingType,
        target: widget.habit.target,
        schedule: widget.habit.schedule,
        frequency: widget.habit.frequency ?? 1,
        description: widget.habit.description.isNotEmpty
            ? widget.habit.description
            : null,
        categoryType: widget.habit.categoryType,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit duplicated')),
        );
      }
      await widget.onRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying habit: $e')),
        );
      }
    }
  }

  Widget _buildBinaryWeeklyControl(int progress, int target) {
    return Checkbox(
      value: progress < target ? false : true,
      onChanged: _isUpdating
          ? null
          : (value) async {
              setState(() {
                _isUpdating = true;
              });

              try {
                if (value == true) {
                  await HabitTrackingUtil.markCompleted(widget.habit);
                } else {
                  // Remove today's completion
                  final today = DateTime.now();
                  final todayDate =
                      DateTime(today.year, today.month, today.day);
                  // Note: completedDates tracking moved to separate completion records
                  final completedDates = <DateTime>[];
                  completedDates.removeWhere((date) =>
                      date.year == todayDate.year &&
                      date.month == todayDate.month &&
                      date.day == todayDate.day);

                  await widget.habit.reference.update({
                    'completedDates': completedDates,
                    'lastUpdated': DateTime.now(),
                  });
                }
                widget.onRefresh();
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating habit: $e')),
                );
              } finally {
                setState(() {
                  _isUpdating = false;
                });
              }
            },
      activeColor: _getImpactLevelColor(),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  // Removed old quantitative weekly controls; compact badge is used instead

  Color _getImpactLevelColor() {
    final theme = FlutterFlowTheme.of(context);
    switch (widget.habit.priority) {
      case 1:
        return theme.accent3; // cool neutral
      case 2:
        return theme.secondary; // slate grey
      case 3:
        return theme.primary; // high priority
      default:
        return theme.secondary;
    }
  }
}
