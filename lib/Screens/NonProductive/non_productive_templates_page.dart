import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_template_dialog.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/constants.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';
import 'package:habit_tracker/Helper/utils/item_component.dart';

class NonProductiveTemplatesPage extends StatefulWidget {
  const NonProductiveTemplatesPage({Key? key}) : super(key: key);

  @override
  _NonProductiveTemplatesPageState createState() =>
      _NonProductiveTemplatesPageState();
}

class _NonProductiveTemplatesPageState
    extends State<NonProductiveTemplatesPage> {
  List<ActivityRecord> _templates = [];
  bool _isLoading = true;
  static const List<String> _bottomTabNames = [
    'Tasks',
    'Habits',
    'Queue',
    'Routines',
    'Calendar'
  ];
  int _bottomNavIndex = 2;
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();

  @override
  void initState() {
    super.initState();
    _loadTemplates();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchManager.removeListener(_onSearchChanged);
    super.dispose();
  }

  void _onSearchChanged(String query) {
    if (mounted) {
      setState(() {
        _searchQuery = query;
      });
    }
  }

  List<ActivityRecord> get _filteredTemplates {
    if (_searchQuery.isEmpty) {
      return _templates;
    }
    final query = _searchQuery.toLowerCase();
    return _templates.where((template) {
      final nameMatch = template.name.toLowerCase().contains(query);
      final descriptionMatch = template.description.toLowerCase().contains(query);
      return nameMatch || descriptionMatch;
    }).toList();
  }

  Future<void> _loadTemplates() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final templates = await NonProductiveService.getNonProductiveTemplates(
        userId: currentUserUid,
      );
      setState(() {
        _templates = templates;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      if (mounted) {
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
    await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => NonProductiveTemplateDialog(
        onTemplateCreated: (template) {
          // Don't pop here - let the dialog handle navigation
          // Just refresh the list when dialog closes
        },
      ),
    );
    // Refresh templates after dialog closes (whether template was created or not)
    if (mounted) {
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
        await NonProductiveService.deleteNonProductiveTemplate(
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
      'templateCategoryName': template.categoryName.isNotEmpty ? template.categoryName : 'Non-Productive',
      'templateCategoryType': 'non_productive',
      'templatePriority': template.priority,
      'templateTrackingType': template.trackingType.isNotEmpty ? template.trackingType : 'time',
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
      builder: (context) => NonProductiveTemplateDialog(
        existingTemplate: template,
        onTemplateUpdated: (template) {
          Navigator.of(context).pop(template);
        },
      ),
    );
    if (result != null) {
      await _loadTemplates();
    }
  }

  Future<void> _showOverflowMenu(BuildContext context, ActivityRecord template) async {
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

  void _handleBottomNavTap(int index) {
    if (index < 0 || index >= _bottomTabNames.length) return;
    final targetPage = _bottomTabNames[index];
    bool reachedHome = false;
    Navigator.of(context).popUntil((route) {
      if (route.settings.name == home) {
        reachedHome = true;
        return true;
      }
      return false;
    });
    if (!reachedHome) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
    NotificationCenter.post('navigateBottomTab', targetPage);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: const Text('Non-Productive Items'),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _filteredTemplates.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.access_time,
                            size: 64,
                            color: FlutterFlowTheme.of(context).secondaryText,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _searchQuery.isNotEmpty
                                ? 'No Templates Found'
                                : 'No Non-Productive Templates',
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
                    )
                  : RefreshIndicator(
                      onRefresh: _loadTemplates,
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                        itemCount: _filteredTemplates.length,
                        itemBuilder: (context, index) {
                          final template = _filteredTemplates[index];
                          final displayInstance = _createDisplayInstance(template);
                          final timeEstimate = template.timeEstimateMinutes;
                          final timeEstimateText = _formatTimeEstimate(timeEstimate);
                          
                          return Stack(
                            clipBehavior: Clip.none,
                            children: [
                              // Main ItemComponent
                              ItemComponent(
                                key: Key('non_productive_template_${template.reference.id}'),
                                instance: displayInstance,
                                isHabit: false,
                                showTypeIcon: false,
                                showRecurringIcon: false,
                                showCompleted: false,
                                onRefresh: _loadTemplates,
                                onInstanceUpdated: _handleInstanceUpdated,
                                onInstanceDeleted: _handleInstanceDeleted,
                                onHabitUpdated: (updated) async {
                                  // For templates, refresh the list
                                  await _loadTemplates();
                                },
                                onHabitDeleted: (deleted) async {
                                  // Handle template deletion - this will be called
                                  // when ItemComponent's delete action is used
                                  _deleteTemplate(template);
                                },
                                categoryColorHex: null, // Non-productive uses grey
                              ),
                              // Overlay: Kebab menu icon and time estimate
                              // ItemComponent has margin: 16 horizontal, 2 vertical, and padding: 6 all around
                              Positioned.fill(
                                child: Padding(
                                  padding: const EdgeInsets.only(
                                    right: 16 + 6, // margin + padding
                                  ),
                                  child: Align(
                                    alignment: Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
                                        // Time estimate text
                                        if (timeEstimateText.isNotEmpty)
                                          Padding(
                                            padding: const EdgeInsets.only(right: 8),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withOpacity(0.9),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                timeEstimateText,
                                                style: FlutterFlowTheme.of(context).bodySmall.override(
                                                  fontFamily: 'Readex Pro',
                                                  color: FlutterFlowTheme.of(context).secondaryText,
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w500,
                                                ),
                                              ),
                                            ),
                                          ),
                                        // Kebab menu icon
                                        Builder(
                                          builder: (btnContext) => Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              onTap: () => _showOverflowMenu(btnContext, template),
                                              borderRadius: BorderRadius.circular(20),
                                              child: Container(
                                                padding: const EdgeInsets.all(6),
                                                child: Icon(
                                                  Icons.more_vert,
                                                  size: 20,
                                                  color: FlutterFlowTheme.of(context).secondaryText,
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
                          );
                        },
                      ),
                    ),
          // Search FAB at bottom-left
          const SearchFAB(heroTag: 'search_fab_non_productive'),
          // Existing FAB at bottom-right
          Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton(
              onPressed: _showCreateDialog,
              child: const Icon(Icons.add),
              tooltip: 'Create Non-Productive Template',
            ),
          ),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: FlutterFlowTheme.of(context).secondaryBackground,
          border: Border(
            top: BorderSide(
              color: FlutterFlowTheme.of(context).alternate,
              width: 1,
            ),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _bottomNavIndex,
          onTap: (index) {
            if (!mounted) return;
            setState(() {
              _bottomNavIndex = index;
            });
            _handleBottomNavTap(index);
          },
          type: BottomNavigationBarType.fixed,
          backgroundColor:
              FlutterFlowTheme.of(context).secondaryBackground,
          selectedItemColor: FlutterFlowTheme.of(context).primary,
          unselectedItemColor: FlutterFlowTheme.of(context).secondaryText,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.assignment),
              label: 'Tasks',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.flag),
              label: 'Habits',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.queue),
              label: 'Queue',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.playlist_play),
              label: 'Routines',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.calendar_today),
              label: 'Calendar',
            ),
          ],
        ),
      ),
    );
  }
}
