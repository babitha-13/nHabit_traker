import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/goal_record.dart';
import 'package:habit_tracker/Screens/Goals/goal_data_service.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/main.dart';

/// Onboarding goal dialog for new users to set their first goal
/// Provides three options: Fill & Save, Do It Later, or Skip
class GoalOnboardingDialog extends StatefulWidget {
  const GoalOnboardingDialog({super.key});
  @override
  State<GoalOnboardingDialog> createState() => _GoalOnboardingDialogState();
}

class _GoalOnboardingDialogState extends State<GoalOnboardingDialog> {
  bool _isSaving = false;
  // Form controllers
  final _whatController = TextEditingController();
  final _byWhenController = TextEditingController();
  final _whyController = TextEditingController();
  final _howController = TextEditingController();
  final _avoidController = TextEditingController();
  // Form key for validation
  final _formKey = GlobalKey<FormState>();
  @override
  void dispose() {
    _whatController.dispose();
    _byWhenController.dispose();
    _whyController.dispose();
    _howController.dispose();
    _avoidController.dispose();
    super.dispose();
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
        lastShownAt: null,
        createdAt: DateTime.now(),
        lastUpdated: DateTime.now(),
        isActive: true,
      );
      final goal = GoalRecord.getDocumentFromData(
        goalData,
        GoalRecord.collectionForUser(users.uid ?? '').doc(),
      );
      await GoalService.saveGoal(users.uid ?? '', goal);
      await GoalService.markOnboardingCompleted(users.uid ?? '');
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Goal saved successfully! 🎯'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error saving goal. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _doItLater() async {
    Navigator.of(context).pop();
  }

  Future<void> _skip() async {
    try {
      await GoalService.markOnboardingSkipped(users.uid ?? '');
      Navigator.of(context).pop();
    } catch (e) {
      Navigator.of(context).pop();
    }
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
          decoration: InputDecoration(
            hintText: helperText,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          validator: validator,
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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(
                  Icons.flag,
                  color: theme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Welcome! Let\'s set your first goal 🎯',
                    style: theme.headlineSmall.override(
                      fontFamily: 'Outfit',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
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
                      children: [
                        _buildFormField(
                          label: 'What do you want to achieve?',
                          helperText:
                              'e.g., Lose 10 kg, Learn Spanish, Start a business',
                          controller: _whatController,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter what you want to achieve';
                            }
                            return null;
                          },
                        ),
                        _buildFormField(
                          label: 'By when do you want to achieve this?',
                          helperText: 'e.g., December 31, 2025, In 6 months',
                          controller: _byWhenController,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
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
                            if (value == null || value.trim().isEmpty) {
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
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your action plan';
                            }
                            return null;
                          },
                          maxLines: 2,
                        ),
                        _buildFormField(
                          label: 'Things I will avoid in order to achieve this',
                          helperText:
                              'e.g., Junk food, Procrastination, Negative people',
                          controller: _avoidController,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter what you will avoid';
                            }
                            return null;
                          },
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Skip button
                TextButton(
                  onPressed: _isSaving ? null : _skip,
                  child: const Text('Skip'),
                ),
                // Do it later button
                TextButton(
                  onPressed: _isSaving ? null : _doItLater,
                  child: const Text('Do It Later'),
                ),
                // Fill & Save button
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
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Text('Fill & Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
