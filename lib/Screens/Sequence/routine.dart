import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/backend/sequence_order_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/utils/search_state_manager.dart';
import 'package:habit_tracker/Helper/utils/search_fab.dart';
import 'package:habit_tracker/Helper/utils/notification_center.dart';
import 'package:habit_tracker/Screens/Sequence/create_sequence_page.dart';
import 'package:habit_tracker/Screens/Sequence/sequence_detail_page.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_templates_page.dart';
import 'package:habit_tracker/Screens/NonProductive/non_productive_template_dialog.dart';

class Sequences extends StatefulWidget {
  const Sequences({super.key});
  @override
  _SequencesState createState() => _SequencesState();
}

class _SequencesState extends State<Sequences> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  List<SequenceRecord> _sequences = [];
  List<ActivityRecord> _habits = [];
  bool _isLoading = true;
  // Search functionality
  String _searchQuery = '';
  final SearchStateManager _searchManager = SearchStateManager();
  // Track sequences being reordered to prevent stale updates
  Set<String> _reorderingSequenceIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
    // Listen for search changes
    _searchManager.addListener(_onSearchChanged);
    NotificationCenter.addObserver(this, 'categoryUpdated', (param) {
      if (mounted) {
        _loadData();
      }
    });
  }

  @override
  void dispose() {
    NotificationCenter.removeObserver(this);
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

  List<SequenceRecord> get _filteredSequences {
    if (_searchQuery.isEmpty) {
      return _sequences;
    }
    final query = _searchQuery.toLowerCase();
    return _sequences.where((sequence) {
      final nameMatch = sequence.name.toLowerCase().contains(query);
      final descriptionMatch =
          sequence.description.toLowerCase().contains(query);
      return nameMatch || descriptionMatch;
    }).toList();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final sequences = await querySequenceRecordOnce(userId: userId);
        final habits = await queryActivitiesRecordOnce(userId: userId);
        // Sort sequences by order to ensure consistent display
        final sortedSequences =
            SequenceOrderService.sortSequencesByOrder(sequences);
        setState(() {
          _sequences = sortedSequences;
          _habits = habits;
          _isLoading = false;
        });
        // Initialize order values for sequences that don't have them
        SequenceOrderService.initializeOrderValues(_sequences);
      } else {}
    } catch (e) {
      if (e is FirebaseException) {}
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSequence(SequenceRecord sequence) async {
    try {
      await deleteSequence(sequence.reference.id, userId: currentUserUid);
      await _loadData(); // Reload the list
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Sequence "${sequence.name}" deleted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error deleting sequence: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _navigateToCreateSequence() {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => const CreateSequencePage(),
      ),
    )
        .then((_) {
      // Reload the list after creating a sequence
      _loadData();
    });
  }

  void _navigateToEditSequence(SequenceRecord sequence) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => CreateSequencePage(
          existingSequence: sequence,
        ),
      ),
    )
        .then((_) {
      // Reload the list after editing a sequence
      _loadData();
    });
  }

  void _navigateToSequenceDetail(SequenceRecord sequence) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SequenceDetailPage(
          sequence: sequence,
        ),
      ),
    );
  }

  List<String> _getItemNames(List<String> itemIds) {
    return itemIds.map((id) {
      try {
        final activity = _habits.firstWhere((h) => h.reference.id == id);
        return activity.name;
      } catch (e) {
        return 'Unknown Item';
      }
    }).toList();
  }

  void _navigateToNonProductiveTemplates() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const NonProductiveTemplatesPage(),
      ),
    );
  }

  Future<void> _showCreateNonProductiveDialog() async {
    final result = await showDialog<ActivityRecord>(
      context: context,
      builder: (context) => NonProductiveTemplateDialog(
        onTemplateCreated: (template) {
          Navigator.of(context).pop(template);
        },
      ),
    );
    // Optionally reload data if needed
    if (result != null) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      appBar: AppBar(
        backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
        title: const Text('Sequences'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'non_productive') {
                _navigateToNonProductiveTemplates();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'non_productive',
                child: Row(
                  children: [
                    Icon(Icons.access_time, size: 20),
                    SizedBox(width: 8),
                    Text('Manage Non-Productive Items'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: true,
        child: Stack(
          children: [
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      // Search indicator banner when search is active
                      if (_searchQuery.isNotEmpty &&
                          _filteredSequences.isNotEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          color: FlutterFlowTheme.of(context)
                              .secondaryBackground
                              .withOpacity(0.7),
                          child: Row(
                            children: [
                              Icon(
                                Icons.info_outline,
                                size: 16,
                                color:
                                    FlutterFlowTheme.of(context).secondaryText,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Drag and drop is disabled while searching',
                                  style: FlutterFlowTheme.of(context)
                                      .bodySmall
                                      .override(
                                        fontSize: 12,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      // Create New Sequence button at the top
                      if (_filteredSequences.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _navigateToCreateSequence,
                              icon: const Icon(Icons.add),
                              label: const Text('Create New Sequence'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    FlutterFlowTheme.of(context).primary,
                                foregroundColor: Colors.white,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                              ),
                            ),
                          ),
                        ),
                      // Sequences list
                      Expanded(
                        child: _filteredSequences.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.playlist_play,
                                      size: 64,
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'No sequences found'
                                          : 'No sequences yet',
                                      style: FlutterFlowTheme.of(context)
                                          .titleMedium,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      _searchQuery.isNotEmpty
                                          ? 'Try a different search term'
                                          : 'Create sequences to group related habits and tasks!',
                                      style: FlutterFlowTheme.of(context)
                                          .bodyMedium,
                                    ),
                                    if (_searchQuery.isEmpty) ...[
                                      const SizedBox(height: 16),
                                      ElevatedButton(
                                        onPressed: _navigateToCreateSequence,
                                        child: const Text('Create Sequence'),
                                      ),
                                    ],
                                  ],
                                ),
                              )
                            : _searchQuery.isEmpty
                                ? ReorderableListView.builder(
                                    itemCount: _sequences.length,
                                    onReorder: _handleReorder,
                                    itemBuilder: (context, index) {
                                      final sequence = _sequences[index];
                                      final itemNames =
                                          sequence.itemNames.isNotEmpty
                                              ? sequence.itemNames
                                              : _getItemNames(sequence.itemIds);
                                      return _buildSequenceTile(
                                        sequence,
                                        itemNames,
                                        key: Key(sequence.reference.id),
                                      );
                                    },
                                  )
                                : ListView.builder(
                                    itemCount: _filteredSequences.length,
                                    itemBuilder: (context, index) {
                                      final sequence =
                                          _filteredSequences[index];
                                      final itemNames =
                                          sequence.itemNames.isNotEmpty
                                              ? sequence.itemNames
                                              : _getItemNames(sequence.itemIds);
                                      return _buildSequenceTile(
                                        sequence,
                                        itemNames,
                                      );
                                    },
                                  ),
                      ),
                      // Non-Productive Tasks Button at the bottom
                      // Add horizontal padding to avoid overlapping with FABs
                      Padding(
                        padding: const EdgeInsets.fromLTRB(80, 16, 80, 16),
                        child: ElevatedButton.icon(
                          onPressed: _navigateToNonProductiveTemplates,
                          icon: const Icon(Icons.access_time),
                          label: const Text('Non Productive Tasks'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                FlutterFlowTheme.of(context).primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                                vertical: 12, horizontal: 16),
                          ),
                        ),
                      ),
                    ],
                  ),
            // Search FAB at bottom-left
            const SearchFAB(heroTag: 'search_fab_sequences'),
            // Existing FAB at bottom-right
            Positioned(
              right: 16,
              bottom: 16,
              child: FloatingActionButton(
                heroTag:
                    null, // Disable Hero animation to avoid conflicts during navigation
                onPressed: _showCreateNonProductiveDialog,
                backgroundColor: FlutterFlowTheme.of(context).primary,
                child: const Icon(
                  Icons.add,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSequenceOverflowMenu(
      BuildContext anchorContext, SequenceRecord sequence) async {
    final box = anchorContext.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(anchorContext).context.findRenderObject() as RenderBox;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    final size = box?.size ?? const Size(0, 0);
    final selected = await showMenu<String>(
      context: anchorContext,
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
            child: Text('Edit', style: TextStyle(fontSize: 12))),
        PopupMenuDivider(height: 6),
        PopupMenuItem<String>(
            value: 'delete',
            height: 32,
            child: Text('Delete', style: TextStyle(fontSize: 12))),
      ],
    );
    if (selected == null) return;
    if (selected == 'edit') {
      _navigateToEditSequence(sequence);
    } else if (selected == 'delete') {
      _showDeleteConfirmation(sequence);
    }
  }

  void _showDeleteConfirmation(SequenceRecord sequence) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Sequence'),
        content: Text(
          'Are you sure you want to delete "${sequence.name}"? This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _deleteSequence(sequence);
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

  Widget _buildSequenceTile(
    SequenceRecord sequence,
    List<String> itemNames, {
    Key? key,
  }) {
    return Container(
      key: key,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: FlutterFlowTheme.of(context).secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: FlutterFlowTheme.of(context).alternate,
          width: 1,
        ),
      ),
      child: ListTile(
        onTap: () => _navigateToSequenceDetail(sequence),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: FlutterFlowTheme.of(context).primary,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.playlist_play,
            color: Colors.white,
            size: 20,
          ),
        ),
        title: Text(
          sequence.name,
          style: FlutterFlowTheme.of(context).titleMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (sequence.description.isNotEmpty)
              Text(
                sequence.description,
                style: FlutterFlowTheme.of(context).bodyMedium,
              ),
            const SizedBox(height: 4),
            Text(
              '${itemNames.length} items',
              style: FlutterFlowTheme.of(context).bodySmall,
            ),
          ],
        ),
        trailing: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showSequenceOverflowMenu(context, sequence),
            color: FlutterFlowTheme.of(context).secondaryText,
          ),
        ),
      ),
    );
  }

  /// Handle reordering of sequences
  Future<void> _handleReorder(int oldIndex, int newIndex) async {
    final reorderingIds = <String>{};
    try {
      // Allow dropping at the end (newIndex can equal sequences.length)
      if (oldIndex < 0 ||
          oldIndex >= _sequences.length ||
          newIndex < 0 ||
          newIndex > _sequences.length) return;

      // Create a copy of the sequences list for reordering
      final reorderedSequences = List<SequenceRecord>.from(_sequences);

      // Adjust newIndex for the case where we're moving down
      int adjustedNewIndex = newIndex;
      if (oldIndex < newIndex) {
        adjustedNewIndex -= 1;
      }

      // Get the sequence being moved
      final movedSequence = reorderedSequences.removeAt(oldIndex);
      reorderedSequences.insert(adjustedNewIndex, movedSequence);

      // OPTIMISTIC UI UPDATE: Update local state immediately
      // Update order values and create updated sequences
      final updatedSequences = <SequenceRecord>[];
      for (int i = 0; i < reorderedSequences.length; i++) {
        final sequence = reorderedSequences[i];
        final sequenceId = sequence.reference.id;
        reorderingIds.add(sequenceId);

        // Create updated sequence with new listOrder
        final updatedData = Map<String, dynamic>.from(sequence.snapshotData);
        updatedData['listOrder'] = i;
        final updatedSequence = SequenceRecord.getDocumentFromData(
          updatedData,
          sequence.reference,
        );

        updatedSequences.add(updatedSequence);
      }

      // Add sequence IDs to reordering set to prevent stale updates
      _reorderingSequenceIds.addAll(reorderingIds);

      // Replace _sequences with the reordered list (this is the key fix!)
      if (mounted) {
        setState(() {
          _sequences = updatedSequences;
        });
      }

      // Perform database update in background
      await SequenceOrderService.reorderSequences(
        updatedSequences,
        oldIndex,
        adjustedNewIndex,
      );

      // Clear reordering set after successful database update
      _reorderingSequenceIds.removeAll(reorderingIds);
    } catch (e) {
      // Clear reordering set even on error
      _reorderingSequenceIds.removeAll(reorderingIds);
      // Revert to correct state by refreshing data
      await _loadData();
      // Show error to user
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error reordering sequences: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
