import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/features/Routine/Backend_data/routine_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/routine_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_main.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Routine/Create%20Routine/create_routine_page.dart';
import 'package:collection/collection.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';
import 'package:habit_tracker/features/Essential/essential_data_service.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/Helper/backend/cache/batch_read_service.dart';
import 'package:habit_tracker/core/utils/Date_time/time_utils.dart';
import 'package:intl/intl.dart';

class RoutineDetailPage extends StatefulWidget {
  final RoutineRecord routine;
  final bool embedded;
  final VoidCallback? onBack;

  const RoutineDetailPage({
    super.key,
    required this.routine,
    this.embedded = false,
    this.onBack,
  });

  @override
  State<RoutineDetailPage> createState() => _RoutineDetailPageState();
}

class _RoutineDetailPageState extends State<RoutineDetailPage> {
  static const bool _traceRoutineSyncEnv =
      bool.fromEnvironment('TRACE_ROUTINE_SYNC', defaultValue: true);
  static bool get _traceRoutineSync => kDebugMode && _traceRoutineSyncEnv;
  RoutineWithInstances? _routineWithInstances;
  List<CategoryRecord> _categories = [];
  // Cache of ActivityRecord templates for routine items, keyed by templateId.
  // Used to build display-only instances for templates without a real
  // today-instance, so the user can see the item and act on it without
  // creating an empty pending Firestore row on every routine open.
  final Map<String, ActivityRecord> _templateCache = {};
  int? _defaultTimeEstimateMinutes;
  bool _isLoading = true;
  bool _isReordering = false;

  static bool _isDisplayInstance(ActivityInstanceRecord instance) =>
      instance.reference.id.startsWith('display_');

  void _logRoutineSync(
    String stage, {
    String? templateId,
    ActivityInstanceRecord? instance,
    bool? isOptimistic,
    String? note,
  }) {
    if (!_traceRoutineSync) return;
    final instanceId = instance?.reference.id ?? 'null';
    final status = instance?.status ?? 'null';
    final value = instance?.currentValue;
    final lastUpdatedMs = instance?.lastUpdated?.millisecondsSinceEpoch;
    debugPrint(
      '[routine-sync][$stage] '
      'routine=${widget.routine.reference.id} '
      'template=${templateId ?? instance?.templateId ?? 'null'} '
      'instance=$instanceId status=$status value=$value '
      'updatedMs=${lastUpdatedMs ?? 'null'} '
      'optimistic=${isOptimistic ?? false} '
      '${note ?? ''}',
    );
  }

  void _logRoutineSnapshot(
      String stage, Map<String, ActivityInstanceRecord> map) {
    if (!_traceRoutineSync) return;
    final entries = map.entries
        .take(8)
        .map((e) =>
            '${e.key}->${e.value.reference.id}:${e.value.status}:${e.value.currentValue}')
        .join(' | ');
    debugPrint(
      '[routine-sync][$stage] routine=${widget.routine.reference.id} '
      'items=${map.length} sample=$entries',
    );
  }

  @override
  void initState() {
    super.initState();
    _loadRoutineWithInstances();
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _refreshRoutine();
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (mounted) {
        _handleRoutineInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (mounted) {
        _handleRoutineInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (mounted) {
        _handleRoutineInstanceDeleted(param);
      }
    });
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      if (mounted) {
        _handleRoutineRollback(param);
      }
    });
  }

  Future<void> _loadRoutineWithInstances() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }
      final routineWithInstances = await RoutineService.getRoutineWithInstances(
        routineId: widget.routine.reference.id,
        userId: userId,
      );
      final habitCategories = await queryHabitCategoriesOnce(
        userId: userId,
        callerTag: 'RoutineDetailPage._loadRoutine.habits',
      );
      final taskCategories = await queryTaskCategoriesOnce(
        userId: userId,
        callerTag: 'RoutineDetailPage._loadRoutine.tasks',
      );
      final allCategories = [...habitCategories, ...taskCategories];
      // Load the user's default time estimate for quick-log fallback.
      try {
        _defaultTimeEstimateMinutes =
            await TimeLoggingPreferencesService.getDefaultDurationMinutes(
                userId);
      } catch (_) {
        // Non-fatal: quick-log will fall back to 1 minute.
      }
      RoutineWithInstances? updatedRoutineWithInstances = routineWithInstances;
      if (routineWithInstances != null) {
        final routine = routineWithInstances.routine;
        // Pre-fetch template metadata so display stubs can be built without
        // a per-item Firestore read.
        await _hydrateTemplateCache(routine);
        final instances = Map<String, ActivityInstanceRecord>.from(
            routineWithInstances.instances);
        for (int i = 0; i < routine.itemIds.length; i++) {
          final itemId = routine.itemIds[i];
          final itemType =
              routine.itemTypes.isNotEmpty && i < routine.itemTypes.length
                  ? routine.itemTypes[i]
                  : 'habit';
          final itemName =
              routine.itemNames.isNotEmpty && i < routine.itemNames.length
                  ? routine.itemNames[i]
                  : 'Unknown Item';
          if (instances.containsKey(itemId)) {
            continue;
          }
          if (itemType == 'habit' || itemType == 'task') {
            try {
              final newInstance =
                  await RoutineService.createInstanceForRoutineItem(
                itemId: itemId,
                userId: userId,
              );
              if (newInstance != null) {
                instances[itemId] = newInstance;
              } else {
                // createInstanceForRoutineItem returns null for templates
                // even when the cached itemType says 'habit'/'task'.
                // Fall through to the display-stub path so stale metadata
                // doesn't leave the item permanently missing.
                final displayInstance =
                    _buildDisplayTemplateInstance(itemId, itemName);
                if (displayInstance != null) {
                  instances[itemId] = displayInstance;
                }
              }
            } catch (e) {}
          } else if (itemType == 'template' || itemType == 'essential') {
            // Templates: render a display-only stub. No Firestore row is
            // created until the user takes an action (quick-log). This
            // keeps the queue clean and avoids accumulating empty pending
            // rows every time the routine is opened.
            final displayInstance =
                _buildDisplayTemplateInstance(itemId, itemName);
            if (displayInstance != null) {
              instances[itemId] = displayInstance;
            }
          } else {
            // Unknown or empty itemType — try the task/habit creation
            // path first; if that returns null (template), build a stub.
            try {
              final newInstance =
                  await RoutineService.createInstanceForRoutineItem(
                itemId: itemId,
                userId: userId,
              );
              if (newInstance != null) {
                instances[itemId] = newInstance;
              } else {
                final displayInstance =
                    _buildDisplayTemplateInstance(itemId, itemName);
                if (displayInstance != null) {
                  instances[itemId] = displayInstance;
                }
              }
            } catch (e) {}
          }
        }
        updatedRoutineWithInstances = RoutineWithInstances(
          routine: routine,
          instances: instances,
        );
      }
      if (mounted) {
        setState(() {
          _routineWithInstances = updatedRoutineWithInstances;
          _categories = allCategories;
          _isLoading = false;
        });
        _logRoutineSnapshot(
          'load_complete',
          updatedRoutineWithInstances?.instances ?? const {},
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _refreshRoutine() async {
    await _loadRoutineWithInstances();
  }

  ActivityInstanceRecord? _extractInstanceFromNotification(Object? param) {
    if (param is ActivityInstanceRecord) {
      return param;
    }
    if (param is Map && param['instance'] is ActivityInstanceRecord) {
      return param['instance'] as ActivityInstanceRecord;
    }
    return null;
  }

  bool _isOptimisticNotification(Object? param) {
    if (param is Map) {
      return param['isOptimistic'] as bool? ?? false;
    }
    return false;
  }

  bool _isStaleNonOptimisticUpdate({
    required ActivityInstanceRecord existing,
    required ActivityInstanceRecord incoming,
    required bool isOptimistic,
  }) {
    if (isOptimistic) return false;
    final incomingLastUpdated = incoming.lastUpdated;
    final existingLastUpdated = existing.lastUpdated;
    if (incomingLastUpdated != null && existingLastUpdated != null) {
      return incomingLastUpdated.isBefore(existingLastUpdated);
    }
    return false;
  }

  void _handleRoutineInstanceCreated(Object? param) {
    final createdInstance = _extractInstanceFromNotification(param);
    if (createdInstance == null) return;
    _logRoutineSync(
      'event_created',
      instance: createdInstance,
      isOptimistic: _isOptimisticNotification(param),
    );
    _applyRoutineInstanceUpdate(
      createdInstance,
      isOptimistic: _isOptimisticNotification(param),
    );
  }

  void _handleRoutineInstanceUpdated(Object? param) {
    final updatedInstance = _extractInstanceFromNotification(param);
    if (updatedInstance == null) return;
    _logRoutineSync(
      'event_updated',
      instance: updatedInstance,
      isOptimistic: _isOptimisticNotification(param),
    );
    _applyRoutineInstanceUpdate(
      updatedInstance,
      isOptimistic: _isOptimisticNotification(param),
    );
  }

  void _applyRoutineInstanceUpdate(
    ActivityInstanceRecord incoming, {
    required bool isOptimistic,
  }) {
    final routineWithInstances = _routineWithInstances;
    if (routineWithInstances == null) return;

    String? matchedTemplateId;
    ActivityInstanceRecord? existing;

    for (final entry in routineWithInstances.instances.entries) {
      if (entry.value.reference.id == incoming.reference.id) {
        matchedTemplateId = entry.key;
        existing = entry.value;
        break;
      }
    }

    matchedTemplateId ??= incoming.templateId;
    if (!routineWithInstances.routine.itemIds.contains(matchedTemplateId)) {
      _logRoutineSync(
        'apply_skip_not_in_routine',
        templateId: matchedTemplateId,
        instance: incoming,
        isOptimistic: isOptimistic,
      );
      return;
    }

    existing ??= routineWithInstances.instances[matchedTemplateId];

    // When the incoming instance is a *different* instance for the same
    // routine slot (e.g. completing today's habit triggers creation of
    // tomorrow's pending instance for the same template), don't blindly
    // replace the slot — re-pick via the same selector the initial load
    // uses, so today's completed instance keeps winning over tomorrow's
    // pending. Reconciled events run after TodayInstanceRepository (which
    // registers first) has applied them to its snapshot, so the picker
    // already sees the new candidate.
    if (!isOptimistic &&
        existing != null &&
        existing.reference.id != incoming.reference.id) {
      final repickedMap = TodayInstanceRepository.instance
          .selectRoutineItems(routine: routineWithInstances.routine);
      final repicked = repickedMap[matchedTemplateId];
      if (repicked != null) {
        if (repicked.reference.id == existing.reference.id &&
            repicked.lastUpdated == existing.lastUpdated &&
            repicked.status == existing.status) {
          _logRoutineSync(
            'apply_skip_repick_unchanged',
            templateId: matchedTemplateId,
            instance: incoming,
            isOptimistic: isOptimistic,
            note: 'existing=${existing.reference.id} keeps slot',
          );
          return;
        }
        setState(() {
          routineWithInstances.instances[matchedTemplateId!] = repicked;
        });
        _logRoutineSync(
          'apply_repick',
          templateId: matchedTemplateId,
          instance: repicked,
          isOptimistic: isOptimistic,
          note:
              'incoming=${incoming.reference.id}, picked=${repicked.reference.id}',
        );
        return;
      }
      // No repick result (e.g., essential created on-the-fly) — fall through
      // to the legacy stale check + replace path.
    }

    if (existing != null &&
        _isStaleNonOptimisticUpdate(
          existing: existing,
          incoming: incoming,
          isOptimistic: isOptimistic,
        )) {
      _logRoutineSync(
        'apply_skip_stale',
        templateId: matchedTemplateId,
        instance: incoming,
        isOptimistic: isOptimistic,
        note:
            'existing=${existing.reference.id}:${existing.currentValue}:${existing.lastUpdated?.millisecondsSinceEpoch}',
      );
      return;
    }

    setState(() {
      routineWithInstances.instances[matchedTemplateId!] = incoming;
    });
    _logRoutineSync(
      'apply_success',
      templateId: matchedTemplateId,
      instance: incoming,
      isOptimistic: isOptimistic,
    );
  }

  void _handleRoutineInstanceDeleted(Object? param) {
    final deletedInstance = _extractInstanceFromNotification(param);
    String? deletedId;
    if (deletedInstance != null) {
      deletedId = deletedInstance.reference.id;
    } else if (param is Map && param['instanceId'] is String) {
      deletedId = param['instanceId'] as String;
    }
    if (deletedId == null ||
        deletedId.isEmpty ||
        _routineWithInstances == null) {
      return;
    }
    final entry = _routineWithInstances!.instances.entries.firstWhereOrNull(
      (mapEntry) => mapEntry.value.reference.id == deletedId,
    );
    if (entry == null) return;

    setState(() {
      _routineWithInstances!.instances.remove(entry.key);
    });
    _logRoutineSync(
      'event_deleted',
      templateId: entry.key,
      instance: deletedInstance,
    );
  }

  void _handleRoutineRollback(Object? param) {
    if (param is! Map) return;
    final original = param['originalInstance'] as ActivityInstanceRecord?;
    if (original != null) {
      _logRoutineSync('event_rollback_restore', instance: original);
      _applyRoutineInstanceUpdate(original, isOptimistic: false);
      return;
    }
    final operationType = param['operationType'] as String?;
    final instanceId = param['instanceId'] as String?;
    if (operationType == 'create' &&
        instanceId != null &&
        instanceId.isNotEmpty) {
      _logRoutineSync(
        'event_rollback_create_remove',
        note: 'instanceId=$instanceId',
      );
      _handleRoutineInstanceDeleted({'instanceId': instanceId});
    }
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    super.dispose();
  }

  void _editRoutine() {
    final routineToEdit = _routineWithInstances?.routine ?? widget.routine;
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => CreateRoutinePage(
          existingRoutine: routineToEdit,
        ),
      ),
    )
        .then((result) {
      if (result is Map<String, dynamic> && result['itemIds'] != null) {
        final itemIds = List<String>.from(result['itemIds'] as List);
        final itemOrder = result['itemOrder'] != null
            ? List<String>.from(result['itemOrder'] as List)
            : itemIds;
        final itemNames = result['itemNames'] != null
            ? List<String>.from(result['itemNames'] as List)
            : null;
        final itemTypes = result['itemTypes'] != null
            ? List<String>.from(result['itemTypes'] as List)
            : null;
        final previousIds =
            _routineWithInstances?.routine.itemIds ?? <String>[];
        final itemsChanged = itemIds.length != previousIds.length ||
            !itemIds.every((id) => previousIds.contains(id)) ||
            !previousIds.every((id) => itemIds.contains(id));

        _applyRoutineEdit(itemIds, itemOrder, itemNames, itemTypes);
        if (itemsChanged) {
          _refreshRoutine();
        }
      }
    });
  }

  void _applyRoutineEdit(
    List<String> itemIds,
    List<String> itemOrder,
    List<String>? itemNames,
    List<String>? itemTypes,
  ) {
    if (_routineWithInstances == null) return;
    final currentRoutine = _routineWithInstances!.routine;
    final finalNames = itemNames ??
        itemOrder.map((id) {
          final index = currentRoutine.itemIds.indexOf(id);
          return index != -1 && index < currentRoutine.itemNames.length
              ? currentRoutine.itemNames[index]
              : 'Unknown Item';
        }).toList();

    final finalTypes = itemTypes ??
        itemOrder.map((id) {
          final index = currentRoutine.itemIds.indexOf(id);
          return index != -1 && index < currentRoutine.itemTypes.length
              ? currentRoutine.itemTypes[index]
              : 'habit';
        }).toList();

    final updatedData = Map<String, dynamic>.from(currentRoutine.snapshotData);
    updatedData['itemIds'] = itemIds;
    updatedData['itemOrder'] = itemOrder;
    updatedData['itemNames'] = finalNames;
    updatedData['itemTypes'] = finalTypes;
    updatedData['lastUpdated'] = DateTime.now();

    final updatedRoutine = RoutineRecord.getDocumentFromData(
      updatedData,
      currentRoutine.reference,
    );

    final filteredInstances = <String, ActivityInstanceRecord>{};
    for (final itemId in itemOrder) {
      if (_routineWithInstances!.instances.containsKey(itemId)) {
        filteredInstances[itemId] = _routineWithInstances!.instances[itemId]!;
      }
    }

    setState(() {
      _routineWithInstances = RoutineWithInstances(
        routine: updatedRoutine,
        instances: filteredInstances,
      );
    });
  }

  void _applyRoutineOrder(List<String> orderedIds) {
    _applyRoutineEdit(orderedIds, orderedIds, null, null);
  }

  Future<void> _onReorderItems(int oldIndex, int newIndex) async {
    if (_routineWithInstances == null) return;
    if (_isReordering) return;
    int adjustedNewIndex = newIndex;
    if (oldIndex < newIndex) {
      adjustedNewIndex -= 1;
    }

    final currentOrder =
        List<String>.from(_routineWithInstances!.routine.itemOrder);
    if (oldIndex < 0 ||
        oldIndex >= currentOrder.length ||
        adjustedNewIndex < 0 ||
        adjustedNewIndex >= currentOrder.length) {
      return;
    }

    final moved = currentOrder.removeAt(oldIndex);
    currentOrder.insert(adjustedNewIndex, moved);
    _applyRoutineOrder(currentOrder);
    setState(() => _isReordering = true);
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      await RoutineService.updateRoutine(
        routineId: _routineWithInstances!.routine.reference.id,
        userId: userId,
        itemIds: currentOrder,
        itemOrder: currentOrder,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error reordering routine items: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isReordering = false);
      }
    }
  }

  /// Hydrate [_templateCache] with ActivityRecord templates for every
  /// template/essential item referenced by the routine. Required so display
  /// stubs and the quick-log flow have full template metadata without a
  /// Firestore round-trip per render.
  Future<void> _hydrateTemplateCache(RoutineRecord routine) async {
    final templateItemIds = <String>{};
    for (int i = 0; i < routine.itemIds.length; i++) {
      final itemType =
          i < routine.itemTypes.length ? routine.itemTypes[i] : 'habit';
      if (itemType == 'template' || itemType == 'essential') {
        templateItemIds.add(routine.itemIds[i]);
      }
    }
    final missing = templateItemIds
        .where((id) => !_templateCache.containsKey(id))
        .toList();
    if (missing.isEmpty) return;
    final uid = await waitForCurrentUserUid();
    if (uid.isEmpty) return;
    try {
      final fetched = await BatchReadService.batchGetTemplates(
        templateIds: missing,
        userId: uid,
        useCache: true,
      );
      _templateCache.addAll(fetched);
    } catch (e) {
      debugPrint('[routine-template] _hydrateTemplateCache failed: $e');
    }
  }

  /// Build an in-memory display-only ActivityInstanceRecord for a template
  /// routine item. The ref id is prefixed with `display_` so action handlers
  /// know to materialize a real instance before mutating. Mirrors the
  /// pattern in essential_templates_page_logic.createDisplayInstance.
  ActivityInstanceRecord? _buildDisplayTemplateInstance(
      String itemId, String itemName) {
    final template = _templateCache[itemId];
    if (template == null) return null;
    final now = DateTime.now();
    final instanceData = <String, dynamic>{
      'templateId': template.reference.id,
      'status': 'pending',
      'createdTime': now,
      'lastUpdated': now,
      'isActive': true,
      'templateName': template.name.isNotEmpty ? template.name : itemName,
      'templateCategoryId': template.categoryId,
      'templateCategoryName': template.categoryName.isNotEmpty
          ? template.categoryName
          : 'Others',
      'templateCategoryType': template.categoryType,
      'templatePriority': template.priority,
      'templateTrackingType':
          template.trackingType.isNotEmpty ? template.trackingType : 'time',
      'templateTarget': template.target,
      'templateUnit': template.unit,
      'templateDescription': template.description,
      'templateShowInFloatingTimer': template.showInFloatingTimer,
      'templateIsRecurring': template.isRecurring,
      'templateTimeEstimateMinutes': template.timeEstimateMinutes,
      'templateDueTime': template.hasDueTime() ? template.dueTime : null,
      'dueDate': null,
      'timeLogSessions': const [],
      'totalTimeLogged': 0,
    };
    final ref = ActivityInstanceRecord.collectionForUser(currentUserUid)
        .doc('display_${template.reference.id}');
    return ActivityInstanceRecord.getDocumentFromData(instanceData, ref);
  }

  /// Quick-log a template: creates a real essential instance covering the
  /// last [estimate] minutes and marks it completed. Mirrors the Templates
  /// tab's quickLog. The new instance arrives via instanceCreated broadcast
  /// and replaces the display stub in the routine slot.
  Future<void> _quickLogTemplate(ActivityRecord template) async {
    final now = DateTime.now();
    int estimate = 1;
    if (template.hasTimeEstimateMinutes() &&
        template.timeEstimateMinutes! > 0) {
      estimate = template.timeEstimateMinutes!;
    } else if (_defaultTimeEstimateMinutes != null &&
        _defaultTimeEstimateMinutes! > 0) {
      estimate = _defaultTimeEstimateMinutes!;
    }
    final startTime = now.subtract(Duration(minutes: estimate));
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) throw Exception('User not signed in');
      await essentialService.createessentialInstance(
        templateId: template.reference.id,
        startTime: startTime,
        endTime: now,
        userId: userId,
      );
      // No success snackbar — the optimistic strike-through (for binary
      // taps) and the swapped-in real instance are the only feedback.
      // From the user's POV ticking a routine template feels identical
      // to ticking a regular task tile.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error logging activity: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// Show a scheduling menu for a template routine item. Picking a date
  /// creates a pending instance (`dueDate == picked`, `belongsToDate ==
  /// picked`) WITHOUT touching the template's own `dueDate` field, so
  /// scheduling from a routine never alters the template's defaults. The
  /// instance appears in the queue (dueDate is non-null) and in the
  /// routine slot for the matching day via the instanceCreated broadcast.
  Future<void> _showRoutineTemplateScheduleMenu(
      BuildContext anchorContext, ActivityRecord template) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero, ancestor: overlay);
    final size = box.size;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    // "Current dueDate" for the contextual menu = the dueDate on the
    // real instance currently held by this routine slot (if any). The
    // template's own dueDate is intentionally ignored — routine
    // scheduling lives on the instance, not the template.
    DateTime? currentInstanceDueDate;
    for (final entry
        in _routineWithInstances?.instances.entries ?? const <MapEntry<String, ActivityInstanceRecord>>[]) {
      final inst = entry.value;
      if (inst.templateId == template.reference.id &&
          !_isDisplayInstance(inst) &&
          inst.status == 'pending') {
        currentInstanceDueDate = inst.dueDate;
        break;
      }
    }
    final isDueToday = currentInstanceDueDate != null &&
        _isSameDay(currentInstanceDueDate, today);
    final isDueTomorrow = currentInstanceDueDate != null &&
        _isSameDay(currentInstanceDueDate, tomorrow);

    final items = <PopupMenuEntry<String>>[
      if (!isDueToday)
        const PopupMenuItem<String>(
            value: 'today',
            height: 32,
            child:
                Text('Schedule for today', style: TextStyle(fontSize: 12))),
      if (!isDueTomorrow)
        const PopupMenuItem<String>(
            value: 'tomorrow',
            height: 32,
            child: Text('Schedule for tomorrow',
                style: TextStyle(fontSize: 12))),
      const PopupMenuItem<String>(
          value: 'pick',
          height: 32,
          child: Text('Pick due date...', style: TextStyle(fontSize: 12))),
      if (currentInstanceDueDate != null) ...[
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
            value: 'clear',
            height: 32,
            child: Text('Clear due date', style: TextStyle(fontSize: 12))),
      ],
    ];

    final selected = await showMenu<String>(
      context: anchorContext,
      position: RelativeRect.fromLTRB(
        position.dx,
        position.dy + size.height,
        overlay.size.width - position.dx - size.width,
        overlay.size.height - position.dy,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: items,
    );

    if (selected == null || !mounted) return;

    DateTime? newDueDate;
    if (selected == 'today') {
      newDueDate = today;
    } else if (selected == 'tomorrow') {
      newDueDate = tomorrow;
    } else if (selected == 'pick') {
      newDueDate = await showDatePicker(
        context: context,
        initialDate: currentInstanceDueDate ?? today,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (newDueDate == null) return;
    } else if (selected == 'clear') {
      newDueDate = null;
    } else {
      return;
    }

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;
      // Deactivate any existing pending instances for this template (so a
      // re-schedule replaces the previous one) and, if a date was chosen,
      // create a new pending instance carrying that dueDate. This routes
      // through the same essential-service helper the Templates tab uses
      // for instance-side scheduling, just without the template-side
      // updateessentialTemplate call that would mutate the template's
      // default dueDate.
      await essentialService.managePendingInstanceForDueDate(
        templateId: template.reference.id,
        newDueDate: newDueDate,
        userId: userId,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating date: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _getCategoryColor(ActivityInstanceRecord instance) {
    final category = _categories
        .firstWhereOrNull((c) => c.name == instance.templateCategoryName);
    if (category == null) {
      return '#000000';
    }
    return category.color;
  }

  Widget _buildSectionHeader(String title, int count) {
    final theme = FlutterFlowTheme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        gradient: theme.neumorphicGradient,
        border: Border.all(
          color: theme.surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: theme.neumorphicShadowsRaised,
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            IconButton(
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back_ios),
              color: theme.primary,
              iconSize: 20,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          Icon(
            Icons.playlist_play,
            color: theme.primary,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: theme.titleMedium.override(
                fontWeight: FontWeight.w600,
                color: theme.primary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            onPressed: _editRoutine,
            icon: const Icon(Icons.edit),
            tooltip: 'Edit Routine',
            color: theme.secondaryText,
            iconSize: 20,
          ),
          const SizedBox(width: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _buildRoutineStatusSubtitle(ActivityInstanceRecord instance) {
    final status = instance.status.toLowerCase();
    if (status != 'completed' && status != 'skipped') {
      return '';
    }

    final isSkipped = status == 'skipped';
    final verb = isSkipped ? 'Skipped' : 'Completed';
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));

    DateTime? statusAt = isSkipped ? instance.skippedAt : instance.completedAt;
    statusAt ??= instance.lastUpdated;

    String whenLabel = '';
    if (statusAt != null) {
      if (_isSameDay(statusAt, now)) {
        whenLabel = 'Today';
      } else if (_isSameDay(statusAt, yesterday)) {
        whenLabel = 'Yesterday';
      } else {
        whenLabel = DateFormat.MMMd().format(statusAt);
      }
    }

    final due = instance.dueDate;
    final dueStr = due != null ? DateFormat.MMMd().format(due) : 'No due';
    final dueTime = instance.hasDueTime()
        ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
        : '';

    if (whenLabel.isEmpty) {
      return '$verb • Due: $dueStr$dueTime';
    }
    return '$verb $whenLabel • Due: $dueStr$dueTime';
  }

  Widget _buildItemComponent(ActivityInstanceRecord? instance, String itemId,
      String itemType, String itemName) {
    if (instance == null) {
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: FlutterFlowTheme.of(context).alternate,
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.info_outline,
              size: 18,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '$itemName: no active instance available right now.',
                style: FlutterFlowTheme.of(context).bodySmall,
              ),
            ),
          ],
        ),
      );
    }
    final categoryColor = instance.templateCategoryColor.isNotEmpty
        ? instance.templateCategoryColor
        : _getCategoryColor(instance);

    final isTemplateItem = instance.templateCategoryType == 'template' ||
        instance.templateCategoryType == 'essential';
    final template = isTemplateItem ? _templateCache[itemId] : null;
    final isTimeType = template?.trackingType == 'time';

    return ItemComponent(
      key: ValueKey(instance.reference.id),
      subtitle: _buildRoutineStatusSubtitle(instance),
      instance: instance,
      categoryColorHex: categoryColor,
      onRefresh:
          () async {}, // No-op — updates handled via onInstanceUpdated and NotificationCenter
      onInstanceUpdated: (updatedInstance) {
        // Allow updates targeting display stubs through — they're local
        // optimistic state (e.g. a binary tap that just marked the stub
        // completed) that needs to render immediately. The real instance
        // arrives separately via the instanceCreated broadcast and is
        // swapped in by _applyRoutineInstanceUpdate.
        setState(() {
          if (_routineWithInstances != null) {
            _routineWithInstances!.instances[itemId] = updatedInstance;
          }
        });
      },
      onInstanceDeleted: (deletedInstance) {
        setState(() {
          if (_routineWithInstances != null) {
            _routineWithInstances!.instances.remove(itemId);
          }
        });
      },
      onHabitUpdated: (updated) => {},
      onHabitDeleted: (deleted) async => _refreshRoutine(),
      isHabit: itemType == 'habit',
      showTypeIcon: true,
      showRecurringIcon: true,
      showCompleted: true,
      page: 'queue',
      showCalendar: true,
      showCalendarSkipOnly: true,
      showManagementActions: false,
      // Templates: surface a quick-log button as the primary action. For
      // display stubs the regular complete/progress controls would write
      // to a non-existent doc, so quick-log is the only safe path. For
      // real template instances we still expose it for convenience.
      forceShowActions: isTemplateItem,
      showQuickLogOnLeft: isTemplateItem && template != null,
      quickLogIcon: isTemplateItem && isTimeType
          ? Icons.play_circle_outline
          : null,
      onQuickLog: isTemplateItem && template != null
          ? () => _quickLogTemplate(template)
          : null,
      // Calendar tap on a template routes through the same schedule menu
      // the Templates tab uses: picking a date updates the template's
      // dueDate and creates a pending instance with that dueDate, which
      // then surfaces in the queue.
      onCalendarTapOverride: isTemplateItem && template != null
          ? (anchorCtx) =>
              _showRoutineTemplateScheduleMenu(anchorCtx, template)
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = _buildBodyContent();
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: Text(
          'Routine',
          style: FlutterFlowTheme.of(context).headlineMedium,
        ),
      ),
      body: body,
    );
  }

  Widget _buildBodyContent() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_routineWithInstances == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'Error loading routine',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Please try refreshing or check your connection',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refreshRoutine,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _buildSectionHeader(
            widget.routine.name,
            _routineWithInstances!.routine.itemIds.length,
          ),
        ),
        if (widget.routine.description.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: FlutterFlowTheme.of(context).secondaryBackground,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: FlutterFlowTheme.of(context).alternate,
                  width: 1,
                ),
              ),
              child: Text(
                widget.routine.description,
                style: FlutterFlowTheme.of(context).bodyMedium,
              ),
            ),
          ),
        SliverReorderableList(
          itemCount: _routineWithInstances!.routine.itemOrder.length,
          onReorder: _onReorderItems,
          itemBuilder: (context, index) {
            final itemId = _routineWithInstances!.routine.itemOrder[index];
            final instance = _routineWithInstances!.instances[itemId];
            final itemType =
                _routineWithInstances!.routine.itemTypes.isNotEmpty &&
                        index <
                            _routineWithInstances!.routine.itemTypes.length
                    ? _routineWithInstances!.routine.itemTypes[index]
                    : 'habit';
            final itemName =
                _routineWithInstances!.routine.itemNames.isNotEmpty &&
                        index <
                            _routineWithInstances!.routine.itemNames.length
                    ? _routineWithInstances!.routine.itemNames[index]
                    : 'Unknown Item';
            return ReorderableDelayedDragStartListener(
              key: ValueKey('routine_item_$itemId'),
              index: index,
              enabled: !_isReordering,
              child: _buildItemComponent(
                instance,
                itemId,
                itemType,
                itemName,
              ),
            );
          },
        ),
        if (_routineWithInstances!.missingInstances.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.info_outline,
                    color: Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Some items don\'t have instances for today. They may appear after day-end processing.',
                      style: FlutterFlowTheme.of(context)
                          .bodySmall
                          .override(
                            color: Colors.orange.shade700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SliverToBoxAdapter(
          child: SizedBox(height: 100),
        ),
      ],
    );
  }
}
