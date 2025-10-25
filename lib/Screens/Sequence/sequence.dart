import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Screens/Sequence/create_sequence_page.dart';
import 'package:habit_tracker/Screens/Sequence/sequence_detail_page.dart';

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
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isNotEmpty) {
        final sequences = await querySequenceRecordOnce(userId: userId);
        // Debug each sequence
        for (int i = 0; i < sequences.length; i++) {
          final seq = sequences[i];
          print('🔍 DEBUG: Sequence $i: ${seq.name} (ID: ${seq.reference.id})');
        }
        final habits = await queryActivitiesRecordOnce(userId: userId);
        setState(() {
          _sequences = sequences;
          _habits = habits;
          _isLoading = false;
        });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: scaffoldKey,
      backgroundColor: FlutterFlowTheme.of(context).primaryBackground,
      body: SafeArea(
        top: true,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // Sequences list
                  Expanded(
                    child: _sequences.isEmpty
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
                                  'No sequences yet',
                                  style:
                                      FlutterFlowTheme.of(context).titleMedium,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Create sequences to group related habits and tasks!',
                                  style:
                                      FlutterFlowTheme.of(context).bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _navigateToCreateSequence,
                                  child: const Text('Create Sequence'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _sequences.length,
                            itemBuilder: (context, index) {
                              final sequence = _sequences[index];
                              final itemNames = sequence.itemNames.isNotEmpty
                                  ? sequence.itemNames
                                  : _getItemNames(sequence.itemIds);
                              return Container(
                                margin: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 4),
                                decoration: BoxDecoration(
                                  color: FlutterFlowTheme.of(context)
                                      .secondaryBackground,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color:
                                        FlutterFlowTheme.of(context).alternate,
                                    width: 1,
                                  ),
                                ),
                                child: ListTile(
                                  onTap: () =>
                                      _navigateToSequenceDetail(sequence),
                                  leading: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color:
                                          FlutterFlowTheme.of(context).primary,
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
                                    style: FlutterFlowTheme.of(context)
                                        .titleMedium,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (sequence.description.isNotEmpty)
                                        Text(
                                          sequence.description,
                                          style: FlutterFlowTheme.of(context)
                                              .bodyMedium,
                                        ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${itemNames.length} items',
                                        style: FlutterFlowTheme.of(context)
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        children: itemNames
                                            .take(3)
                                            .map(
                                              (name) => Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 6,
                                                        vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: FlutterFlowTheme.of(
                                                          context)
                                                      .primary
                                                      .withOpacity(0.1),
                                                  borderRadius:
                                                      BorderRadius.circular(8),
                                                ),
                                                child: Text(
                                                  name,
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: FlutterFlowTheme.of(
                                                            context)
                                                        .primary,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                      if (itemNames.length > 3)
                                        Text(
                                          '+${itemNames.length - 3} more',
                                          style: FlutterFlowTheme.of(context)
                                              .bodySmall
                                              .override(
                                                fontFamily: 'Readex Pro',
                                                color:
                                                    FlutterFlowTheme.of(context)
                                                        .secondaryText,
                                              ),
                                        ),
                                    ],
                                  ),
                                  trailing: Builder(
                                    builder: (context) => IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () =>
                                          _showSequenceOverflowMenu(
                                              context, sequence),
                                      color: FlutterFlowTheme.of(context)
                                          .secondaryText,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _navigateToCreateSequence,
        backgroundColor: FlutterFlowTheme.of(context).primary,
        child: const Icon(
          Icons.add,
          color: Colors.white,
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
}
