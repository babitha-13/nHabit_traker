import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Screens/Essential/essential_data_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/activity_editor_dialog.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/Screens/Categories/create_category.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/task_instance_service.dart';
import 'package:habit_tracker/Screens/Settings/default_time_estimates_service.dart';

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
  bool isLoadingData = false; // Guard against concurrent loads

  Future<void> loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getEssentialExpandedSections();
    if (mounted) {
      setState(() {
        expandedCategories = expandedSections;
      });
    }
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
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final instances = await TaskInstanceService.getessentialInstances(
        userId: currentUserUid,
        startDate: startOfDay,
        endDate: endOfDay,
      );

      final counts = <String, int>{};
      final minutes = <String, int>{};

      for (final inst in instances) {
        final templateId = inst.templateId;
        if (templateId.isNotEmpty) {
          counts[templateId] = (counts[templateId] ?? 0) + 1;
          minutes[templateId] =
              (minutes[templateId] ?? 0) + (inst.totalTimeLogged ~/ 60000);
        }
      }

      return {
        'counts': counts,
        'minutes': minutes,
      };
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

    try {
      await essentialService.createessentialInstance(
        templateId: template.reference.id,
        startTime: startTime,
        endTime: now,
        userId: currentUserUid,
      );
      await loadTodayStats();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Logged ${template.name} (${estimate}m)'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error logging activity: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
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

  Future<void> loadTemplates() async {
    if (!mounted) return;
    if (isLoadingData) return;
    isLoadingData = true;
    if (!isLoading) {
      setState(() {
        isLoading = true;
      });
    }
    try {
      defaultTimeEstimateMinutes =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(currentUserUid);
      final results = await Future.wait([
        essentialService.getessentialTemplates(
          userId: currentUserUid,
        ),
        queryEssentialCategoriesOnce(
          userId: currentUserUid,
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
      final newHash = templatesResult.length.hashCode ^
          templatesResult.fold(0, (sum, t) => sum ^ t.reference.id.hashCode);
      
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
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: null,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: categories,
      ),
    );
    if (result != null && mounted) {
      await loadTemplates();
    }
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
        await essentialService.deleteessentialTemplate(
          templateId: template.reference.id,
          userId: currentUserUid,
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
          : 'essential',
      'templateCategoryType': 'essential',
      'templatePriority': template.priority,
      'templateTrackingType':
          template.trackingType.isNotEmpty ? template.trackingType : 'time',
      'templateTarget': template.target,
      'templateUnit': template.unit,
      'templateDescription': template.description,
      'templateShowInFloatingTimer': template.showInFloatingTimer,
      'templateIsRecurring': template.isRecurring,
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
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: template,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: categories,
      ),
    );
    if (result != null && mounted) {
      await loadTemplates();
    }
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
      items: [
        const PopupMenuItem<String>(
          value: 'edit',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.edit, size: 20),
              SizedBox(width: 8),
              Text('Edit'),
            ],
          ),
        ),
        const PopupMenuDivider(height: 6),
        const PopupMenuItem<String>(
          value: 'delete',
          height: 32,
          child: Row(
            children: [
              Icon(Icons.delete, size: 20, color: Colors.red),
              SizedBox(width: 8),
              Text('Delete', style: TextStyle(color: Colors.red)),
            ],
          ),
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
    // For templates page, instance updates don't apply
    // This is just for ItemComponent compatibility
  }

  void handleInstanceDeleted(ActivityInstanceRecord instance) {
    final templateId = instance.templateId;
    if (templateId.isNotEmpty) {
      try {
        final template = templates.firstWhere(
          (t) => t.reference.id == templateId,
        );
        deleteTemplate(template);
      } catch (e) {
      }
    }
  }

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
        categoryType: 'essential',
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
                await deleteCategory(category.reference.id,
                    userId: currentUserUid);
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
