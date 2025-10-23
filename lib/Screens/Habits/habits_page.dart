import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/instance_events.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Screens/Create%20Catagory/create_category.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';
import 'package:habit_tracker/Helper/utils/expansion_state_manager.dart';
import 'package:habit_tracker/Helper/backend/instance_order_service.dart';
import 'package:habit_tracker/Helper/utils/window_display_helper.dart';
import 'package:habit_tracker/Helper/utils/time_utils.dart';
import 'dart:async';
import 'package:intl/intl.dart';

class HabitsPage extends StatefulWidget {
  final bool showCompleted;
  const HabitsPage({super.key, required this.showCompleted});

  @override
  _HabitsPageState createState() => _HabitsPageState();
}

class _HabitsPageState extends State<HabitsPage> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _scrollController = ScrollController();
  List<ActivityInstanceRecord> _habitInstances = [];
  List<CategoryRecord> _categories = [];
  String? _expandedCategory;
  final Map<String, GlobalKey> _categoryKeys = {};
  bool _isLoading = true;
  bool _didInitialDependencies = false;
  bool _shouldReloadOnReturn = false;
  late bool _showCompleted;
  bool _hasAutoExpandedOnLoad = false;

  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();

  @override
  void initState() {
    super.initState();
    _showCompleted = widget.showCompleted;
    _loadExpansionState();
    _loadHabits();

    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);

    NotificationCenter.addObserver(this, 'showCompleted', (param) {
      if (param is bool && mounted) {
        setState(() {
          _showCompleted = param;
        });
      }
    });
    NotificationCenter.addObserver(this, 'loadHabits', (param) {
      if (mounted) {
        setState(() {
          _loadHabits();
        });
      }
    });

    // Listen for instance events (only habit instances)
    NotificationCenter.addObserver(this, InstanceEvents.instanceCreated,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          param.templateCategoryType == 'habit') {
        _handleInstanceCreated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceUpdated,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          param.templateCategoryType == 'habit') {
        _handleInstanceUpdated(param);
      }
    });
    NotificationCenter.addObserver(this, InstanceEvents.instanceDeleted,
        (param) {
      if (param is ActivityInstanceRecord &&
          mounted &&
          param.templateCategoryType == 'habit') {
        _handleInstanceDeleted(param);
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitialDependencies) {
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent && _shouldReloadOnReturn) {
        _shouldReloadOnReturn = false;
        _loadHabits();
      }
    } else {
      _didInitialDependencies = true;
    }
  }

  Future<void> _loadExpansionState() async {
    final expandedSection =
        await ExpansionStateManager().getHabitsExpandedSection();
    if (mounted) {
      setState(() {
        _expandedCategory = expandedSection;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;

        // Auto-expand first category with results when searching
        if (_searchQuery.isNotEmpty) {
          final grouped = groupedByCategory;

          // Expand first category with results
          for (final key in grouped.keys) {
            if (grouped[key]!.isNotEmpty) {
              _expandedCategory = key;
              break;
            }
          }
        }
      });
    }
  }

  Map<String, List<ActivityInstanceRecord>> get groupedByCategory {
    final grouped = <String, List<ActivityInstanceRecord>>{};

    // Filter instances by search query if active
    final instancesToProcess = _habitInstances.where((instance) {
      if (_searchQuery.isEmpty) return true;
      return instance.templateName
          .toLowerCase()
          .contains(_searchQuery.toLowerCase());
    }).toList();

    for (final instance in instancesToProcess) {
      if (!_showCompleted && instance.status == 'completed') continue;
      final categoryName = instance.templateCategoryName.isNotEmpty
          ? instance.templateCategoryName
          : 'Uncategorized';
      (grouped[categoryName] ??= []).add(instance);
    }

    // Sort items within each category by habits order
    for (final key in grouped.keys) {
      final items = grouped[key]!;
      if (items.isNotEmpty) {
        // Initialize order values for items that don't have them
        InstanceOrderService.initializeOrderValues(items, 'habits');
        // Sort by habits order
        grouped[key] =
            InstanceOrderService.sortInstancesByOrder(items, 'habits');
      }
    }

    return grouped;
  }

  String _getDueDateSubtitle(ActivityInstanceRecord instance) {
    // For habits with completion windows, show window information
    if (WindowDisplayHelper.hasCompletionWindow(instance)) {
      if (instance.status == 'completed' || instance.status == 'skipped') {
        return WindowDisplayHelper.getNextWindowStartSubtitle(instance);
      } else {
        return WindowDisplayHelper.getWindowEndSubtitle(instance);
      }
    }

    // Fall back to original logic for habits without windows
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));

    if (instance.dueDate == null) {
      // Even if no due date, show time if available
      if (instance.hasDueTime()) {
        return '@ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}';
      }
      return 'No due date';
    }

    final dueDate = DateTime(
        instance.dueDate!.year, instance.dueDate!.month, instance.dueDate!.day);

    String dateStr;
    if (dueDate.isAtSameMomentAs(today)) {
      dateStr = 'Today';
    } else if (dueDate.isAtSameMomentAs(tomorrow)) {
      dateStr = 'Tomorrow';
    } else {
      dateStr = DateFormat.yMMMd().format(instance.dueDate!);
    }

    // Add due time if available
    final timeStr = instance.hasDueTime()
        ? ' @ ${TimeUtils.formatTimeForDisplay(instance.dueTime)}'
        : '';

    return '$dateStr$timeStr';
  }

  Future<void> _loadHabits() async {
    setState(() => _isLoading = true);
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final instances = await queryLatestHabitInstances(userId: userId);
        final categories = await queryHabitCategoriesOnce(userId: userId);
        if (mounted) {
          setState(() {
            _habitInstances = instances;
            _categories = categories;
            _isLoading = false;
          });

          // Auto-expand first category only on initial load
          if (!_hasAutoExpandedOnLoad && _habitInstances.isNotEmpty) {
            _hasAutoExpandedOnLoad = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && _expandedCategory == null) {
                final grouped = groupedByCategory;
                if (grouped.isNotEmpty) {
                  setState(() {
                    _expandedCategory = grouped.keys.first;
                  });
                  ExpansionStateManager()
                      .setHabitsExpandedSection(_expandedCategory);
                }
              }
            });
          }
        }
      } else {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      print('Error loading habits: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildAllHabitsView(),
          // FloatingTimer(
          //   activeHabits: _activeFloatingHabits,
          //   onRefresh: _loadHabits,
          //   onHabitUpdated: (updated) => {}, // _updateHabitInLocalState(updated),
          // ),
        ],
      ),
    );
  }

  // List<ActivityRecord> get _activeFloatingHabits {
  //   // TODO: Re-implement with instances
  //   return [];
  // }

  Widget _buildAllHabitsView() {
    final groupedHabits = groupedByCategory;

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
        category = _categories.firstWhere((c) => c.name == categoryName);
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

      final expanded = _expandedCategory == categoryName;

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
                  subtitle: _getDueDateSubtitle(instance),
                  showCompleted: _showCompleted,
                  instance: instance,
                  categoryColorHex: category!.color,
                  onRefresh: _loadHabits,
                  onInstanceUpdated: _updateInstanceInLocalState,
                  onInstanceDeleted: _removeInstanceFromLocalState,
                  isHabit: true,
                  showTypeIcon: false,
                  showRecurringIcon: false,
                ),
              );
            },
            itemCount: sortedHabits.length,
            onReorder: (oldIndex, newIndex) =>
                _handleReorder(oldIndex, newIndex, categoryName),
          ),
        );
      }
    }

    return CustomScrollView(
      controller: _scrollController,
      slivers: [
        ...slivers,
        const SliverToBoxAdapter(
          child: SizedBox(height: 140),
        ),
      ],
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
          bottomLeft: expanded ? Radius.zero : const Radius.circular(16),
          bottomRight: expanded ? Radius.zero : const Radius.circular(16),
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
              onSelected: (value) => _handleCategoryMenuAction(value, category),
              itemBuilder: (context) => [
                const PopupMenuItem<String>(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 16),
                      SizedBox(width: 5),
                      Text('Edit category'),
                    ],
                  ),
                ),
                const PopupMenuItem<String>(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 16, color: Colors.red),
                      SizedBox(width: 5),
                      Text('Delete category',
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
                    // Collapse current section
                    _expandedCategory = null;
                  } else {
                    // Expand this section (accordion behavior)
                    _expandedCategory = categoryName;
                  }
                });
                // Save state persistently
                ExpansionStateManager()
                    .setHabitsExpandedSection(_expandedCategory);

                // Scroll to make the newly expanded section visible
                if (_expandedCategory == categoryName) {
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

  void _handleCategoryMenuAction(String action, CategoryRecord category) {
    switch (action) {
      case 'edit':
        _showEditCategoryDialog(category);
        break;
      case 'delete':
        _showDeleteCategoryConfirmation(category);
        break;
    }
  }

  void _showEditCategoryDialog(CategoryRecord category) {
    showDialog(
      context: context,
      builder: (context) => CreateCategory(category: category),
    );
  }

  void _updateInstanceInLocalState(ActivityInstanceRecord updatedInstance) {
    setState(() {
      final index = _habitInstances.indexWhere(
          (inst) => inst.reference.id == updatedInstance.reference.id);
      if (index != -1) {
        _habitInstances[index] = updatedInstance;
      }
      // Remove from list if completed and not showing completed
      if (!_showCompleted && updatedInstance.status == 'completed') {
        _habitInstances.removeWhere(
            (inst) => inst.reference.id == updatedInstance.reference.id);
      }
    });
    // Background refresh to sync with server
    _loadHabitsSilently();
  }

  void _removeInstanceFromLocalState(ActivityInstanceRecord deletedInstance) {
    setState(() {
      _habitInstances.removeWhere(
          (inst) => inst.reference.id == deletedInstance.reference.id);
    });
    // Background refresh to sync with server
    _loadHabitsSilently();
  }

  Future<void> _loadHabitsSilently() async {
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final instances = await queryCurrentHabitInstances(userId: userId);
        if (mounted) {
          setState(() {
            _habitInstances = instances;
          });
        }
      }
    } catch (e) {
      print('Error silently loading habits: $e');
    }
  }

  void _showDeleteCategoryConfirmation(CategoryRecord category) {
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
                await _loadHabits();

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
                print('Error deleting category: $e');
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

  // Event handlers for live updates (habit instances only)
  void _handleInstanceCreated(ActivityInstanceRecord instance) {
    setState(() {
      _habitInstances.add(instance);
    });
    print('HabitsPage: Added new habit instance ${instance.templateName}');
  }

  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    setState(() {
      final index = _habitInstances
          .indexWhere((inst) => inst.reference.id == instance.reference.id);
      if (index != -1) {
        _habitInstances[index] = instance;
        print('HabitsPage: Updated habit instance ${instance.templateName}');
      }
      // Remove from list if completed and not showing completed
      if (!_showCompleted && instance.status == 'completed') {
        _habitInstances
            .removeWhere((inst) => inst.reference.id == instance.reference.id);
        print(
            'HabitsPage: Removed completed habit instance ${instance.templateName}');
      }
    });
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    setState(() {
      _habitInstances
          .removeWhere((inst) => inst.reference.id == instance.reference.id);
    });
    print('HabitsPage: Removed habit instance ${instance.templateName}');
  }

  /// Handle reordering of items within a category
  Future<void> _handleReorder(
      int oldIndex, int newIndex, String categoryName) async {
    try {
      final groupedHabits = groupedByCategory;
      final items = groupedHabits[categoryName]!;

      if (oldIndex >= items.length || newIndex >= items.length) return;

      // Create a copy of the items list for reordering
      final reorderedItems = List<ActivityInstanceRecord>.from(items);

      // Adjust newIndex for the case where we're moving down
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }

      // Get the item being moved
      final movedItem = reorderedItems.removeAt(oldIndex);
      reorderedItems.insert(adjustedNewIndex, movedItem);

      // OPTIMISTIC UI UPDATE: Update local state immediately
      // Update order values in the local _habitInstances list
      for (int i = 0; i < reorderedItems.length; i++) {
        final instance = reorderedItems[i];

        // Create updated instance with new habits order
        final updatedData = Map<String, dynamic>.from(instance.snapshotData);
        updatedData['habitsOrder'] = i;
        final updatedInstance = ActivityInstanceRecord.getDocumentFromData(
          updatedData,
          instance.reference,
        );

        // Update in _habitInstances
        final habitIndex = _habitInstances
            .indexWhere((inst) => inst.reference.id == instance.reference.id);
        if (habitIndex != -1) {
          _habitInstances[habitIndex] = updatedInstance;
        }
      }

      // Trigger setState to update UI immediately (eliminates twitch)
      if (mounted) {
        setState(() {
          // State is already updated above
        });
      }

      // Perform database update in background
      await InstanceOrderService.reorderInstancesInSection(
        reorderedItems,
        'habits',
        oldIndex,
        newIndex,
      );

      print('HabitsPage: Reordered items in category $categoryName');
    } catch (e) {
      print('HabitsPage: Error reordering items: $e');
      // Revert to correct state by refreshing data
      await _loadHabits();
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reordering items: $e')),
        );
      }
    }
  }
}
