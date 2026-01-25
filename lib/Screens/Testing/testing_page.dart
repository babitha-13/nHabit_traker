import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/testing/simple_day_advancer_ui.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/Helpers/Date_time_services/date_service.dart';
import 'package:habit_tracker/Helper/Helpers/testing/duplicate_instance_cleanup.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';

/// Testing page for day simulation and habit/task testing
/// Add this to your app navigation for easy testing access
class TestingPage extends StatefulWidget {
  const TestingPage({Key? key}) : super(key: key);
  @override
  State<TestingPage> createState() => _TestingPageState();
}

class _TestingPageState extends State<TestingPage> {
  bool _isScanningDuplicates = false;
  bool _isDeletingDuplicates = false;
  DuplicateScanResults? _scanResults;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Scaffold(
      backgroundColor: theme.primaryBackground,
      appBar: AppBar(
        backgroundColor: theme.primary,
        automaticallyImplyLeading: true,
        title: Text(
          'Testing Tools',
          style: theme.headlineMedium.override(
            fontFamily: 'Readex Pro',
            color: Colors.white,
            fontSize: 22.0,
          ),
        ),
        centerTitle: false,
        elevation: 0.0,
      ),
      body: SafeArea(
        top: true,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Warning banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700], size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Testing Mode: This page is for development and testing only. Do not use in production.',
                        style: theme.bodySmall.override(
                          fontFamily: 'Readex Pro',
                          color: Colors.orange[700],
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              // Simple Day Advancer
              const SimpleDayAdvancerUI(),
              const SizedBox(height: 24),
              // DateService Status
              _buildDateServiceStatus(theme),
              const SizedBox(height: 24),
              // Database Cleanup Tools
              _buildCleanupTools(theme),
              const SizedBox(height: 24),
              // Testing instructions
              _buildInstructions(theme),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateServiceStatus(FlutterFlowTheme theme) {
    final status = DateService.getStatus();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                color: theme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'DateService Status',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildStatusRow('Test Mode',
              status['isTestMode'] ? 'Enabled' : 'Disabled', theme),
          _buildStatusRow('Current Date', status['currentDate'], theme),
          _buildStatusRow('Real Date', status['realDate'], theme),
          if (status['testDate'] != null)
            _buildStatusRow('Test Date', status['testDate'], theme),
        ],
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: theme.bodySmall.override(
                fontFamily: 'Readex Pro',
                color: theme.secondaryText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.bodySmall.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructions(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to Test Day-End Processing',
            style: theme.titleMedium.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          _buildInstructionStep(
            '1',
            'Create Test Habits',
            'Go to your app and create some habits with different frequencies',
            theme,
          ),
          _buildInstructionStep(
            '2',
            'Complete Habits Manually',
            'Mark habits as completed or partially completed in your app',
            theme,
          ),
          _buildInstructionStep(
            '3',
            'Advance to Next Day',
            'Click "Advance Day" to trigger day-end processing',
            theme,
          ),
          _buildInstructionStep(
            '4',
            'Check Progress Page',
            'Navigate to your Progress page to see the generated historical data',
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionStep(
      String number, String title, String description, FlutterFlowTheme theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: theme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                number,
                style: theme.bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.bodyMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCleanupTools(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.secondaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.alternate, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.cleaning_services,
                color: theme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Database Cleanup Tools',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Scan button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanningDuplicates
                  ? null
                  : () => _handleScanDuplicates(theme),
              icon: _isScanningDuplicates
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.search),
              label: Text(
                _isScanningDuplicates
                    ? 'Scanning for Duplicates...'
                    : 'Scan for Duplicates',
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Delete button (only enabled if scan results exist)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_isDeletingDuplicates ||
                      _scanResults == null ||
                      _scanResults!.instanceIdsToDelete.isEmpty)
                  ? null
                  : () => _handleDeleteDuplicates(theme),
              icon: _isDeletingDuplicates
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.delete_sweep),
              label: Text(
                _isDeletingDuplicates
                    ? 'Deleting Duplicates...'
                    : 'Delete Duplicates',
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Show scan results summary if available
          if (_scanResults != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _scanResults!.duplicateGroupsFound > 0
                    ? Colors.orange.withOpacity(0.1)
                    : Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _scanResults!.duplicateGroupsFound > 0
                      ? Colors.orange.withOpacity(0.3)
                      : Colors.green.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _scanResults!.duplicateGroupsFound > 0
                            ? Icons.warning
                            : Icons.check_circle,
                        color: _scanResults!.duplicateGroupsFound > 0
                            ? Colors.orange[700]
                            : Colors.green[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Scan Results',
                        style: theme.bodyMedium.override(
                          fontFamily: 'Readex Pro',
                          fontWeight: FontWeight.w600,
                          color: _scanResults!.duplicateGroupsFound > 0
                              ? Colors.orange[700]
                              : Colors.green[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Total scanned: ${_scanResults!.totalInstancesScanned}\n'
                    'Duplicate groups: ${_scanResults!.duplicateGroupsFound}\n'
                    'Instances to delete: ${_scanResults!.instanceIdsToDelete.length}\n'
                    'Skipped (null dueDate): ${_scanResults!.instancesWithNullDueDate}',
                    style: theme.bodySmall.override(
                      fontFamily: 'Readex Pro',
                    ),
                  ),
                  if (_scanResults!.duplicateGroupsFound > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Check debug console for detailed breakdown.',
                      style: theme.bodySmall.override(
                        fontFamily: 'Readex Pro',
                        fontStyle: FontStyle.italic,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          Text(
            'Step 1: Scan to identify duplicates. Step 2: Review results, then delete. Keeps completed instances when available, otherwise keeps the oldest instance.',
            style: theme.bodySmall.override(
              fontFamily: 'Readex Pro',
              color: theme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleScanDuplicates(FlutterFlowTheme theme) async {
    setState(() {
      _isScanningDuplicates = true;
      _scanResults = null; // Clear previous results
    });

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User not authenticated'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Run scan
      final results = await DuplicateInstanceCleanup.scanForDuplicates(userId);

      if (mounted) {
        setState(() {
          _scanResults = results;
        });

        // Show results dialog
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(results.duplicateGroupsFound > 0
                ? 'Duplicates Found'
                : 'No Duplicates Found'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Total instances scanned: ${results.totalInstancesScanned}'),
                  const SizedBox(height: 8),
                  Text(
                      'Instances with null dueDate (skipped): ${results.instancesWithNullDueDate}'),
                  const SizedBox(height: 8),
                  Text(
                      'Duplicate groups found: ${results.duplicateGroupsFound}'),
                  const SizedBox(height: 8),
                  Text(
                      'Instances to delete: ${results.instanceIdsToDelete.length}'),
                  if (results.duplicatesPerTemplate.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Duplicates per template:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...results.duplicatesPerTemplate.entries
                        .map((entry) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 16, bottom: 4),
                              child: Text('• ${entry.key}: ${entry.value}'),
                            )),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Check debug console for detailed breakdown. Review the results, then use the "Delete Duplicates" button to proceed.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during scan: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      print('❌ Scan error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isScanningDuplicates = false;
        });
      }
    }
  }

  Future<void> _handleDeleteDuplicates(FlutterFlowTheme theme) async {
    if (_scanResults == null || _scanResults!.instanceIdsToDelete.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No duplicates to delete. Please scan first.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'This will permanently delete ${_scanResults!.instanceIdsToDelete.length} duplicate activity instances.\n\n'
          'For each group of duplicates, it will keep the completed instance (if any) or the oldest instance.\n\n'
          'This action cannot be undone.\n\n'
          'Do you want to continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isDeletingDuplicates = true;
    });

    try {
      final userId = await waitForCurrentUserUid();
      if (userId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Error: User not authenticated'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      // Run deletion using scan results
      final stats = await DuplicateInstanceCleanup.deleteDuplicates(
          userId, _scanResults!);

      if (mounted) {
        // Clear scan results after successful deletion
        setState(() {
          _scanResults = null;
        });

        // Show success dialog with statistics
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Deletion Complete'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Total instances deleted: ${stats.totalInstancesDeleted}'),
                  const SizedBox(height: 8),
                  Text('Instances kept: ${stats.totalInstancesKept}'),
                  if (stats.duplicatesPerTemplate.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Deleted per template:',
                        style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...stats.duplicatesPerTemplate.entries
                        .map((entry) => Padding(
                              padding:
                                  const EdgeInsets.only(left: 16, bottom: 4),
                              child: Text('• ${entry.key}: ${entry.value}'),
                            )),
                  ],
                  const SizedBox(height: 8),
                  const Text(
                    'Check debug console for detailed statistics.',
                    style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error during deletion: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      print('❌ Deletion error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isDeletingDuplicates = false;
        });
      }
    }
  }
}
