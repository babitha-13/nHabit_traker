import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/goal_record.dart';
import 'package:habit_tracker/Screens/Goals/goal_data_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/main.dart';
import 'package:habit_tracker/Screens/Goals/goal_history_page.dart';

/// Goal dialog for displaying and editing user goals
/// Supports both view and edit modes
class GoalDialog extends StatefulWidget {
  const GoalDialog({super.key});
  @override
  State<GoalDialog> createState() => _GoalDialogState();
}

class _GoalDialogState extends State<GoalDialog> {
  bool _isEditMode = false;
  bool _isLoading = true;
  bool _isSaving = false;
  GoalRecord? _currentGoal;
  // Form controllers
  final _whatController = TextEditingController();
  final _byWhenController = TextEditingController();
  final _whyController = TextEditingController();
  final _howController = TextEditingController();
  final _avoidController = TextEditingController();
  // Form key for validation
  final _formKey = GlobalKey<FormState>();
  @override
  void initState() {
    super.initState();
    _loadGoal();
    // Mark goal as shown immediately when dialog appears
    _markGoalAsShown();
  }

  @override
  void dispose() {
    _whatController.dispose();
    _byWhenController.dispose();
    _whyController.dispose();
    _howController.dispose();
    _avoidController.dispose();
    super.dispose();
  }

  Future<void> _loadGoal() async {
    try {
      final goal = await GoalService.getUserGoal(users.uid ?? '');
      setState(() {
        _currentGoal = goal;
        _isLoading = false;
      });
      if (goal != null) {
        _whatController.text = goal.whatToAchieve;
        _byWhenController.text = goal.byWhen;
        _whyController.text = goal.why;
        _howController.text = goal.how;
        _avoidController.text = goal.thingsToAvoid;
      } else {
        // No goal exists, start in edit mode
        setState(() {
          _isEditMode = true;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _markGoalAsShown() async {
    try {
      await GoalService.markGoalShown(users.uid ?? '');
    } catch (e) {
      // Silently handle error - don't show to user
    }
  }

  Future<void> _saveGoal() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isSaving = true;
    });
    try {
      final goalData = createGoalRecordData(
        whatToAchieve: _whatController.text.trim(),
        byWhen: _byWhenController.text.trim(),
        why: _whyController.text.trim(),
        how: _howController.text.trim(),
        thingsToAvoid: _avoidController.text.trim(),
        lastShownAt: _currentGoal?.lastShownAt,
        createdAt: _currentGoal?.createdAt ?? DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
      );
      final goal = GoalRecord.getDocumentFromData(
        goalData,
        _currentGoal?.reference ??
            GoalRecord.collectionForUser(users.uid ?? '').doc(),
      );
      await GoalService.saveGoal(users.uid ?? '', goal);
      setState(() {
        _isEditMode = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal saved successfully! 🎯'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error saving goal. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _toggleEditMode() {
    setState(() {
      _isEditMode = !_isEditMode;
    });
  }

  void _cancelEdit() {
    // Reset form to original values
    if (_currentGoal != null) {
      _whatController.text = _currentGoal!.whatToAchieve;
      _byWhenController.text = _currentGoal!.byWhen;
      _whyController.text = _currentGoal!.why;
      _howController.text = _currentGoal!.how;
      _avoidController.text = _currentGoal!.thingsToAvoid;
    }
    setState(() {
      _isEditMode = false;
    });
  }

  Future<void> _markAsCompleted() async {
    try {
      await GoalService.markGoalAsCompleted(users.uid ?? '');
      // Clear current goal data
      setState(() {
        _currentGoal = null;
        _whatController.clear();
        _byWhenController.clear();
        _whyController.clear();
        _howController.clear();
        _avoidController.clear();
        _isEditMode = true; // Automatically switch to edit mode for new goal
      });
      // Reload goal (will be null now)
      await _loadGoal();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Goal marked as completed! 🎉'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Error marking goal as completed. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _navigateToHistory() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const GoalHistoryPage(),
      ),
    );
  }

  Widget _buildFormField({
    required String label,
    required String helperText,
    required TextEditingController controller,
    required String? Function(String?) validator,
    int maxLines = 1,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.titleMedium.override(
            fontFamily: 'Outfit',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          maxLines: maxLines,
          enabled: _isEditMode,
          decoration: InputDecoration(
            hintText: helperText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: !_isEditMode,
            fillColor: _isEditMode ? null : theme.secondaryBackground,
          ),
          validator: validator,
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildDisplayField({
    required String answer,
  }) {
    final theme = FlutterFlowTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          answer,
          style: theme.bodyLarge.override(
            fontFamily: 'Readex Pro',
            color: Colors.black,
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: const BoxDecoration(
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(24),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Icon(
                        Icons.gps_fixed,
                        color: theme.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _isEditMode
                              ? (_currentGoal == null
                                  ? 'Set Your Goal'
                                  : 'Edit Your Goal')
                              : 'Your Goal',
                          style: theme.headlineSmall.override(
                            fontFamily: 'Outfit',
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (!_isEditMode && _currentGoal != null)
                        IconButton(
                          onPressed: _navigateToHistory,
                          icon: const Icon(Icons.history),
                          tooltip: 'View Goal History',
                        ),
                      if (!_isEditMode && _currentGoal != null)
                        IconButton(
                          onPressed: _toggleEditMode,
                          icon: const Icon(Icons.edit),
                          tooltip: 'Edit Goal',
                        ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Form
                  Expanded(
                    child: Container(
                      color: Colors.white,
                      child: Form(
                        key: _formKey,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: _isEditMode
                                ? [
                                    // Edit mode - form fields
                                    _buildFormField(
                                      label: 'What do you want to achieve?',
                                      helperText:
                                          'e.g., Lose 10 kg, Learn Spanish, Start a business',
                                      controller: _whatController,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter what you want to achieve';
                                        }
                                        return null;
                                      },
                                    ),
                                    _buildFormField(
                                      label:
                                          'By when do you want to achieve this?',
                                      helperText:
                                          'e.g., December 31, 2025, In 6 months',
                                      controller: _byWhenController,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter your target date';
                                        }
                                        return null;
                                      },
                                    ),
                                    _buildFormField(
                                      label: 'Why do you want to achieve this?',
                                      helperText:
                                          'e.g., To improve health, For career growth, Financial freedom',
                                      controller: _whyController,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter your motivation';
                                        }
                                        return null;
                                      },
                                      maxLines: 2,
                                    ),
                                    _buildFormField(
                                      label: 'How will you achieve this?',
                                      helperText:
                                          'e.g., Exercise daily, Study 30 min/day, Work on weekends',
                                      controller: _howController,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter your action plan';
                                        }
                                        return null;
                                      },
                                      maxLines: 2,
                                    ),
                                    _buildFormField(
                                      label:
                                          'Things I will avoid in order to achieve this',
                                      helperText:
                                          'e.g., Junk food, Procrastination, Negative people',
                                      controller: _avoidController,
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return 'Please enter what you will avoid';
                                        }
                                        return null;
                                      },
                                      maxLines: 2,
                                    ),
                                  ]
                                : [
                                    // View mode - show only answers
                                    if (_whatController.text.isNotEmpty)
                                      _buildDisplayField(
                                        answer: _whatController.text,
                                      ),
                                    if (_byWhenController.text.isNotEmpty)
                                      _buildDisplayField(
                                        answer: _byWhenController.text,
                                      ),
                                    if (_whyController.text.isNotEmpty)
                                      _buildDisplayField(
                                        answer: _whyController.text,
                                      ),
                                    if (_howController.text.isNotEmpty)
                                      _buildDisplayField(
                                        answer: _howController.text,
                                      ),
                                    if (_avoidController.text.isNotEmpty)
                                      _buildDisplayField(
                                        answer: _avoidController.text,
                                      ),
                                  ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Action buttons
                  if (!_isEditMode && _currentGoal != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Flexible(
                          child: OutlinedButton(
                            onPressed: _markAsCompleted,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Mark as Completed',
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                            ),
                            child: const Text(
                              'Yes, I will do it! 💪',
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_isEditMode) ...[
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: _isSaving ? null : _cancelEdit,
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton(
                          onPressed: _isSaving ? null : _saveGoal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 12,
                            ),
                          ),
                          child: _isSaving
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                                  ),
                                )
                              : const Text('Save Goal'),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 8),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: const Text('Yes, I will do it! 💪'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}
