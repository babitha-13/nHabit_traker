import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/testing/simple_day_advancer_ui.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
/// Simple testing page for day advancement
class SimpleTestingPage extends StatelessWidget {
  const SimpleTestingPage({Key? key}) : super(key: key);
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
                        'Testing Mode: This page is for development and testing only.',
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
              // Simple instructions
              Container(
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
              ),
            ],
          ),
        ),
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
}
