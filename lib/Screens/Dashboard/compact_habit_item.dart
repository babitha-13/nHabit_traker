import 'dart:async';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/habit_tracking_util.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/utils/TimeManager.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:habit_tracker/Screens/Create%20Task/create_task.dart';
import 'package:habit_tracker/Screens/CreateHabit/create_Habit.dart';

class CompactHabitItem extends StatefulWidget {
  final HabitRecord habit;
  final Future<void> Function()? onRefresh;
  final void Function(HabitRecord updatedHabit)? onHabitUpdated;
  final void Function(HabitRecord deletedHabit)? onHabitDeleted;
  final String? categoryColorHex;
  final bool? showCompleted;
  final bool showCalendar;
  final bool showTaskEdit;
  final List<CategoryRecord>? categories;
  final List<HabitRecord>? tasks;

  const CompactHabitItem(
      {Key? key,
      required this.habit,
      this.onRefresh,
      this.onHabitUpdated,
      this.onHabitDeleted,
      this.categoryColorHex,
      this.showCompleted,
      this.showCalendar = false,
      this.categories,
      this.tasks,
      this.showTaskEdit = false})
      : super(key: key);

  @override
  State<CompactHabitItem> createState() => _CompactHabitItemState();
}

class _CompactHabitItemState extends State<CompactHabitItem>
    with TickerProviderStateMixin {
  bool _isUpdating = false;
  Timer? _timer;
  int? _quantProgressOverride;
  bool? _timerStateOverride;

  @override
  void initState() {
    super.initState();
    if (widget.habit.trackingType == 'time' && widget.habit.isTimerActive) {
      _startTimer();
    }
  }

  @override
  void didUpdateWidget(covariant CompactHabitItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.habit.trackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      final num backend =
          HabitTrackingUtil.getCurrentProgress(widget.habit) ?? 0;
      if (backend.toInt() == _quantProgressOverride) {
        setState(() => _quantProgressOverride = null);
      }
    }
    if (widget.habit.trackingType == 'time' && _timerStateOverride != null) {
      if (widget.habit.isTimerActive == _timerStateOverride) {
        setState(() => _timerStateOverride = null);
      }
    }
  }

  Future<void> _copyHabit() async {
    try {
      await createHabit(
        name: widget.habit.name,
        categoryName: widget.habit.categoryName.isNotEmpty
            ? widget.habit.categoryName
            : 'default',
        trackingType: widget.habit.trackingType,
        target: widget.habit.target,
        schedule: widget.habit.schedule,
        frequency: widget.habit.frequency,
        description: widget.habit.description.isNotEmpty
            ? widget.habit.description
            : null,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit copied')),
        );
      }
      await widget.onRefresh?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error copying habit: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _timer?.cancel();
    final startTime = widget.habit.timerStartTime ?? DateTime.now();
    final target = HabitTrackingUtil.getTargetDuration(widget.habit);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (mounted) {
        setState(() {});
      }
      final elapsed = DateTime.now().difference(startTime);
      if (target > Duration.zero && elapsed >= target) {
        timer.cancel();
        setState(() => _timerStateOverride = false);
        await HabitTrackingUtil.stopTimer(widget.habit);
        final updated =
            await HabitRecord.getDocumentOnce(widget.habit.reference);
        if (mounted) {
          widget.onHabitUpdated?.call(updated);
        }
      }
    });
  }

  bool get _isCompleted {
    return HabitTrackingUtil.isCompletedToday(widget.habit);
  }

  Color get _impactLevelColor {
    final theme = FlutterFlowTheme.of(context);
    switch (widget.habit.priority) {
      case 1:
        return theme.accent3;
      case 2:
        return theme.secondary;
      case 3:
        return theme.primary;
      default:
        return theme.secondary;
    }
  }

  String _getTimerDisplayWithSeconds() {
    return HabitTrackingUtil.getTimerDisplayTextWithSeconds(widget.habit);
  }

  bool get _isTimerActiveLocal {
    if (widget.habit.trackingType == 'time' && _timerStateOverride != null) {
      return _timerStateOverride!;
    }
    return widget.habit.isTimerActive;
  }

  num _currentProgressLocal() {
    if (widget.habit.trackingType == 'quantitative' &&
        _quantProgressOverride != null) {
      return _quantProgressOverride!;
    }
    return HabitTrackingUtil.getCurrentProgress(widget.habit) ?? 0;
  }

  double get _progressPercentClamped {
    try {
      if (widget.habit.trackingType == 'quantitative') {
        final num progress = _currentProgressLocal();
        final num target = HabitTrackingUtil.getTarget(widget.habit) ?? 0;
        if (target == 0) return 0.0;
        final pct = (progress.toDouble() / target.toDouble());
        if (pct.isNaN) return 0.0;
        return pct.clamp(0.0, 1.0);
      }
      final pct = HabitTrackingUtil.getProgressPercentage(widget.habit);
      return pct.clamp(0.0, 1.0);
    } catch (_) {
      return 0.0;
    }
  }

  bool get _isFullyCompleted {
    switch (widget.habit.trackingType) {
      case 'quantitative':
        final progress = _currentProgressLocal();
        final target = HabitTrackingUtil.getTarget(widget.habit) ?? 0;
        return target > 0 && progress >= target;
      case 'binary':
        return HabitTrackingUtil.isCompletedToday(widget.habit);
      case 'time':
        final tracked = HabitTrackingUtil.getTrackedTime(widget.habit);
        final target = HabitTrackingUtil.getTargetDuration(widget.habit);
        return target > Duration.zero && tracked >= target;
      default:
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullyCompleted && (widget.showCompleted != true)) {
      return const SizedBox.shrink();
    }
    final double screenWidth = MediaQuery.of(context).size.width;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      decoration: BoxDecoration(
          gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
          border: Border(
            left: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            right: BorderSide(
                color: FlutterFlowTheme.of(context).surfaceBorderColor,
                width: 1),
            top: BorderSide.none,
          )),
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: screenWidth - 32),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
          decoration: BoxDecoration(
            gradient: FlutterFlowTheme.of(context).neumorphicGradientSubtle,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: FlutterFlowTheme.of(context).surfaceBorderColor,
              width: 0.5,
            ),
          ),
          child: Column(
            children: [
              IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      decoration: BoxDecoration(
                        color: _leftStripeColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 5),
                    SizedBox(
                      width: 36,
                      child: Center(child: _buildLeftControlsCompact()),
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.habit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: FlutterFlowTheme.of(context)
                                  .bodyMedium
                                  .override(
                                    fontFamily: 'Readex Pro',
                                    fontWeight: FontWeight.w600,
                                    decoration: _isCompleted
                                        ? TextDecoration.lineThrough
                                        : TextDecoration.none,
                                    color: _isCompleted
                                        ? FlutterFlowTheme.of(context)
                                            .secondaryText
                                        : FlutterFlowTheme.of(context)
                                            .primaryText,
                                  ),
                            ),
                          ),
                          if (widget.habit.trackingType != 'binary') ...[
                            const SizedBox(width: 5),
                            Align(
                              alignment: Alignment.center,
                              child: Container(
                                constraints:
                                    const BoxConstraints(maxWidth: 160),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  border: Border.all(
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                    width: 1,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  _getProgressDisplayText(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        lineHeight: 1.05,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Row(
                      children: [
                        const SizedBox(width: 5),
                        _buildHabitPriorityStars(),
                        const SizedBox(width: 5),
                        Builder(
                          builder: (btnCtx) => GestureDetector(
                            onTap: () {
                              _showSnoozeRescheduleMenu(btnCtx);
                            },
                            child: const Icon(Icons.snooze, size: 20),
                          ),
                        ),
                        Visibility(
                          visible: widget.showCalendar,
                          child: Row(
                            children: [
                              const SizedBox(width: 5),
                              GestureDetector(
                                child: const Icon(Icons.calendar_today,
                                    size: 20, color: Colors.blueGrey),
                                onTap: () {
                                  showDatePicker(
                                    context: context,
                                    initialDate:
                                        widget.habit.dueDate ?? DateTime.now(),
                                    firstDate: DateTime.now()
                                        .subtract(const Duration(days: 365)),
                                    lastDate: DateTime.now()
                                        .add(const Duration(days: 365)),
                                  ).then((selectedDate) {
                                    if (selectedDate != null) {
                                      widget.habit.reference.update({
                                        'dueDate': DateTime(
                                          selectedDate.year,
                                          selectedDate.month,
                                          selectedDate.day,
                                        ),
                                      }).then((_) {
                                        if (widget.onHabitUpdated != null) {
                                          widget.onHabitUpdated!(widget.habit);
                                        }
                                      });
                                    }
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 5),
                        Builder(
                          builder: (btnCtx) => GestureDetector(
                            onTap: () {
                              _showHabitOverflowMenu(btnCtx);
                            },
                            child: const Icon(Icons.more_vert, size: 20),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (widget.habit.trackingType != 'binary') ...[
                const SizedBox(height: 3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: _leftStripeColor,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Stack(
                      children: [
                        // Background track (always full width) - white fill
                        Container(
                          width: double.infinity,
                          height: 3,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        // Progress fill
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: _progressPercentClamped,
                          child: Container(
                            height: 3,
                            decoration: BoxDecoration(
                              color: _leftStripeColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHabitPriorityStars() {
    final current = widget.habit.priority;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final level = i + 1;
        final filled = current >= level;
        return GestureDetector(
          onTap: () async {
            try {
              final next = current == 0 ? 1 : (current % 3) + 1;
              await updateHabit(
                habitRef: widget.habit.reference,
                priority: next,
              );
              final updated =
                  await HabitRecord.getDocumentOnce(widget.habit.reference);
              widget.onHabitUpdated?.call(updated);
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error updating priority: $e')),
                );
              }
            }
          },
          child: Icon(
            filled ? Icons.star : Icons.star_border,
            size: 24,
            color: filled
                ? Colors.amber
                : FlutterFlowTheme.of(context).secondaryText.withOpacity(0.35),
          ),
        );
      }),
    );
  }

  Future<void> _showHabitOverflowMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: const [
        PopupMenuItem<String>(
            value: 'edit',
            height: 32,
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'copy',
            height: 32,
            child: Text('Duplicate', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    if (selected == 'edit') {
      if (widget.showTaskEdit) {
        showDialog(
          context: context,
          builder: (_) => CreateTask(
            task: widget.habit,
            categories: widget.categories ?? [],
            onSave: (updatedHabit) async {
              await updatedHabit.reference.update({
                'name': updatedHabit.name,
                'categoryId': updatedHabit.categoryId,
                'categoryName': updatedHabit.categoryName,
                'trackingType': updatedHabit.trackingType,
                'target': updatedHabit.target,
                'unit': updatedHabit.unit,
                'dueDate': updatedHabit.dueDate,
              });
              if (widget.tasks != null) {
                final index = widget.tasks!.indexWhere(
                    (t) => t.reference.id == updatedHabit.reference.id);
                if (index != -1) {
                  widget.tasks![index] = updatedHabit;
                }
              }
            },
          ),
        ).then((value) {
          if (value) {
            if (widget.onHabitUpdated != null) {
              widget.onHabitUpdated!(widget.habit);
            }
          }
        });
      } else {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CreateHabitPage(habitToEdit: widget.habit),
          ),
        );
      }
    } else if (selected == 'copy') {
      await _copyHabit();
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
          await widget.onRefresh?.call();
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error deleting habit: $e')),
            );
          }
        }
      }
    }
  }

  Future<void> _showSnoozeRescheduleMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: const [
        PopupMenuItem<String>(
            value: 'snooze_tomorrow',
            height: 32,
            child: Text('Snooze to tomorrow', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'snooze_weekend',
            height: 32,
            child: Text('Snooze to weekend', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'snooze_next_week',
            height: 32,
            child: Text('Snooze to next week', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'pick_date',
            height: 32,
            child: Text('Pick a date…', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'clear_snooze',
            height: 32,
            child: Text('Clear snooze', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    DateTime? newDate;
    if (selected == 'snooze_tomorrow') {
      newDate = _tomorrowDate();
    } else if (selected == 'snooze_weekend') {
      newDate = _nextWeekend();
    } else if (selected == 'snooze_next_week') {
      newDate = _nextWeekMonday();
    } else if (selected == 'pick_date') {
      final picked = await showDatePicker(
        context: context,
        initialDate: _tomorrowDate(),
        firstDate: _todayDate(),
        lastDate: _todayDate().add(const Duration(days: 365)),
      );
      if (picked != null) newDate = picked;
    } else if (selected == 'clear_snooze') {
      try {
        await updateHabit(
            habitRef: widget.habit.reference, snoozedUntil: DateTime(1970));
        final updated =
            await HabitRecord.getDocumentOnce(widget.habit.reference);
        widget.onHabitUpdated?.call(updated);
        return;
      } catch (_) {
        return;
      }
    }
    if (newDate != null) {
      try {
        await updateHabit(
            habitRef: widget.habit.reference, snoozedUntil: newDate);
        final updated =
            await HabitRecord.getDocumentOnce(widget.habit.reference);
        widget.onHabitUpdated?.call(updated);
        if (mounted) {
          final label = DateFormat('EEE, MMM d').format(newDate);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Snoozed to $label')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error snoozing: $e')),
          );
        }
      }
    }
  }

  Future<void> _showQuantControlsMenu(
      BuildContext anchorContext, bool canDecrement) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: FlutterFlowTheme.of(context).alternate),
      ),
      items: [
        const PopupMenuItem<String>(
          value: 'inc',
          height: 36,
          child: Row(
            children: [
              Icon(Icons.add, size: 18),
              SizedBox(width: 8),
              Text('Increase')
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'dec',
          enabled: canDecrement,
          height: 36,
          child: const Row(
            children: [
              Icon(Icons.remove, size: 18),
              SizedBox(width: 8),
              Text('Decrease')
            ],
          ),
        ),
      ],
    );
    if (selected == 'inc') {
      await _updateProgress(1);
    } else if (selected == 'dec' && canDecrement) {
      await _updateProgress(-1);
    }
  }

  Color get _leftStripeColor {
    final hex = widget.categoryColorHex;
    if (hex != null && hex.isNotEmpty) {
      try {
        return Color(int.parse(hex.replaceFirst('#', '0xFF')));
      } catch (_) {}
    }
    return _impactLevelColor;
  }

  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));
  DateTime _nextWeekend() {
    final today = _todayDate();
    final int daysUntilSaturday = (DateTime.saturday - today.weekday) % 7;
    return today
        .add(Duration(days: daysUntilSaturday == 0 ? 7 : daysUntilSaturday));
  }

  DateTime _nextWeekMonday() {
    final today = _todayDate();
    final int daysUntilMonday = (DateTime.monday - today.weekday) % 7;
    return today
        .add(Duration(days: daysUntilMonday == 0 ? 7 : daysUntilMonday));
  }

  String _getProgressDisplayText() {
    switch (widget.habit.trackingType) {
      case 'binary':
        return '';
      case 'quantitative':
        final progress = _currentProgressLocal();
        final target = HabitTrackingUtil.getTarget(widget.habit);
        return '$progress/$target ${widget.habit.unit}';
      case 'time':
        final target = HabitTrackingUtil.getTarget(widget.habit);
        final targetFormatted = HabitTrackingUtil.formatTargetTime(target);
        return '${_getTimerDisplayWithSeconds()} / $targetFormatted';
      default:
        return '';
    }
  }

  Widget _buildLeftControlsCompact() {
    switch (widget.habit.trackingType) {
      case 'binary':
        return SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: _isCompleted,
            onChanged: _isUpdating
                ? null
                : (value) async {
                    setState(() => _isUpdating = true);
                    try {
                      if (value == true) {
                        await HabitTrackingUtil.markCompleted(widget.habit);
                      } else {
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
                      final updated = await HabitRecord.getDocumentOnce(
                          widget.habit.reference);
                      widget.onHabitUpdated?.call(updated);
                    } catch (_) {
                    } finally {
                      if (mounted) setState(() => _isUpdating = false);
                    }
                  },
            activeColor: _impactLevelColor,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        );
      case 'quantitative':
        final current = _currentProgressLocal();
        final canDecrement = current > 0;
        return Builder(
          builder: (btnCtx) => GestureDetector(
            // onDoubleTap: _isUpdating || !canDecrement
            //     ? null
            //     : () => _updateProgress(-1),
            onLongPress: () => _showQuantControlsMenu(btnCtx, canDecrement),
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).primaryText,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: _isUpdating ? null : () => _updateProgress(1),
                  child: const Icon(
                    Icons.add,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      case 'time':
        final bool isActive = _isTimerActiveLocal;
        return Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: isActive
                ? FlutterFlowTheme.of(context).error
                : FlutterFlowTheme.of(context).primaryText,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(4),
              onTap: () async {
                setState(() => _isUpdating = true);
                try {
                  if (_isTimerActiveLocal) {
                    // Stop the timer
                    _timer?.cancel(); // stop local timer
                    await HabitTrackingUtil.stopTimer(widget.habit);
                    TimerManager().stop(widget.habit);

                    await widget.habit.reference.update(createHabitRecordData(
                      isTimerActive: false,
                      showInFloatingTimer: false,
                    ));
                  } else {
                    // Start the timer
                    final now = DateTime.now();
                    await HabitTrackingUtil.startTimer(widget.habit);
                    TimerManager().start(widget.habit);

                    await widget.habit.reference.update(createHabitRecordData(
                      isTimerActive: true,
                      showInFloatingTimer: true,
                      timerStartTime: now,
                    ));

                    // Start the local timer in this widget
                    _startTimer();
                  }

                  // Update UI with latest habit
                  final updated =
                      await HabitRecord.getDocumentOnce(widget.habit.reference);
                  widget.onHabitUpdated?.call(updated);
                } catch (_) {
                  setState(() => _timerStateOverride = null);
                } finally {
                  setState(() => _isUpdating = false);
                }
              },
              child: Icon(
                isActive ? Icons.stop : Icons.play_arrow,
                size: 16,
                color: Colors.white,
              ),
            ),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Future<void> _updateProgress(int delta) async {
    if (_isUpdating) return;
    setState(() {
      _isUpdating = true;
    });
    try {
      final currentProgress = _currentProgressLocal();

      final current = (currentProgress is int)
          ? currentProgress
          : (currentProgress is double)
              ? currentProgress.round()
              : int.tryParse(currentProgress.toString()) ?? 0;
      int newProgress = current + delta;
      if (newProgress < 0) {
        newProgress = 0;
      }
      _quantProgressOverride = newProgress;
      if (mounted) setState(() {});
      await HabitTrackingUtil.updateProgress(widget.habit, newProgress);
      final updated = await HabitRecord.getDocumentOnce(widget.habit.reference);
      widget.onHabitUpdated?.call(updated);
    } catch (e) {
      print('Error updating progress: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating progress: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }
}
