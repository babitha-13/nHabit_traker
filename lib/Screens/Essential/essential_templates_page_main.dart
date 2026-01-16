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
import 'package:habit_tracker/Screens/Shared/Search/search_fab.dart';
import 'package:habit_tracker/Screens/Item_component/item_component_main.dart';
import 'package:habit_tracker/Screens/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/Screens/Categories/create_category.dart';
import 'package:habit_tracker/Helper/Helpers/Activtity_services/task_instance_service.dart';
import 'package:habit_tracker/Screens/Settings/default_time_estimates_service.dart';

class essentialTemplatesPage extends StatefulWidget {
  const essentialTemplatesPage({Key? key}) : super(key: key);

  @override
  _essentialTemplatesPageState createState() => _essentialTemplatesPageState();
}

class _essentialTemplatesPageState extends State<essentialTemplatesPage> {
  List<ActivityRecord> _templates = [];
  List<CategoryRecord> _categories = [];
  Set<String> _expandedCategories = {};
  final Map<String, GlobalKey> _categoryKeys = {};
  bool _isLoading = true;
  bool _hasAutoExpandedOnLoad = false;
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Cache for groupedByCategory to avoid recalculation on every build
  Map<String, List<ActivityRecord>>? _cachedGroupedByCategory;
  int _templatesHashCode = 0;
  String _lastSearchQuery = '';
  Map<String, int> _todayCounts = {};
  Map<String, int> _todayMinutes = {};
  int? _defaultTimeEstimateMinutes;
  bool _isLoadingData = false; // Guard against concurrent loads

  @override
  void initState() {
    super.initState();
    _loadExpansionState();
    _loadTemplates();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _loadTemplates();
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    _searchManager.removeListener(_onSearchChanged);
    super.dispose();
  }

  Future<void> _loadExpansionState() async {
    final expandedSections =
        await ExpansionStateManager().getEssentialExpandedSections();
    if (mounted) {
      setState(() {
        _expandedCategories = expandedSections;
      });
    }
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
        // Invalidate cache when search query changes
        _cachedGroupedByCategory = null;
        // Auto-expand categories with results when searching
        if (_searchQuery.isNotEmpty) {
          final grouped = groupedByCategory;
          // Expand all categories with results
          for (final key in grouped.keys) {
            if (grouped[key]!.isNotEmpty) {
              _expandedCategories.add(key);
            }
          }
        }
      });
    }
  }

  /// Load today's stats and return the data (for parallel loading)
  Future<Map<String, dynamic>> _loadTodayStatsData() async {
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

  Future<void> _loadTodayStats() async {
    final data = await _loadTodayStatsData();
    if (mounted) {
      setState(() {
        _todayCounts = data['counts'] as Map<String, int>;
        _todayMinutes = data['minutes'] as Map<String, int>;
      });
    }
  }

  Future<void> _quickLog(ActivityRecord template) async {
    final now = DateTime.now();
    // Use template's time estimate or default to system preference duration
    int estimate = 1; // absolute fallback
    if (template.hasTimeEstimateMinutes() &&
        template.timeEstimateMinutes! > 0) {
      estimate = template.timeEstimateMinutes!;
    } else if (_defaultTimeEstimateMinutes != null &&
        _defaultTimeEstimateMinutes! > 0) {
      // Use the default duration loaded from settings
      estimate = _defaultTimeEstimateMinutes!;
    }

    final startTime = now.subtract(Duration(minutes: estimate));

    try {
      await essentialService.createessentialInstance(
        templateId: template.reference.id,
        startTime: startTime,
        endTime: now,
        userId: currentUserUid,
      );

      // Refresh to update counts
      await _loadTodayStats();

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

  Map<String, List<ActivityRecord>> get groupedByCategory {
    // Check if cache is still valid (hash is calculated when data changes, not here)
    final cacheInvalid = _cachedGroupedByCategory == null ||
        _templatesHashCode == 0 || // Hash not calculated yet
        _searchQuery != _lastSearchQuery;

    if (!cacheInvalid && _cachedGroupedByCategory != null) {
      return _cachedGroupedByCategory!;
    }

    // Recalculate grouping
    final grouped = <String, List<ActivityRecord>>{};
    // Filter templates by search query if active
    final templatesToProcess = _templates.where((template) {
      if (_searchQuery.isEmpty) return true;
      return template.name.toLowerCase().contains(_searchQuery.toLowerCase());
    }).toList();
    for (final template in templatesToProcess) {
      final categoryName =
          template.categoryName.isNotEmpty ? template.categoryName : 'Others';
      (grouped[categoryName] ??= []).add(template);
    }
    // Sort items within each category by name
    for (final key in grouped.keys) {
      final items = grouped[key]!;
      if (items.isNotEmpty) {
        grouped[key] = items..sort((a, b) => a.name.compareTo(b.name));
      }
    }

    // Update cache
    _cachedGroupedByCategory = grouped;
    _lastSearchQuery = _searchQuery;

    return grouped;
  }

  List<ActivityRecord> get _filteredTemplates {
    if (_searchQuery.isEmpty) {
      return _templates;
    }
    final query = _searchQuery.toLowerCase();
    return _templates.where((template) {
      final nameMatch = template.name.toLowerCase().contains(query);
      final descriptionMatch =
          template.description.toLowerCase().contains(query);
      return nameMatch || descriptionMatch;
    }).toList();
  }

  Future<void> _loadTemplates() async {
    if (!mounted) return;
    // Guard against concurrent loads
    if (_isLoadingData) return;
    _isLoadingData = true;
    
    // Only set loading state if it's not already true
    if (!_isLoading) {
      setState(() {
        _isLoading = true;
      });
    }
    try {
      // Load default time estimate from preferences first (needed for quick log)
      _defaultTimeEstimateMinutes =
          await TimeLoggingPreferencesService.getDefaultDurationMinutes(
              currentUserUid);

      // Load templates, categories, and today stats in parallel for faster data loading
      final results = await Future.wait([
        essentialService.getessentialTemplates(
          userId: currentUserUid,
        ),
        queryEssentialCategoriesOnce(
          userId: currentUserUid,
          callerTag: 'essentialTemplatesPage._loadTemplates',
        ),
        _loadTodayStatsData(),
      ]);
      if (!mounted) {
        _isLoadingData = false;
        return;
      }
      
      final templates = results[0] as List<ActivityRecord>;
      final categories = results[1] as List<CategoryRecord>;
      final statsData = results[2] as Map<String, dynamic>;
      final todayCounts = statsData['counts'] as Map<String, int>;
      final todayMinutes = statsData['minutes'] as Map<String, int>;
      
      // Calculate hash code when data changes (not in getter)
      final newHash = templates.length.hashCode ^
          templates.fold(0, (sum, t) => sum ^ t.reference.id.hashCode);
      
      if (mounted) {
        setState(() {
          _templates = templates;
          _categories = categories;
          _todayCounts = todayCounts;
          _todayMinutes = todayMinutes;
          // Invalidate cache when data changes
          _cachedGroupedByCategory = null;
          // Update hash code when data changes
          _templatesHashCode = newHash;
          _isLoading = false;
        });
        // Auto-expand first category only on initial load if no sections are expanded
        if (!_hasAutoExpandedOnLoad && _templates.isNotEmpty) {
          _hasAutoExpandedOnLoad = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _expandedCategories.isEmpty) {
              final grouped = groupedByCategory;
              if (grouped.isNotEmpty) {
                setState(() {
                  _expandedCategories.add(grouped.keys.first);
                });
                ExpansionStateManager()
                    .setEssentialExpandedSections(_expandedCategories);
              }
            }
          });
        }
      }
      _isLoadingData = false;
    } catch (e) {
      _isLoadingData = false;
      // Batch state updates for error case
      if (mounted) {
        setState(() {
          _isLoading = false;
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

  Future<void> _showCreateDialog() async {
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: null,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: _categories,
      ),
    );
    // Refresh templates after dialog closes if template was created
    if (result != null && mounted) {
      await _loadTemplates();
    }
  }

  Future<void> _deleteTemplate(ActivityRecord template) async {
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
          await _loadTemplates();
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

  /// Create a display instance from a template for ItemComponent rendering
  ActivityInstanceRecord _createDisplayInstance(ActivityRecord template) {
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

    // Create a dummy document reference for display purposes
    final dummyRef = ActivityInstanceRecord.collectionForUser(currentUserUid)
        .doc('display_${template.reference.id}');

    return ActivityInstanceRecord.getDocumentFromData(instanceData, dummyRef);
  }

  /// Format time estimate for display
  String _formatTimeEstimate(int? minutes) {
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

  Future<void> _showEditDialog(ActivityRecord template) async {
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => ActivityEditorDialog(
        activity: template,
        isHabit: false, // Essentials are not habits
        isEssential: true,
        categories: _categories,
      ),
    );
    if (result != null && mounted) {
      await _loadTemplates();
    }
  }

  Future<void> _showOverflowMenu(
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
      await _showEditDialog(template);
    } else if (selected == 'delete') {
      await _deleteTemplate(template);
    }
  }

  void _handleInstanceUpdated(ActivityInstanceRecord instance) {
    // For templates page, instance updates don't apply
    // This is just for ItemComponent compatibility
  }

  void _handleInstanceDeleted(ActivityInstanceRecord instance) {
    // Extract template ID from instance and delete template
    final templateId = instance.templateId;
    if (templateId.isNotEmpty) {
      try {
        final template = _templates.firstWhere(
          (t) => t.reference.id == templateId,
        );
        _deleteTemplate(template);
      } catch (e) {
        // Template not found, ignore
      }
    }
  }

  Widget _buildGroupedTemplatesView() {
    final groupedTemplates = groupedByCategory;
    if (groupedTemplates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.monitor_heart,
              size: 64,
              color: FlutterFlowTheme.of(context).secondaryText,
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No Templates Found'
                  : 'No essential Templates',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'Try a different search term'
                  : 'Create templates to track time for activities like sleep, travel, and rest',
              style: FlutterFlowTheme.of(context).bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }
    final slivers = <Widget>[];
    for (final categoryName in groupedTemplates.keys) {
      final templates = groupedTemplates[categoryName]!;
      CategoryRecord? category;
      try {
        category = _categories.firstWhere((c) => c.name == categoryName);
      } catch (e) {
        // Category not found, create a dummy one
        category = CategoryRecord.getDocumentFromData(
          {
            'name': categoryName,
            'color': '#808080',
            'categoryType': 'essential',
            'isActive': true,
          },
          FirebaseFirestore.instance.collection('categories').doc(),
        );
      }
      final expanded = _expandedCategories.contains(categoryName);
      // Get or create GlobalKey for this category
      if (!_categoryKeys.containsKey(categoryName)) {
        _categoryKeys[categoryName] = GlobalKey();
      }
      slivers.add(
        SliverToBoxAdapter(
          child: _buildCategoryHeader(category, expanded, categoryName,
              templates.length, _categoryKeys[categoryName]!),
        ),
      );
      if (expanded) {
        for (final template in templates) {
          final displayInstance = _createDisplayInstance(template);
          final timeEstimate = template.timeEstimateMinutes;
          final timeEstimateText = _formatTimeEstimate(timeEstimate);
          slivers.add(
            SliverToBoxAdapter(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  // Main ItemComponent
                  ItemComponent(
                    key: Key('essential_template_${template.reference.id}'),
                    instance: displayInstance,
                    isHabit: false,
                    showTypeIcon: false,
                    showRecurringIcon: false,
                    showCompleted: false,
                    onRefresh: _loadTemplates,
                    onInstanceUpdated: _handleInstanceUpdated,
                    onInstanceDeleted: _handleInstanceDeleted,
                    onHabitUpdated: (updated) async {
                      await _loadTemplates();
                    },
                    onHabitDeleted: (deleted) async {
                      _deleteTemplate(template);
                    },
                    categoryColorHex: category.color,
                    showQuickLogOnLeft: true,
                    onQuickLog: () => _quickLog(template),
                  ),
                  // Overlay: Kebab menu icon and time estimate
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 16 + 6),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            if (_todayCounts.containsKey(template.reference.id))
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '${_todayCounts[template.reference.id]}x (${_todayMinutes[template.reference.id]}m)',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontFamily: 'Readex Pro',
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                ),
                              ),
                            if (timeEstimateText.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.9),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    timeEstimateText,
                                    style: FlutterFlowTheme.of(context)
                                        .bodySmall
                                        .override(
                                          fontFamily: 'Readex Pro',
                                          color: FlutterFlowTheme.of(context)
                                              .secondaryText,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                  ),
                                ),
                              ),
                            Builder(
                              builder: (btnContext) => Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () =>
                                      _showOverflowMenu(btnContext, template),
                                  borderRadius: BorderRadius.circular(20),
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    child: Icon(
                                      Icons.more_vert,
                                      size: 20,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
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
          );
        }
      }
    }
    return CustomScrollView(
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
          bottomLeft: const Radius.circular(16),
          bottomRight: const Radius.circular(16),
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
                    _expandedCategories.remove(categoryName);
                  } else {
                    _expandedCategories.add(categoryName);
                  }
                });
                ExpansionStateManager()
                    .setEssentialExpandedSections(_expandedCategories);
                if (_expandedCategories.contains(categoryName)) {
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
      builder: (context) => CreateCategory(
        category: category,
        categoryType: 'essential',
      ),
    ).then((value) {
      if (value != null && value != false) {
        _loadTemplates();
      }
    });
  }

  void _showDeleteCategoryConfirmation(CategoryRecord category) {
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
                await _loadTemplates();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16.0, 6.0, 16.0, 0),
                        child: Text(
                          'Essential activities track time but do not earn points.',
                          style: FlutterFlowTheme.of(context)
                              .bodySmall
                              .override(
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                                fontStyle: FontStyle.italic,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Expanded(
                        child: _filteredTemplates.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.monitor_heart,
                                      size: 64,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No Templates Found'
                                          : 'No essential Templates',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Create templates to track time for activities like sleep, travel, and rest',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : RefreshIndicator(
                                onRefresh: _loadTemplates,
                                child: _buildGroupedTemplatesView(),
                              ),
                      ),
                    ],
                  ),
            // Search FAB at bottom-left
            const SearchFAB(heroTag: 'search_fab_essential'),
            // Existing FAB at bottom-right
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag: 'fab_add_essential',
                onPressed: _showCreateDialog,
                child: const Icon(Icons.add),
                tooltip: 'Create Essential Template',
              ),
            ),
          ],
        ),
      ),
    );
  }
}
