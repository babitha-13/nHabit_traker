import 'dart:async';

import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/features/Essential/essential_data_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/features/activity%20editor/presentation/activity_editor_dialog.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/features/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/features/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/features/Categories/Create%20Category/create_category.dart';
import 'package:habit_tracker/services/Activtity/today_instances/today_instance_repository.dart';
import 'package:habit_tracker/features/Settings/default_time_estimates_service.dart';
import 'package:habit_tracker/services/template_timer_service.dart';

mixin EssentialTemplatesPageLogic<T extends StatefulWidget> on State<T> {
  List<ActivityRecord> templates = [];
  List<CategoryRecord> categories = [];
  Set<String> expandedCategories = {};
  bool isLoading = true;
  bool hasAutoExpandedOnLoad = false;
  String searchQuery = '';
  final SearchStateManager searchManager = SearchStateManager();
  Map<String, List<ActivityRecord>>? cachedGroupedByCategory;
  int templatesHashCode = 0;
  String lastSearchQuery = '';
  Map<String, int> todayCounts = {};
  Map<String, int> todayMinutes = {};
  int? defaultTimeEstimateMinutes;
  bool isLoadingData = false;

  // Timer tick — drives elapsed time display for time-type templates
  Timer? _tickTimer;

  final _timerService = TemplateTimerService.instance;

  bool isTemplateTimerRunning(String templateId) =>
      _timerService.isRunning(templateId);

  String timerElapsedDisplay(String templateId) =>
      _timerService.elapsedDisplay(templateId);

  void cancelTickTimer() => _tickTimer?.cancel();

  void _startTickTimer() {
    _tickTimer?.cancel();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _timerService.hasAnyRunning) {
        setState(() {});
      } else {
        _tickTimer?.cancel();
        _tickTimer = null;
      }
    });
  }

  void startTemplateTimer(ActivityRecord template) {
    _timerService.start(template.reference.id);
    _startTickTimer();
    if (mounted) setState(() {});
  }

  Future<void> stopTemplateTimer(ActivityRecord template) async {
    final startTime = _timerService.stop(template.reference.id);
    if (startTime == null) return;
    final endTime = DateTime.now();
    final templateId = template.reference.id;

    if (mounted) setState(() {});

    unawaited(() async {
      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) throw Exception('User not signed in');
        await essentialService.createessentialInstance(
          templateId: templateId,
          startTime: startTime,
          endTime: endTime,
          userId: userId,
        );
        final elapsed = endTime.difference(startTime);
        if (mounted) {
          setState(() {
            todayCounts[templateId] = (todayCounts[templateId] ?? 0) + 1;
            todayMinutes[templateId] =
                (todayMinutes[templateId] ?? 0) + elapsed.inMinutes;
          });
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Logged ${template.name} (${elapsed.inMinutes}m ${elapsed.inSeconds % 60}s)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ));
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Error logging activity: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }());
  }

  int _computeTemplatesHash(List<ActivityRecord> records) {
    return records.length.hashCode ^
        records.fold(0, (sum, t) => sum ^ t.reference.id.hashCode);
  }

  int _findTemplateIndex({
    required String templateId,
    String? optimisticOperationId,
  }) {
    return templates.indexWhere((t) {
      if (t.reference.id == templateId) return true;
      if (optimisticOperationId == null) return false;
      return t.snapshotData['optimisticOperationId'] == optimisticOperationId;
    });
  }

  ActivityRecord _stripOptimisticMetadata(ActivityRecord record) {
    final cleanedData = Map<String, dynamic>.from(record.snapshotData)
      ..remove('optimisticOperationId')
      ..remove('optimisticPending')
      ..remove('optimisticFailed')
      ..remove('optimisticError');
    return ActivityRecord.getDocumentFromData(cleanedData, record.reference);
  }

  void _handleOptimisticTemplateSave(ActivityRecord? record) {
    if (!mounted || record == null) return;

    final operationId = record.snapshotData['optimisticOperationId'] as String?;
    final optimisticFailed = record.snapshotData['optimisticFailed'] == true;
    final optimisticPending = record.snapshotData['optimisticPending'] == true;
    final optimisticError = record.snapshotData['optimisticError'] as String?;
    final isTempTemplate = record.reference.id.startsWith('tmp_essential_');
    final matchIndex = _findTemplateIndex(
      templateId: record.reference.id,
      optimisticOperationId: operationId,
    );

    if (optimisticFailed) {
      setState(() {
        if (isTempTemplate) {
          if (matchIndex >= 0) {
            templates.removeAt(matchIndex);
          }
        } else {
          final rollbackRecord = _stripOptimisticMetadata(record);
          if (matchIndex >= 0) {
            templates[matchIndex] = rollbackRecord;
          } else {
            templates.add(rollbackRecord);
          }
        }
        cachedGroupedByCategory = null;
        templatesHashCode = _computeTemplatesHash(templates);
      });

      if (optimisticError != null && optimisticError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $optimisticError'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() {
      final templateToApply =
          optimisticPending ? record : _stripOptimisticMetadata(record);
      if (matchIndex >= 0) {
        templates[matchIndex] = templateToApply;
      } else {
        templates.add(templateToApply);
      }
      cachedGroupedByCategory = null;
      templatesHashCode = _computeTemplatesHash(templates);
    });
  }

  Future<void> loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getEssentialExpandedSections();
    if (mounted) {
      setState(() {
        expandedCategories = expandedSections;
      });
    }
    // Restart tick timer if a timer was running before the user navigated away
    if (_timerService.hasAnyRunning) _startTickTimer();
  }

  void onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        searchQuery = query;
        cachedGroupedByCategory = null;
        if (searchQuery.isNotEmpty) {
          final grouped = getGroupedByCategory();
          for (final key in grouped.keys) {
            if (grouped[key]!.isNotEmpty) {
              expandedCategories.add(key);
            }
          }
        }
      });
    }
  }

  Future<Map<String, dynamic>> loadTodayStatsData() async {
    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        return {'counts': <String, int>{}, 'minutes': <String, int>{}};
      }

      final repo = TodayInstanceRepository.instance;
      await repo.ensureHydrated(userId: userId);
      final statsByTemplate = repo.selectEssentialTodayStatsByTemplate();
      final counts = <String, int>{};
      final minutes = <String, int>{};
      statsByTemplate.forEach((templateId, stats) {
        counts[templateId] = stats['count'] ?? 0;
        minutes[templateId] = stats['minutes'] ?? 0;
      });

      return {'counts': counts, 'minutes': minutes};
    } catch (e) {
      print('Error loading today stats: $e');
      return {'counts': <String, int>{}, 'minutes': <String, int>{}};
    }
  }

  Future<void> loadTodayStats() async {
    final data = await loadTodayStatsData();
    if (mounted) {
      setState(() {
        todayCounts = data['counts'] as Map<String, int>;
        todayMinutes = data['minutes'] as Map<String, int>;
      });
    }
  }

  Future<void> quickLog(ActivityRecord template) async {
    final now = DateTime.now();
    int estimate = 1; // absolute fallback
    if (template.hasTimeEstimateMinutes() &&
        template.timeEstimateMinutes! > 0) {
      estimate = template.timeEstimateMinutes!;
    } else if (defaultTimeEstimateMinutes != null &&
        defaultTimeEstimateMinutes! > 0) {
      estimate = defaultTimeEstimateMinutes!;
    }

    final startTime = now.subtract(Duration(minutes: estimate));
    final templateId = template.reference.id;

    if (mounted) {
      setState(() {
        todayCounts[templateId] = (todayCounts[templateId] ?? 0) + 1;
        todayMinutes[templateId] = (todayMinutes[templateId] ?? 0) + estimate;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logged ${template.name} (${estimate}m)'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 1),
        ),
      );
    }

    unawaited(() async {
      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) throw Exception('User not signed in');
        await essentialService.createessentialInstance(
          templateId: templateId,
          startTime: startTime,
          endTime: now,
          userId: userId,
        );
      } catch (e) {
        if (!mounted) return;
        setState(() {
          final nextCount = (todayCounts[templateId] ?? 0) - 1;
          final nextMinutes = (todayMinutes[templateId] ?? 0) - estimate;
          if (nextCount <= 0) {
            todayCounts.remove(templateId);
          } else {
            todayCounts[templateId] = nextCount;
          }
          if (nextMinutes <= 0) {
            todayMinutes.remove(templateId);
          } else {
            todayMinutes[templateId] = nextMinutes;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }());
  }

  Map<String, List<ActivityRecord>> getGroupedByCategory() {
    final cacheInvalid = cachedGroupedByCategory == null ||
        templatesHashCode == 0 || // Hash not calculated yet
        searchQuery != lastSearchQuery;

    if (!cacheInvalid && cachedGroupedByCategory != null) {
      return cachedGroupedByCategory!;
    }
    final grouped = <String, List<ActivityRecord>>{};
    final templatesToProcess = templates.where((template) {
      if (searchQuery.isEmpty) return true;
      return template.name.toLowerCase().contains(searchQuery.toLowerCase());
    }).toList();
    for (final template in templatesToProcess) {
      final categoryName =
          template.categoryName.isNotEmpty ? template.categoryName : 'Others';
      (grouped[categoryName] ??= []).add(template);
    }
    for (final key in grouped.keys) {
      final items = grouped[key]!;
      if (items.isNotEmpty) {
        grouped[key] = items..sort((a, b) => a.name.compareTo(b.name));
      }
    }
    cachedGroupedByCategory = grouped;
    lastSearchQuery = searchQuery;

    return grouped;
  }

  List<ActivityRecord> getFilteredTemplates() {
    if (searchQuery.isEmpty) {
      return templates;
    }
    final query = searchQuery.toLowerCase();
    return templates.where((template) {
      final nameMatch = template.name.toLowerCase().contains(query);
      final descriptionMatch =
          template.description.toLowerCase().contains(query);
      return nameMatch || descriptionMatch;
    }).toList();
  }

  Future<void> loadTemplates({bool silent = false}) async {
    if (!mounted) return;
    if (isLoadingData) return;
    isLoadingData = true;
    if (!isLoading && !silent) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      final uid = await waitForCurrentUserUid();
      if (uid.isEmpty) {
        isLoadingData = false;
        if (mounted) {
          setState(() {
            isLoading = false;
          });
        }
        return;
      }
      defaultTimeEstimateMinutes =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(uid);
      final results = await Future.wait([
        essentialService.getessentialTemplates(
          userId: uid,
        ),
        queryEssentialCategoriesOnce(
          userId: uid,
          callerTag: 'essentialTemplatesPage._loadTemplates',
        ),
        loadTodayStatsData(),
      ]);
      if (!mounted) {
        isLoadingData = false;
        return;
      }

      final templatesResult = results[0] as List<ActivityRecord>;
      final categoriesResult = results[1] as List<CategoryRecord>;
      final statsData = results[2] as Map<String, dynamic>;
      final todayCountsResult = statsData['counts'] as Map<String, int>;
      final todayMinutesResult = statsData['minutes'] as Map<String, int>;
      final newHash = _computeTemplatesHash(templatesResult);

      if (mounted) {
        setState(() {
          templates = templatesResult;
          categories = categoriesResult;
          todayCounts = todayCountsResult;
          todayMinutes = todayMinutesResult;
          cachedGroupedByCategory = null;
          templatesHashCode = newHash;
          isLoading = false;
        });
        if (!hasAutoExpandedOnLoad && templates.isNotEmpty) {
          hasAutoExpandedOnLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && expandedCategories.isEmpty) {
              final grouped = getGroupedByCategory();
              if (grouped.isNotEmpty) {
                setState(() {
                  expandedCategories.add(grouped.keys.first);
                });
                ExpansionStateManager()
                    .setEssentialExpandedSections(expandedCategories);
              }
            }
          });
        }
      }
      isLoadingData = false;
    } catch (e) {
      isLoadingData = false;
      if (mounted) {
        setState(() {
          isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading templates: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> showCreateDialog() async {
    await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: null,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: categories,
        onSave: _handleOptimisticTemplateSave,
      ),
    );
  }

  Future<void> deleteTemplate(ActivityRecord template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Template'),
        content: Text(
          'Are you sure you want to delete "${template.name}"?\n\nThis will also mark all associated instances as inactive.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        final userId = await waitForCurrentUserUid();
        if (userId.isEmpty) return;
        await essentialService.deleteessentialTemplate(
          templateId: template.reference.id,
          userId: userId,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Template deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );
          await loadTemplates();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error deleting template: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  ActivityInstanceRecord createDisplayInstance(ActivityRecord template) {
    final now = DateTime.now();
    final instanceData = {
      'templateId': template.reference.id,
      'status': 'pending',
      'createdTime': now,
      'lastUpdated': now,
      'isActive': true,
      'templateName': template.name,
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
      'dueDate': template.dueDate,
      'timeLogSessions': [],
      'totalTimeLogged': 0,
    };

    final dummyRef = ActivityInstanceRecord.collectionForUser(currentUserUid)
        .doc('display_${template.reference.id}');

    return ActivityInstanceRecord.getDocumentFromData(instanceData, dummyRef);
  }

  String formatTimeEstimate(int? minutes) {
    if (minutes == null || minutes <= 0) return '';
    if (minutes < 60) {
      return '$minutes min';
    }
    final hours = minutes ~/ 60;
    final remainingMinutes = minutes % 60;
    if (remainingMinutes == 0) {
      return '$hours ${hours == 1 ? 'hour' : 'hours'}';
    }
    return '$hours ${hours == 1 ? 'hour' : 'hours'} $remainingMinutes min';
  }

  Future<void> showEditDialog(ActivityRecord template) async {
    await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: template,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: categories,
        onSave: _handleOptimisticTemplateSave,
      ),
    );
  }

  Future<void> showOverflowMenu(
      BuildContext context, ActivityRecord template) async {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = box.localToGlobal(Offset.zero);
    final size = box.size;

    final selected = await showMenu<String>(
      context: context,
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
          child: Text('Edit', style: TextStyle(fontSize: 12)),
        ),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Text('Delete', style: TextStyle(fontSize: 12)),
        ),
      ],
    );

    if (selected == null) return;

    if (selected == 'edit') {
      await showEditDialog(template);
    } else if (selected == 'delete') {
      await deleteTemplate(template);
    }
  }

  void handleInstanceUpdated(ActivityInstanceRecord instance) {
    final templateId = instance.templateId;
    if (templateId.isEmpty) return;
    final idx = templates.indexWhere((t) => t.reference.id == templateId);
    if (idx < 0) return;
    final old = templates[idx];
    final updatedData = Map<String, dynamic>.from(old.snapshotData)
      ..['priority'] = instance.templatePriority;
    setState(() {
      templates[idx] = ActivityRecord.getDocumentFromData(updatedData, old.reference);
      cachedGroupedByCategory = null;
    });
  }

  void handleInstanceDeleted(ActivityInstanceRecord instance) {
    final templateId = instance.templateId;
    if (templateId.isNotEmpty) {
      try {
        final template = templates.firstWhere(
          (t) => t.reference.id == templateId,
        );
        deleteTemplate(template);
      } catch (e) {}
    }
  }

  /// Show a date quick-picker for a template (Today / Tomorrow / Pick / Clear).
  /// Operates on the ActivityRecord's dueDate (not the synthetic display instance).
  Future<void> showTemplateDateMenu(
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
    final currentDueDate = template.dueDate;
    final isDueToday =
        currentDueDate != null && _isSameDay(currentDueDate, today);
    final isDueTomorrow =
        currentDueDate != null && _isSameDay(currentDueDate, tomorrow);

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
          child:
              Text('Pick due date...', style: TextStyle(fontSize: 12))),
      if (currentDueDate != null) ...[
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
        initialDate: currentDueDate ?? today,
        firstDate: today,
        lastDate: today.add(const Duration(days: 365 * 5)),
      );
      if (newDueDate == null) return;
    } else if (selected == 'clear') {
      newDueDate = null;
    } else {
      return;
    }

    // Optimistic: update the local list immediately so the icon/subtitle reflects
    // the new date without waiting for the Firestore round-trip.
    final idx = templates.indexWhere(
        (t) => t.reference.id == template.reference.id);
    if (idx >= 0 && mounted) {
      final updated = Map<String, dynamic>.from(templates[idx].snapshotData)
        ..['dueDate'] = newDueDate;
      setState(() {
        templates[idx] = ActivityRecord.getDocumentFromData(
            updated, templates[idx].reference);
        cachedGroupedByCategory = null;
      });
    }

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) return;

      await essentialService.updateessentialTemplate(
        templateId: template.reference.id,
        dueDate: newDueDate,
        userId: userId,
      );
      await essentialService.managePendingInstanceForDueDate(
        templateId: template.reference.id,
        newDueDate: newDueDate,
        userId: userId,
      );
      await loadTemplates(silent: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error updating date: $e'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void handleCategoryMenuAction(String action, CategoryRecord category) {
    switch (action) {
      case 'edit':
        showEditCategoryDialog(category);
        break;
      case 'delete':
        showDeleteCategoryConfirmation(category);
        break;
    }
  }

  void showEditCategoryDialog(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => CreateCategory(
        category: category,
        categoryType: 'template',
      ),
    ).then((value) {
      if (value != null && value != false) {
        loadTemplates();
      }
    });
  }

  void showDeleteCategoryConfirmation(CategoryRecord category) {
    if (category.isSystemCategory) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System categories cannot be deleted'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Category'),
        content: Text(
          'Are you sure you want to delete "${category.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              try {
                final userId = await waitForCurrentUserUid();
                if (userId.isEmpty) return;
                await deleteCategory(category.reference.id, userId: userId);
                await loadTemplates();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                          'Category "${category.name}" deleted successfully!'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error deleting category: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
