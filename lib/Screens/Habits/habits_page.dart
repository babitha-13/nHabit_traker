import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/notification_center_broadcast.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/instance_optimistic_update.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_state_manager.dart';
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Screens/Categories/Create%20Category/create_category.dart';
import 'package:habit_tracker/Screens/Shared/Activity_create_edit/activity_editor_dialog.dart';
import 'package:habit_tracker/Screens/Item_component/item_component_main.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'dart:async';
import 'dart:convert';
import '../../debug_log_stub.dart'
    if (dart.library.io) '../../debug_log_io.dart'
    if (dart.library.html) '../../debug_log_web.dart';

import 'package:habit_tracker/Screens/Habits/Logic/habits_page_logic.dart';

class HabitsPage extends StatefulWidget {
  final bool showCompleted;
  const HabitsPage({super.key, required this.showCompleted});
  @override
  _HabitsPageState createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> with HabitsPageLogic {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _categoryKeys = {};
  @override
  void initState() {
    super.initState();
    showCompleted = widget.showCompleted;
    Future.wait([
      loadExpansionState(),
      loadHabits(),
    ]);
    searchManager.addListener(onSearchChanged);
    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        // Only update if value actually changed
        if (showCompleted != param) {
          setState(() {
            showCompleted = param;
            cachedGroupedByCategory = null;
          });
        }
      }
    });
    NotificationCenter.addObserver(this, 'loadHabits', (param) {
      if (mounted) {
        loadHabits();
      }
    });
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        loadHabitsSilently();
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          param.templateCategoryType == 'habit') {
        handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (mounted) {
        ActivityInstanceRecord? instance;
        if (param is Map) {
          instance = param['instance'] as ActivityInstanceRecord?;
        } else if (param is ActivityInstanceRecord) {
          instance = param;
        }
        if (instance != null && instance.templateCategoryType == 'habit') {
          handleInstanceUpdated(param);
        }
      }
    });
    NotificationCenter.addObserver(this, 'instanceUpdateRollback', (param) {
      if (mounted) {
        handleRollback(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          param.templateCategoryType == 'habit') {
        handleInstanceDeleted(param);
      }
    });
  }

  @override
  void reassemble() {
    super.reassemble();
    logReassemble('called');
    NotificationCenter.removeObserver(this);
    logReassemble('complete');
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    searchManager.removeListener(onSearchChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && shouldReloadOnReturn) {
        shouldReloadOnReturn = false;
        loadHabits();
      }
    } else {
      didInitialDependencies = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildAllHabitsView(),
            const SearchFAB(heroTag: 'search_fab_habits'),
            Positioned(
              right: 16,
              bottom: 16,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FloatingActionButton(
                    heroTag: 'fab_add_habit',
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (context) => ActivityEditorDialog(
                          isHabit: true,
                          categories: categories,
                          onSave: (record) {
                            if (record != null) {
                              NotificationCenter.post("loadHabits", "");
                            }
                          },
                        ),
                      );
                    },
                    tooltip: 'Add Habit',
                    backgroundColor: FlutterFlowTheme.of(context).primary,
                    child: const Icon(Icons.add, color: Colors.white),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllHabitsView() {
    final groupedHabits = getGroupedByCategory();
    if (groupedHabits.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.list_alt,
              size: 64,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              'No habits found',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Create your first habit to get started!',
              style: FlutterFlowTheme.of(context).bodyMedium,
            ),
          ],
        ),
      );
    }
    final slivers = <Widget>[];
    for (final categoryName in groupedHabits.keys) {
      final habits = groupedHabits[categoryName]!;
      CategoryRecord? category;
      try {
        category = categories.firstWhere((c) => c.name == categoryName);
      } catch (e) {
        final categoryData = createCategoryRecordData(
          name: categoryName,
          color: '#2196F3',
          userId: currentUserUid,
          isActive: true,
          weight: 1.0,
          createdTime: DateTime.now(),
          lastUpdated: DateTime.now(),
          categoryType: 'habit',
        );
        category = CategoryRecord.getDocumentFromData(
          categoryData,
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }
      final expanded = expandedCategories.contains(categoryName);
      // Get or create GlobalKey for this category
      if (!_categoryKeys.containsKey(categoryName)) {
        _categoryKeys[categoryName] = GlobalKey();
      }
      slivers.add(
        SliverToBoxAdapter(
          child: _buildCategoryHeader(category, expanded, categoryName,
              habits.length, _categoryKeys[categoryName]!),
        ),
      );
      if (expanded) {
        final sortedHabits = List<ActivityInstanceRecord>.from(habits);
        slivers.add(
          SliverReorderableList(
            itemBuilder: (context, index) {
              final instance = sortedHabits[index];
              return ReorderableDelayedDragStartListener(
                index: index,
                key: Key('${instance.reference.id}_drag'),
                child: ItemComponent(
                  key: Key(instance.reference.id),
                  subtitle: getDueDateSubtitle(instance),
                  showCompleted: showCompleted,
                  instance: instance,
                  categoryColorHex: category!.color,
                  onRefresh: loadHabits,
                  onInstanceUpdated: updateInstanceInLocalState,
                  onInstanceDeleted: removeInstanceFromLocalState,
                  isHabit: true,
                  showTypeIcon: false,
                  showRecurringIcon: false,
                ),
              );
            },
            itemCount: sortedHabits.length,
            itemExtent:
                85.0, // Approximate item height for better scroll performance
            onReorder: (oldIndex, newIndex) =>
                handleReorder(oldIndex, newIndex, categoryName),
          ),
        );
      }
    }
    return RefreshIndicator(
      onRefresh: loadHabits,
      child: CustomScrollView(
        controller: _scrollController,
        cacheExtent:
            500.0, // Cache 500px worth of items above/below viewport for better scroll performance
        slivers: [
          ...slivers,
          const SliverToBoxAdapter(
            child: SizedBox(height: 140),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryHeader(CategoryRecord category, bool expanded,
      String categoryName, int itemCount, GlobalKey headerKey) {
    return Container(
      key: headerKey,
      margin: EdgeInsets.fromLTRB(16, 8, 16, expanded ? 0 : 6),
      padding: EdgeInsets.fromLTRB(12, 8, 12, expanded ? 2 : 6),
      decoration: BoxDecoration(
        gradient: FlutterFlowTheme.of(context).neumorphicGradient,
        border: Border.all(
          color: FlutterFlowTheme.of(context).surfaceBorderColor,
          width: 1,
        ),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(16),
          topRight: const Radius.circular(16),
          bottomLeft:
              expanded ? const Radius.circular(12) : const Radius.circular(16),
          bottomRight:
              expanded ? const Radius.circular(12) : const Radius.circular(16),
        ),
        boxShadow: expanded
            ? []
            : FlutterFlowTheme.of(context).neumorphicShadowsRaised,
      ),
      child: Row(
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                category.name,
                style: FlutterFlowTheme.of(context).titleMedium.override(
                      fontFamily: 'Readex Pro',
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Color(
                      int.parse(category.color.replaceFirst('#', '0xFF'))),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: FlutterFlowTheme.of(context).primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$itemCount',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: FlutterFlowTheme.of(context).primary,
                  ),
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(
            height: 20,
            width: 20,
            child: PopupMenuButton<String>(
              padding: EdgeInsets.zero,
              menuPadding: EdgeInsets.zero,
              tooltip: 'Category options',
              icon: Icon(
                Icons.more_vert,
                size: 20,
                color: FlutterFlowTheme.of(context).secondaryText,
              ),
              onSelected: (value) => handleCategoryMenuAction(value, category),
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      const Icon(Icons.edit, size: 16),
                      const SizedBox(width: 5),
                      const Text('Edit category'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, size: 16, color: Colors.red),
                      const SizedBox(width: 5),
                      const Text('Delete category',
                          style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              if (mounted) {
                setState(() {
                  if (expanded) {
                    expandedCategories.remove(categoryName);
                  } else {
                    expandedCategories.add(categoryName);
                  }
                });
                // Save state persistently
                ExpansionStateManager()
                    .setHabitsExpandedSections(expandedCategories);
                // Scroll to make the newly expanded section visible
                if (expandedCategories.contains(categoryName)) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (headerKey.currentContext != null) {
                      Scrollable.ensureVisible(
                        headerKey.currentContext!,
                        duration: Duration.zero,
                        alignment: 0.0,
                        alignmentPolicy:
                            ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
                      );
                    }
                  });
                }
              }
            },
            child: Icon(
              expanded ? Icons.expand_less : Icons.expand_more,
              size: 28,
            ),
          ),
        ],
      ),
    );
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
      builder: (context) => CreateCategory(category: category),
    ).then((value) {
      if (value != null && value != false) {
        loadHabits();
      }
    });
  }

  void showDeleteCategoryConfirmation(CategoryRecord category) {
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
                await loadHabits();
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
