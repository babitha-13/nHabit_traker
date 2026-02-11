import 'package:flutter/material.dart';
import 'package:habit_tracker/services/testing/simple_day_advancer.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'package:intl/intl.dart';

/// Simple UI for day advancement testing
class SimpleDayAdvancerUI extends StatefulWidget {
  const SimpleDayAdvancerUI({Key? key}) : super(key: key);
  @override
  State<SimpleDayAdvancerUI> createState() => _SimpleDayAdvancerUIState();
}

class _SimpleDayAdvancerUIState extends State<SimpleDayAdvancerUI> {
  bool _isProcessing = false;
  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
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
                Icons.schedule,
                color: theme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Day Advancer (Testing)',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Current date display
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.primaryBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: theme.alternate, width: 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Current Date',
                  style: theme.bodySmall.override(
                    fontFamily: 'Readex Pro',
                    color: theme.secondaryText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('EEEE, MMM d, yyyy')
                      .format(SimpleDayAdvancer.currentDate),
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _advanceDay,
                  icon: _isProcessing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.arrow_forward, size: 18),
                  label: Text(_isProcessing ? 'Processing...' : 'Advance Day'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _isProcessing ? null : _resetDate,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Reset'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.secondary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Instructions
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.alternate.withOpacity(0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How to Test:',
                  style: theme.bodyMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '1. Create some habits in your app\n'
                  '2. Complete or partially complete them\n'
                  '3. Click "Advance Day" to trigger day-end processing\n'
                  '4. Check Progress page to see the results',
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

  Future<void> _advanceDay() async {
    setState(() {
      _isProcessing = true;
    });
    try {
      await SimpleDayAdvancer.advanceToNextDay();
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Day advanced successfully! Check Progress page for results.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _resetDate() {
    SimpleDayAdvancer.resetToRealTime();
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Date reset to real time'),
        backgroundColor: Colors.blue,
      ),
    );
  }
}
