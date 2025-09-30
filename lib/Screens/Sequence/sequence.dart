import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:habit_tracker/Helper/backend/backend.dart';
import 'package:habit_tracker/Helper/backend/schema/habit_record.dart';
import 'package:habit_tracker/Helper/backend/schema/sequence_record.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class Sequences extends StatefulWidget {
  const Sequences({super.key});

  @override
  _SequencesState createState() => _SequencesState();
}

class _SequencesState extends State<Sequences> {
  final scaffoldKey = GlobalKey<ScaffoldState>();

  List<SequenceRecord> _sequences = [];
  List<HabitRecord> _habits = [];
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
        final habits = await queryHabitsRecordOnce(userId: userId);

        setState(() {
          _sequences = sequences;
          _habits = habits;
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading sequences: $e');
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
      print('Error deleting sequence: $e');
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

  void _showAddSequenceDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    List<String> selectedHabitIds = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Sequence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Sequence Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Habits:',
                  style: FlutterFlowTheme.of(context).titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  child: ListView.builder(
                    itemCount: _habits.length,
                    itemBuilder: (context, index) {
                      final habit = _habits[index];
                      return CheckboxListTile(
                        title: Text(habit.name),
                        subtitle: Text(habit.categoryName),
                        value: selectedHabitIds.contains(habit.reference.id),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedHabitIds.add(habit.reference.id);
                            } else {
                              selectedHabitIds.remove(habit.reference.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    selectedHabitIds.isNotEmpty) {
                  try {
                    await createSequence(
                      name: nameController.text,
                      description: descriptionController.text.isNotEmpty
                          ? descriptionController.text
                          : null,
                      habitIds: selectedHabitIds,
                    );

                    Navigator.of(context).pop();
                    await _loadData(); // Reload the list

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Sequence "${nameController.text}" created successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error creating sequence: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error creating sequence: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditSequenceDialog(SequenceRecord sequence) {
    final nameController = TextEditingController(text: sequence.name);
    final descriptionController =
        TextEditingController(text: sequence.description);
    List<String> selectedHabitIds = List.from(sequence.habitIds);

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Edit Sequence'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Sequence Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Text(
                  'Select Habits:',
                  style: FlutterFlowTheme.of(context).titleSmall,
                ),
                const SizedBox(height: 8),
                Container(
                  height: 200,
                  child: ListView.builder(
                    itemCount: _habits.length,
                    itemBuilder: (context, index) {
                      final habit = _habits[index];
                      return CheckboxListTile(
                        title: Text(habit.name),
                        subtitle: Text(habit.categoryName),
                        value: selectedHabitIds.contains(habit.reference.id),
                        onChanged: (bool? value) {
                          setDialogState(() {
                            if (value == true) {
                              selectedHabitIds.add(habit.reference.id);
                            } else {
                              selectedHabitIds.remove(habit.reference.id);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.isNotEmpty &&
                    selectedHabitIds.isNotEmpty) {
                  try {
                    await updateSequence(
                      sequenceId: sequence.reference.id,
                      name: nameController.text,
                      description: descriptionController.text.isNotEmpty
                          ? descriptionController.text
                          : null,
                      habitIds: selectedHabitIds,
                      userId: currentUserUid,
                    );

                    Navigator.of(context).pop();
                    await _loadData(); // Reload the list

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Sequence "${nameController.text}" updated successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    print('Error updating sequence: $e');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error updating sequence: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }

  List<String> _getHabitNames(List<String> habitIds) {
    return habitIds.map((id) {
      try {
        final habit = _habits.firstWhere((h) => h.reference.id == id);
        return habit.name;
      } catch (e) {
        return 'Unknown Habit';
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
                                  'Create sequences to group related habits!',
                                  style:
                                      FlutterFlowTheme.of(context).bodyMedium,
                                ),
                                const SizedBox(height: 16),
                                ElevatedButton(
                                  onPressed: _showAddSequenceDialog,
                                  child: const Text('Add Sequence'),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _sequences.length,
                            itemBuilder: (context, index) {
                              final sequence = _sequences[index];
                              final habitNames =
                                  _getHabitNames(sequence.habitIds);

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
                                        '${habitNames.length} habits',
                                        style: FlutterFlowTheme.of(context)
                                            .bodySmall,
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        children: habitNames
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
                                      if (habitNames.length > 3)
                                        Text(
                                          '+${habitNames.length - 3} more',
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
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.play_arrow),
                                        onPressed: () {
                                          // TODO: Start sequence
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                  'Starting sequence "${sequence.name}"...'),
                                            ),
                                          );
                                        },
                                        color: FlutterFlowTheme.of(context)
                                            .primary,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.edit),
                                        onPressed: () =>
                                            _showEditSequenceDialog(sequence),
                                        color: FlutterFlowTheme.of(context)
                                            .secondaryText,
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete),
                                        onPressed: () =>
                                            _showDeleteConfirmation(sequence),
                                        color: Colors.red,
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
      ),
    );
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
