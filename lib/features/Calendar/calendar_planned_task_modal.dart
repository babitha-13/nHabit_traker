import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/features/Calendar/Helpers/calendar_models.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:habit_tracker/services/Activtity/Activity%20Instance%20Service/activity_instance_service.dart';
import 'package:habit_tracker/services/Activtity/task_instance_service/task_instance_task_service.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/optimistic_operation_tracker.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';

/// Modal for creating **or editing** a planned task from the calendar's
/// Planned section.  Pass [editMetadata] to enter edit mode.
class CalendarPlannedTaskModal extends StatefulWidget {
  final DateTime selectedDate;
  final DateTime? initialStartTime;
  final DateTime? initialEndTime;
  final VoidCallback onSave;
  final Function(DateTime start, DateTime end, String type, Color? color)?
      onPreviewChange;
  /// Non-null when editing an existing planned tile (long-press).
  final CalendarEventMetadata? editMetadata;

  const CalendarPlannedTaskModal({
    super.key,
    required this.selectedDate,
    required this.onSave,
    this.initialStartTime,
    this.initialEndTime,
    this.onPreviewChange,
    this.editMetadata,
  });

  @override
  State<CalendarPlannedTaskModal> createState() =>
      _CalendarPlannedTaskModalState();
}

class _CalendarPlannedTaskModalState extends State<CalendarPlannedTaskModal> {
  final TextEditingController _taskController = TextEditingController();
  final FocusNode _taskFocusNode = FocusNode();
  final GlobalKey _textFieldKey = GlobalKey();

  late DateTime _startTime;
  late DateTime _endTime;
  int _defaultDurationMinutes = 10;

  List<ActivityRecord> _allTaskTemplates = [];
  List<ActivityRecord> _suggestions = [];
  ActivityRecord? _selectedTemplate;

  List<CategoryRecord> _taskCategories = [];
  CategoryRecord? _selectedCategory;

  OverlayEntry? _overlayEntry;

  bool get _isEditMode => widget.editMetadata != null;

  @override
  void initState() {
    super.initState();
    // Pre-fill name before adding listener so it doesn't trigger search.
    if (_isEditMode) {
      _taskController.text = widget.editMetadata!.activityName;
    }
    _initializeTimes();
    _loadData();
    _taskController.addListener(_onSearchChanged);
    _taskFocusNode.addListener(_onFocusChanged);
  }

  void _initializeTimes() {
    final now = DateTime.now();
    final base = widget.selectedDate;
    _startTime = widget.initialStartTime ??
        DateTime(base.year, base.month, base.day, now.hour, now.minute);
    _endTime = widget.initialEndTime ??
        _startTime.add(const Duration(minutes: 10));
  }

  void _onFocusChanged() {
    if (!_taskFocusNode.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted && !_taskFocusNode.hasFocus) _removeOverlay();
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final duration =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(userId);
      if (mounted) {
        setState(() {
          _defaultDurationMinutes = duration;
          if (widget.initialEndTime == null) {
            _endTime =
                _startTime.add(Duration(minutes: _defaultDurationMinutes));
          }
        });
      }

      final results = await Future.wait([
        CategoryRecord.collectionForUser(userId)
            .where('categoryType', isEqualTo: 'task')
            .where('isActive', isEqualTo: true)
            .get(),
        ActivityRecord.collectionForUser(userId)
            .where('categoryType', isEqualTo: 'task')
            .where('isActive', isEqualTo: true)
            .get(),
      ]);

      if (!mounted) return;

      final categories = results[0].docs
          .map((d) => CategoryRecord.fromSnapshot(d))
          .toList();

      final templates = results[1].docs
          .map((d) => ActivityRecord.fromSnapshot(d))
          .where((t) => !t.isRecurring)
          .toList();

      // In edit mode, pre-select the existing template even if it was filtered
      // out (e.g. became recurring) — fetch it directly if necessary.
      ActivityRecord? editTemplate;
      final editTplId = widget.editMetadata?.templateId ?? '';
      if (_isEditMode && editTplId.isNotEmpty) {
        editTemplate = _findById(templates, editTplId);
        if (editTemplate == null) {
          try {
            final snap = await ActivityRecord.collectionForUser(userId)
                .doc(editTplId)
                .get();
            if (snap.exists) {
              editTemplate = ActivityRecord.fromSnapshot(snap);
            }
          } catch (_) {}
        }
      }

      CategoryRecord? defaultCategory;
      try {
        defaultCategory =
            categories.firstWhere((c) => c.name.toLowerCase() == 'inbox');
      } catch (_) {
        defaultCategory = categories.isNotEmpty ? categories.first : null;
      }

      CategoryRecord? editCategory;
      if (editTemplate != null && editTemplate.categoryId.isNotEmpty) {
        editCategory = _findCatById(categories, editTemplate.categoryId);
      }

      setState(() {
        _taskCategories = categories;
        _allTaskTemplates = templates;
        if (_isEditMode && editTemplate != null) {
          _selectedTemplate = editTemplate;
          _selectedCategory = editCategory ?? defaultCategory;
        } else {
          _selectedCategory ??= defaultCategory;
        }
      });
    } catch (_) {}
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  ActivityRecord? _findById(List<ActivityRecord> list, String id) {
    for (final t in list) {
      if (t.reference.id == id) return t;
    }
    return null;
  }

  CategoryRecord? _findCatById(List<CategoryRecord> list, String id) {
    for (final c in list) {
      if (c.reference.id == id) return c;
    }
    return null;
  }

  // ── search overlay ───────────────────────────────────────────────────────

  void _onSearchChanged() {
    final query = _taskController.text.toLowerCase();
    setState(() {
      _suggestions = _allTaskTemplates
          .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
          .toList();
    });
    if (_taskFocusNode.hasFocus && _suggestions.isNotEmpty) {
      _removeOverlay();
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _showOverlay() {
    if (_suggestions.isEmpty) return;
    final theme = FlutterFlowTheme.of(context);
    final renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.attached) return;
    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (ctx) => Positioned(
        left: offset.dx,
        top: offset.dy + size.height + 4,
        width: size.width,
        child: Material(
          elevation: 16,
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          child: Container(
            constraints: const BoxConstraints(maxHeight: 160),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: theme.surfaceBorderColor),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _suggestions.length,
              itemBuilder: (_, i) {
                final template = _suggestions[i];
                return InkWell(
                  onTap: () => _selectTemplate(template),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Text(template.name, style: theme.bodyMedium),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _selectTemplate(ActivityRecord template) {
    _taskController.removeListener(_onSearchChanged);
    _removeOverlay();
    _taskFocusNode.unfocus();
    _taskController.text = template.name;

    CategoryRecord? matchedCategory;
    if (template.categoryId.isNotEmpty) {
      matchedCategory = _findCatById(_taskCategories, template.categoryId);
    }

    setState(() {
      _selectedTemplate = template;
      if (matchedCategory != null) _selectedCategory = matchedCategory;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _taskController.addListener(_onSearchChanged);
    });
  }

  // ── time pickers ──────────────────────────────────────────────────────────

  int get _durationMinutes =>
      _endTime.difference(_startTime).inMinutes.clamp(1, 1440);

  String get _durationLabel {
    final mins = _durationMinutes;
    if (mins >= 60) {
      final h = mins ~/ 60;
      final m = mins % 60;
      return m == 0 ? '${h}h' : '${h}h ${m}m';
    }
    return '${mins}m';
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: _startTime.hour, minute: _startTime.minute),
    );
    if (picked == null || !mounted) return;
    final prevDuration = _durationMinutes;
    final newStart = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      picked.hour,
      picked.minute,
    );
    setState(() {
      _startTime = newStart;
      _endTime = newStart.add(Duration(minutes: prevDuration));
    });
    widget.onPreviewChange?.call(_startTime, _endTime, 'task', null);
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _endTime.hour, minute: _endTime.minute),
    );
    if (picked == null || !mounted) return;
    var newEnd = DateTime(
      widget.selectedDate.year,
      widget.selectedDate.month,
      widget.selectedDate.day,
      picked.hour,
      picked.minute,
    );
    if (!newEnd.isAfter(_startTime)) {
      newEnd = newEnd.add(const Duration(days: 1));
    }
    setState(() => _endTime = newEnd);
    widget.onPreviewChange?.call(_startTime, _endTime, 'task', null);
  }

  // ── save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final name = _taskController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please enter a task name'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!_isEditMode &&
        _selectedTemplate == null &&
        _selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Please select a category'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    if (!_endTime.isAfter(_startTime)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('End time must be after start time'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final dueTimeStr = TimeUtils.timeOfDayToString(
        TimeOfDay(hour: _startTime.hour, minute: _startTime.minute));
    final durationMins = _durationMinutes;
    final rootContext =
        Navigator.of(context, rootNavigator: true).context;
    final onSaveCallback = widget.onSave;

    Navigator.of(context).pop();

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      if (_isEditMode) {
        await _saveEdit(
          userId: userId,
          name: name,
          dueTimeStr: dueTimeStr,
          durationMins: durationMins,
        );
      } else if (_selectedTemplate != null) {
        await _saveForExistingTemplate(
          userId: userId,
          template: _selectedTemplate!,
          dueTimeStr: dueTimeStr,
          durationMins: durationMins,
        );
      } else {
        final category = _selectedCategory!;
        await createActivity(
          name: name,
          categoryId: category.reference.id,
          categoryName: category.name,
          trackingType: 'binary',
          isRecurring: false,
          categoryType: 'task',
          dueDate: widget.selectedDate,
          dueTime: dueTimeStr,
          timeEstimateMinutes: durationMins,
          userId: userId,
        );
      }

      onSaveCallback();
    } catch (e) {
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
          content: Text('Failed to plan task: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  Future<void> _saveEdit({
    required String userId,
    required String name,
    required String dueTimeStr,
    required int durationMins,
  }) async {
    final meta = widget.editMetadata!;
    final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
        .doc(meta.instanceId);
    final instance = await ActivityInstanceRecord.getDocumentOnce(instanceRef);

    // Update due time with optimistic broadcast so tile moves immediately.
    await _updateInstanceWithDueTime(
      instance: instance,
      dueDate: widget.selectedDate,
      dueTimeStr: dueTimeStr,
    );

    // Persist name change on instance and template if it changed.
    final currentName = meta.activityName;
    if (name != currentName) {
      await instanceRef
          .update({'templateName': name, 'lastUpdated': DateTime.now()});
    }

    // Update template fields (name + duration).
    final tplId = _selectedTemplate?.reference.id ?? meta.templateId ?? '';
    if (tplId.isNotEmpty) {
      final tplUpdate = <String, dynamic>{
        'timeEstimateMinutes': durationMins,
        'lastUpdated': DateTime.now(),
      };
      if (name != currentName) tplUpdate['name'] = name;
      await ActivityRecord.collectionForUser(userId).doc(tplId).update(tplUpdate);
    }
  }

  Future<void> _saveForExistingTemplate({
    required String userId,
    required ActivityRecord template,
    required String dueTimeStr,
    required int durationMins,
  }) async {
    ActivityInstanceRecord? existingInstance;
    try {
      final allPending = await TaskInstanceTaskService.getTodaysTaskInstances(
          userId: userId);
      final matches =
          allPending.where((i) => i.templateId == template.reference.id);
      if (matches.isNotEmpty) existingInstance = matches.first;
    } catch (_) {}

    if (existingInstance != null) {
      await _updateInstanceWithDueTime(
        instance: existingInstance,
        dueDate: widget.selectedDate,
        dueTimeStr: dueTimeStr,
      );
    } else {
      await ActivityInstanceService.createActivityInstance(
        templateId: template.reference.id,
        dueDate: widget.selectedDate,
        dueTime: dueTimeStr,
        template: template,
        userId: userId,
        skipOrderLookup: true,
      );
    }

    await template.reference.update({
      'timeEstimateMinutes': durationMins,
      'lastUpdated': DateTime.now(),
    });
  }

  Future<void> _updateInstanceWithDueTime({
    required ActivityInstanceRecord instance,
    required DateTime dueDate,
    required String dueTimeStr,
  }) async {
    final now = DateTime.now();
    final updateData = <String, dynamic>{
      'dueDate': dueDate,
      'dueTime': dueTimeStr,
      'lastUpdated': now,
    };

    final snapshotCopy =
        Map<String, dynamic>.from(instance.snapshotData);
    snapshotCopy['dueDate'] = dueDate;
    snapshotCopy['dueTime'] = dueTimeStr;
    snapshotCopy['lastUpdated'] = now;
    snapshotCopy['_optimistic'] = true;
    final optimisticInstance = ActivityInstanceRecord.getDocumentFromData(
        snapshotCopy, instance.reference);

    final operationId = OptimisticOperationTracker.generateOperationId();
    OptimisticOperationTracker.trackOperation(
      operationId,
      instanceId: instance.reference.id,
      operationType: 'progress',
      optimisticInstance: optimisticInstance,
      originalInstance: instance,
    );
    InstanceEvents.broadcastInstanceUpdatedOptimistic(
        optimisticInstance, operationId);

    try {
      await instance.reference.update(updateData);
      final updated =
          await ActivityInstanceRecord.getDocumentOnce(instance.reference);
      OptimisticOperationTracker.reconcileOperation(operationId, updated);
    } catch (e) {
      OptimisticOperationTracker.rollbackOperation(operationId);
      rethrow;
    }
  }

  // ── delete ────────────────────────────────────────────────────────────────

  Future<void> _delete() async {
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove from Calendar'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Remove Plan',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 4),
            Text(
              'Removes the scheduled time from this task — the task stays in your list without a planned time.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
            SizedBox(height: 16),
            Text(
              'Delete Task',
              style:
                  TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
            SizedBox(height: 4),
            Text(
              'Permanently deletes this task instance. It will disappear from your task list entirely.',
              style: TextStyle(fontSize: 13, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('remove_plan'),
            child: const Text('Remove Plan',
                style: TextStyle(color: Colors.orange)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('delete_task'),
            child: const Text('Delete Task',
                style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel' || !mounted) return;

    final rootContext =
        Navigator.of(context, rootNavigator: true).context;
    final onSaveCallback = widget.onSave;

    Navigator.of(context).pop();

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      final meta = widget.editMetadata!;
      final instanceRef = ActivityInstanceRecord.collectionForUser(userId)
          .doc(meta.instanceId);
      final instance =
          await ActivityInstanceRecord.getDocumentOnce(instanceRef);
      final now = DateTime.now();

      if (choice == 'remove_plan') {
        // Strip the planned time from the instance.
        await instanceRef.update({
          'dueDate': FieldValue.delete(),
          'dueTime': FieldValue.delete(),
          'lastUpdated': now,
        });

        // Remove duration from template so future estimates are not skewed.
        final tplId = meta.templateId ?? '';
        if (tplId.isNotEmpty) {
          try {
            await ActivityRecord.collectionForUser(userId).doc(tplId).update({
              'timeEstimateMinutes': FieldValue.delete(),
              'lastUpdated': now,
            });
          } catch (_) {}
        }

        // Broadcast the updated instance (with dueTime=null). The calendar's
        // wasVisibleOnDate guard will invalidate the cache and schedule a refresh.
        final snapshotCopy =
            Map<String, dynamic>.from(instance.snapshotData);
        snapshotCopy.remove('dueDate');
        snapshotCopy.remove('dueTime');
        snapshotCopy['lastUpdated'] = now;
        final updatedInstance =
            ActivityInstanceRecord.getDocumentFromData(snapshotCopy, instanceRef);
        InstanceEvents.broadcastInstanceUpdated(updatedInstance);
      } else if (choice == 'delete_task') {
        // Delete the Firestore document; broadcastInstanceDeleted immediately
        // removes the tile from _plannedEventController in the calendar page.
        await instanceRef.delete();
        InstanceEvents.broadcastInstanceDeleted(instance);
      }

      onSaveCallback();
    } catch (e) {
      if (rootContext.mounted) {
        ScaffoldMessenger.of(rootContext).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ));
      }
    }
  }

  // ── dispose ───────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _removeOverlay();
    _taskController.removeListener(_onSearchChanged);
    _taskFocusNode.removeListener(_onFocusChanged);
    _taskController.dispose();
    _taskFocusNode.dispose();
    super.dispose();
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final bottomSafeArea = MediaQuery.of(context).padding.bottom;
    final keyboardInset = MediaQuery.of(context).viewInsets.bottom;
    final hasKeyboard = keyboardInset > 0;

    return PopScope(
      canPop: true,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Container(
          padding: EdgeInsets.only(
              bottom: hasKeyboard ? keyboardInset : bottomSafeArea),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: Colors.grey[200], height: 1),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding:
                      EdgeInsets.only(bottom: hasKeyboard ? 8.0 : 12.0),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Header
                        Row(
                          children: [
                            Icon(
                              _isEditMode
                                  ? Icons.edit_calendar
                                  : Icons.event_note,
                              color: theme.primary,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isEditMode
                                  ? 'Edit Planned Task'
                                  : 'Plan a Task',
                              style: theme.titleMedium
                                  .copyWith(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // Task name / search
                        Container(
                          key: _textFieldKey,
                          padding:
                              const EdgeInsets.symmetric(horizontal: 10),
                          constraints: const BoxConstraints(minHeight: 42),
                          decoration: BoxDecoration(
                            color: theme.tertiary.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: theme.surfaceBorderColor, width: 1),
                          ),
                          child: TextField(
                            controller: _taskController,
                            focusNode: _taskFocusNode,
                            style: theme.bodyMedium,
                            textAlignVertical: TextAlignVertical.center,
                            decoration: InputDecoration(
                              hintText: 'Search or create a task...',
                              hintStyle: TextStyle(
                                  color: theme.secondaryText, fontSize: 14),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  vertical: 10),
                              icon: const Icon(Icons.search,
                                  size: 20, color: Colors.grey),
                              suffixIcon: _taskController.text.isNotEmpty
                                  ? IconButton(
                                      padding: const EdgeInsets.all(8),
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.clear,
                                          size: 16),
                                      onPressed: () {
                                        _taskController.clear();
                                        setState(
                                            () => _selectedTemplate = null);
                                        _removeOverlay();
                                      },
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),

                        // Category dropdown — hidden when template is selected
                        if (_selectedTemplate == null) ...[
                          _buildCategoryDropdown(theme),
                          const SizedBox(height: 10),
                        ],

                        // Time pickers
                        Row(
                          children: [
                            Expanded(
                                child: _buildTimePicker(
                              label: 'Due Time',
                              time: _startTime,
                              icon: Icons.access_time,
                              onTap: _pickStartTime,
                              theme: theme,
                            )),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 12),
                              child: Icon(Icons.arrow_forward,
                                  size: 16, color: Colors.grey),
                            ),
                            Expanded(
                                child: _buildTimePicker(
                              label: 'End Time',
                              time: _endTime,
                              icon: Icons.access_time_filled,
                              onTap: _pickEndTime,
                              theme: theme,
                            )),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // Duration display
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: Colors.blue.shade100),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.timelapse,
                                  color: Colors.blue.shade600, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                'Planned duration: $_durationLabel',
                                style: theme.bodySmall.copyWith(
                                  color: Colors.blue.shade700,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Action row: save + delete (edit mode)
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _save,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(12)),
                                  elevation: 0,
                                ),
                                child: Text(
                                  _isEditMode ? 'Update Plan' : 'Plan Task',
                                  style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                            if (_isEditMode) ...[
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.delete_outline),
                                color: Colors.red,
                                tooltip: 'Remove / Delete',
                                onPressed: _delete,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTimePicker({
    required String label,
    required DateTime time,
    required IconData icon,
    required VoidCallback onTap,
    required FlutterFlowTheme theme,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.bodySmall.copyWith(
                color: theme.secondaryText,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: 12, horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  DateFormat.jm().format(time),
                  style: theme.bodyMedium
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown(FlutterFlowTheme theme) {
    CategoryRecord? validSelected = _selectedCategory;
    if (validSelected != null &&
        !_taskCategories
            .any((c) => c.reference.id == validSelected!.reference.id)) {
      validSelected = null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: theme.tertiary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.surfaceBorderColor, width: 1),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButtonFormField<CategoryRecord>(
          value: validSelected,
          decoration: const InputDecoration(
            border: InputBorder.none,
            isDense: true,
            icon: Icon(Icons.category, size: 20, color: Colors.grey),
          ),
          hint: Text('Select Category', style: theme.bodySmall),
          isExpanded: true,
          style: theme.bodyMedium,
          items: _taskCategories.map((category) {
            Color cat;
            try {
              cat = Color(
                  int.parse(category.color.replaceFirst('#', '0xFF')));
            } catch (_) {
              cat = theme.primary;
            }
            return DropdownMenuItem<CategoryRecord>(
              value: category,
              child: Row(children: [
                Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                        color: cat, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Text(category.name),
              ]),
            );
          }).toList(),
          onChanged: (v) => setState(() => _selectedCategory = v),
        ),
      ),
    );
  }
}
