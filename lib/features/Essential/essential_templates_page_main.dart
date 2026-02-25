import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/category_record.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:habit_tracker/services/Activtity/instance_optimistic_update.dart';
import 'package:habit_tracker/services/Activtity/notification_center_broadcast.dart';
import 'package:habit_tracker/features/Shared/Search/search_fab.dart';
import 'package:habit_tracker/features/Item_component/presentation/item_component_main.dart';
import 'package:habit_tracker/features/Shared/section_expansion_state_manager.dart';
import 'package:habit_tracker/features/Essential/Logic/essential_templates_page_logic.dart';

class essentialTemplatesPage extends StatefulWidget {
  const essentialTemplatesPage({Key? key}) : super(key: key);

  @override
  _essentialTemplatesPageState createState() => _essentialTemplatesPageState();
}

class _essentialTemplatesPageState extends State<essentialTemplatesPage>
    with EssentialTemplatesPageLogic {
  final Map<String, GlobalKey> _categoryKeys = {};

  ActivityInstanceRecord? _extractInstanceFromEvent(Object? param) {
    if (param is ActivityInstanceRecord) return param;
    if (param is Map && param['instance'] is ActivityInstanceRecord) {
      return param['instance'] as ActivityInstanceRecord;
    }
    return null;
  }

  void _handleEssentialInstanceChange(Object? param) {
    if (!mounted) return;
    final instance = _extractInstanceFromEvent(param);
    if (instance == null) return;
    if (instance.templateCategoryType != 'essential') return;
    loadTodayStats();
  }

  void _handleInstanceRollback(Object? param) {
    if (!mounted) return;
    loadTodayStats();
  }

  @override
  void initState() {
    super.initState();
    loadExpansionState();
    loadTemplates();
    // Listen for search changes
    searchManager.addListener(onSearchChanged);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        loadTemplates();
      }
    });
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceCreated,
      _handleEssentialInstanceChange,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceUpdated,
      _handleEssentialInstanceChange,
    );
    NotificationCenter.addObserver(
      this,
      InstanceEvents.instanceDeleted,
      _handleEssentialInstanceChange,
    );
    NotificationCenter.addObserver(
      this,
      'instanceUpdateRollback',
      _handleInstanceRollback,
    );
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
    searchManager.removeListener(onSearchChanged);
    super.dispose();
  }

  Widget _buildGroupedTemplatesView() {
    final groupedTemplates = getGroupedByCategory();
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
              searchQuery.isNotEmpty
                  ? 'No Templates Found'
                  : 'No essential Templates',
              style: FlutterFlowTheme.of(context).titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              searchQuery.isNotEmpty
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
        category = categories.firstWhere((c) => c.name == categoryName);
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
      final expanded = expandedCategories.contains(categoryName);
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
          final displayInstance = createDisplayInstance(template);
          final timeEstimate = template.timeEstimateMinutes;
          final timeEstimateText = formatTimeEstimate(timeEstimate);
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
                    onRefresh: loadTemplates,
                    onInstanceUpdated: handleInstanceUpdated,
                    onInstanceDeleted: handleInstanceDeleted,
                    onHabitUpdated: (updated) async {
                      await loadTemplates();
                    },
                    onHabitDeleted: (deleted) async {
                      deleteTemplate(template);
                    },
                    categoryColorHex: category.color,
                    showQuickLogOnLeft: true,
                    onQuickLog: () => quickLog(template),
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
                            if (todayCounts.containsKey(template.reference.id))
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '${todayCounts[template.reference.id]}x (${todayMinutes[template.reference.id]}m)',
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
                                      showOverflowMenu(btnContext, template),
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
    return RefreshIndicator(
      onRefresh: loadTemplates,
      child: CustomScrollView(
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
              onSelected: (value) => handleCategoryMenuAction(value, category),
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
                    expandedCategories.remove(categoryName);
                  } else {
                    expandedCategories.add(categoryName);
                  }
                });
                ExpansionStateManager()
                    .setEssentialExpandedSections(expandedCategories);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            isLoading
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
                        child: getFilteredTemplates().isEmpty
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
                                      searchQuery.isNotEmpty
                                          ? 'No Templates Found'
                                          : 'No essential Templates',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Create templates to track time for activities like sleep, travel, and rest',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              )
                            : _buildGroupedTemplatesView(),
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
                onPressed: showCreateDialog,
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
