import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/activity_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Shared/activity_editor_dialog.dart';
import 'package:intl/intl.dart';
class ActivityControls extends StatefulWidget {
  final ActivityRecord activity;
  final Function(ActivityRecord) onActivityUpdated;
  final Color impactLevelColor;
  final bool isTimerActive;
  final num currentProgress;
  const ActivityControls({
    Key? key,
    required this.activity,
    required this.onActivityUpdated,
    required this.impactLevelColor,
    required this.isTimerActive,
    required this.currentProgress,
  }) : super(key: key);
  @override
  _ActivityControlsState createState() => _ActivityControlsState();
}
class _ActivityControlsState extends State<ActivityControls> {
  bool _isUpdating = false;
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
  Future<void> _updateProgress(int delta) async {
    if (_isUpdating) return;
    setState(() => _isUpdating = true);
    try {
      await ActivityService.updateProgress(widget.activity, delta);
      final updated =
          await ActivityRecord.getDocumentOnce(widget.activity.reference);
      widget.onActivityUpdated(updated);
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    switch (widget.activity.trackingType) {
      case 'binary':
        return _buildBinaryControl(context);
      case 'quantitative':
        return _buildQuantitativeControl(context);
      case 'time':
        return _buildTimeControl(context);
      default:
        return const SizedBox.shrink();
    }
  }
  Widget _buildBinaryControl(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Checkbox(
        value: widget.activity.completedDates.isNotEmpty,
        onChanged: _isUpdating
            ? null
            : (value) async {
                setState(() => _isUpdating = true);
                try {
                  await ActivityService.toggleBinaryCompletion(widget.activity);
                  final updated = await ActivityRecord.getDocumentOnce(
                      widget.activity.reference);
                  widget.onActivityUpdated(updated);
                } finally {
                  if (mounted) setState(() => _isUpdating = false);
                }
              },
        activeColor: widget.impactLevelColor,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
  Widget _buildQuantitativeControl(BuildContext context) {
    final canDecrement = widget.currentProgress > 0;
    return Builder(
      builder: (btnCtx) => GestureDetector(
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
  }
  Widget _buildTimeControl(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: widget.isTimerActive
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
              await ActivityService.toggleTimer(widget.activity);
              final updated = await ActivityRecord.getDocumentOnce(
                  widget.activity.reference);
              widget.onActivityUpdated(updated);
            } finally {
              if (mounted) setState(() => _isUpdating = false);
            }
          },
          child: Icon(
            widget.isTimerActive ? Icons.stop : Icons.play_arrow,
            size: 16,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}
class ActivityOverflowMenu extends StatelessWidget {
  final ActivityRecord activity;
  final bool showTaskEdit;
  final List<CategoryRecord>? categories;
  final List<ActivityRecord>? tasks;
  final VoidCallback? onRefresh;
  final Function(ActivityRecord)? onHabitUpdated;
  final Function(ActivityRecord)? onHabitDeleted;
  const ActivityOverflowMenu({
    Key? key,
    required this.activity,
    this.showTaskEdit = false,
    this.categories,
    this.tasks,
    this.onRefresh,
    this.onHabitUpdated,
    this.onHabitDeleted,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnCtx) => GestureDetector(
        onTap: () {
          _showHabitOverflowMenu(btnCtx);
        },
        child: const Icon(Icons.more_vert, size: 20),
      ),
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
        side: BorderSide(color: FlutterFlowTheme.of(anchorContext).alternate),
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
      _editHabit(anchorContext);
    } else if (selected == 'copy') {
      _copyHabit(anchorContext);
    } else if (selected == 'delete') {
      _deleteHabit(anchorContext);
    }
  }
  void _editHabit(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => ActivityEditorDialog(
        activity: activity,
        isHabit: activity.categoryType == 'habit',
        categories: categories ?? [],
        onSave: (updatedHabit) {
          if (showTaskEdit && tasks != null && updatedHabit != null) {
            final index = tasks!.indexWhere(
                (t) => t.reference.id == updatedHabit.reference.id);
            if (index != -1) {
              tasks![index] = updatedHabit;
            }
          }
        },
      ),
    ).then((value) {
      if (value == true) {
        if (showTaskEdit) {
          onHabitUpdated?.call(activity);
        }
        onRefresh?.call();
      }
    });
  }
  Future<void> _copyHabit(BuildContext context) async {
    try {
      await ActivityService.copyActivity(activity);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Habit copied')),
      );
      onRefresh?.call();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error copying habit: $e')),
      );
    }
  }
  Future<void> _deleteHabit(BuildContext context) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Habit'),
        content: Text('Delete "${activity.name}"? This cannot be undone.'),
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
        await ActivityService.deleteActivity(activity.reference);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Habit deleted')),
        );
        onHabitDeleted?.call(activity);
        onRefresh?.call();
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error deleting habit: $e')),
        );
      }
    }
  }
}
class ActivityScheduleMenu extends StatelessWidget {
  final ActivityRecord activity;
  final Function(ActivityRecord) onActivityUpdated;
  const ActivityScheduleMenu({
    Key? key,
    required this.activity,
    required this.onActivityUpdated,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (btnCtx) => GestureDetector(
        onTap: () {
          _showScheduleMenu(btnCtx);
        },
        child: const Icon(Icons.calendar_month, size: 20),
      ),
    );
  }
  bool _isRecurringItem() {
    return activity.isRecurring;
  }
  Future<void> _showScheduleMenu(BuildContext anchorContext) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    List<PopupMenuEntry<String>> items;
    if (_isRecurringItem()) {
      items = const [
        PopupMenuItem<String>(
            value: 'skip_occurrence',
            height: 32,
            child:
                Text('Skip This Occurrence', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'reschedule_occurrence',
            height: 32,
            child: Text('Reschedule This Occurrence',
                style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'skip_until',
            height: 32,
            child: Text('Skip Until...', style: TextStyle(fontSize: 12))),
      ];
    } else {
      items = const [
        PopupMenuItem<String>(
            value: 'schedule_today',
            height: 32,
            child: Text('Schedule for Today', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'schedule_tomorrow',
            height: 32,
            child:
                Text('Schedule for Tomorrow', style: TextStyle(fontSize: 12))),
        PopupMenuItem<String>(
            value: 'pick_date',
            height: 32,
            child: Text('Pick a Date...', style: TextStyle(fontSize: 12))),
      ];
    }
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
        side: BorderSide(color: FlutterFlowTheme.of(anchorContext).alternate),
      ),
      items: items,
    );
    if (selected == null) return;
    switch (selected) {
      case 'schedule_today':
        _scheduleForToday(anchorContext);
        break;
      case 'schedule_tomorrow':
        _scheduleForTomorrow(anchorContext);
        break;
      case 'pick_date':
        _pickDueDate(anchorContext);
        break;
      case 'skip_occurrence':
        _skipOccurrence(anchorContext);
        break;
      case 'reschedule_occurrence':
        _rescheduleOccurrence(anchorContext);
        break;
      case 'skip_until':
        _skipUntil(anchorContext);
        break;
    }
  }
  DateTime _todayDate() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }
  DateTime _tomorrowDate() => _todayDate().add(const Duration(days: 1));
  Future<void> _updateDueDate(BuildContext context, DateTime newDate) async {
    try {
      await ActivityService.updateDueDate(activity.reference, newDate);
      final updated = await ActivityRecord.getDocumentOnce(activity.reference);
      onActivityUpdated(updated);
      final label = DateFormat('EEE, MMM d').format(newDate);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Due date set to $label')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error setting due date: $e')),
      );
    }
  }
  void _scheduleForToday(BuildContext context) {
    _updateDueDate(context, _todayDate());
  }
  void _scheduleForTomorrow(BuildContext context) {
    _updateDueDate(context, _tomorrowDate());
  }
  void _pickDueDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: activity.dueDate ?? _tomorrowDate(),
      firstDate: _todayDate(),
      lastDate: _todayDate().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      _updateDueDate(context, picked);
    }
  }
  void _skipOccurrence(BuildContext context) {
    ActivityService.skipOccurrence(activity);
  }
  void _rescheduleOccurrence(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Rescheduling not implemented yet.')),
    );
  }
  void _skipUntil(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tomorrowDate(),
      firstDate: _todayDate(),
      lastDate: _todayDate().add(const Duration(days: 365 * 5)),
    );
    if (picked != null) {
      try {
        await ActivityService.skipUntil(activity.reference, picked);
        final updated =
            await ActivityRecord.getDocumentOnce(activity.reference);
        onActivityUpdated(updated);
        final label = DateFormat('EEE, MMM d').format(picked);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Skipped until $label')),
        );
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error skipping: $e')),
        );
      }
    }
  }
}
