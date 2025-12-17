import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/non_productive_service.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_template_dialog.dart';
import 'package:habit_tracker/Screens/Timer/timer_page.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';

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
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => NonProductiveTemplateDialog(
        onTemplateCreated: (template) {
          Navigator.of(context).pop(template);
        },
      ),
    );
    if (result != null) {
      await _loadTemplates();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: const Text('Non-Productive Items'),
      ),
      body: Stack(
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
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredTemplates.length,
                        itemBuilder: (context, index) {
                          final template = _filteredTemplates[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Play button to start timer
                                IconButton(
                                  icon: const Icon(Icons.play_arrow, color: Colors.green),
                                  onPressed: () {
                                    // Navigate to Timer Page with this template
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => TimerPage(
                                          taskTitle: template.name,
                                          isNonProductive: true,
                                        ),
                                      ),
                                    );
                                  },
                                  tooltip: 'Start Timer',
                                ),
                                const SizedBox(width: 8),
                                // Icon for non-productive item
                                Container(
                                  width: 40,
                                  height: 40,
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: const Icon(
                                    Icons.access_time,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                              ],
                            ),
                            title: Text(
                              template.name,
                              style: FlutterFlowTheme.of(context).titleMedium,
                            ),
                            subtitle: template.description.isNotEmpty
                                ? Text(
                                    template.description,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            trailing: PopupMenuButton<String>(
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    _showEditDialog(template);
                                    break;
                                  case 'delete':
                                    _deleteTemplate(template);
                                    break;
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 20),
                                      SizedBox(width: 8),
                                      Text('Edit'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete,
                                          size: 20, color: Colors.red),
                                      SizedBox(width: 8),
                                      Text('Delete',
                                          style: TextStyle(color: Colors.red)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                        },
                      ),
                    ),
          // Search FAB at bottom-left
          const SearchFAB(),
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
    );
  }
}
