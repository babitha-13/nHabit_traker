import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/testing/day_simulator.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/auth/firebase_auth/auth_util.dart';
import 'package:intl/intl.dart';

/// UI Widget for testing day simulation
/// Add this to your app for easy testing of day-end processing
class DaySimulatorUI extends StatefulWidget {
  const DaySimulatorUI({Key? key}) : super(key: key);
  @override
  State<DaySimulatorUI> createState() => _DaySimulatorUIState();
}

class _DaySimulatorUIState extends State<DaySimulatorUI> {
  bool _isSimulationMode = false;
  DateTime _simulatedDate = DateTime.now();
  bool _isLoading = false;
  Map<String, dynamic>? _progressAnalysis;
  @override
  void initState() {
    super.initState();
    _updateStatus();
  }

  void _updateStatus() {
    setState(() {
      _isSimulationMode = DaySimulator.isSimulationMode;
      _simulatedDate = DaySimulator.simulatedDate;
    });
  }

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
                Icons.science,
                color: theme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                'Day Simulator (Testing)',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (_isSimulationMode)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.3)),
                  ),
                  child: Text(
                    'SIMULATION MODE',
                    style: theme.bodySmall.override(
                      fontFamily: 'Readex Pro',
                      color: Colors.orange[700],
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          // Current status
          _buildStatusCard(theme),
          const SizedBox(height: 16),
          // Simulation controls
          _buildSimulationControls(theme),
          const SizedBox(height: 16),
          // Quick scenarios
          _buildQuickScenarios(theme),
          const SizedBox(height: 16),
          // Progress analysis
          if (_progressAnalysis != null) _buildProgressAnalysis(theme),
        ],
      ),
    );
  }

  Widget _buildStatusCard(FlutterFlowTheme theme) {
    return Container(
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
            'Current Status',
            style: theme.titleSmall.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'Simulated Date: ',
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: theme.secondaryText,
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(_simulatedDate),
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                'Real Date: ',
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: theme.secondaryText,
                ),
              ),
              Text(
                DateFormat('MMM d, yyyy').format(DateTime.now()),
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSimulationControls(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Simulation Controls',
          style: theme.titleSmall.override(
            fontFamily: 'Readex Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _toggleSimulation,
                style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _isSimulationMode ? Colors.red : theme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(
                    _isSimulationMode ? 'Stop Simulation' : 'Start Simulation'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _isLoading || !_isSimulationMode ? null : _advanceDay,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: Text(_isLoading ? 'Processing...' : 'Next Day'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed:
                    _isLoading || !_isSimulationMode ? null : _advanceWeek,
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.secondary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('Advance 7 Days'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: _isLoading ? null : _runWeekSimulation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                ),
                child: const Text('Simulate Week'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickScenarios(FlutterFlowTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Scenarios',
          style: theme.titleSmall.override(
            fontFamily: 'Readex Pro',
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildScenarioButton('Perfect Day', Colors.green,
                () => _runScenario(SimulationScenarios.perfectDay)),
            _buildScenarioButton('Good Day', Colors.blue,
                () => _runScenario(SimulationScenarios.goodDay)),
            _buildScenarioButton('Mixed Day', Colors.orange,
                () => _runScenario(SimulationScenarios.mixedDay)),
            _buildScenarioButton('Bad Day', Colors.red,
                () => _runScenario(SimulationScenarios.badDay)),
            _buildScenarioButton('Lazy Day', Colors.grey,
                () => _runScenario(SimulationScenarios.lazyDay)),
          ],
        ),
      ],
    );
  }

  Widget _buildScenarioButton(
      String label, Color color, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        minimumSize: Size.zero,
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12),
      ),
    );
  }

  Widget _buildProgressAnalysis(FlutterFlowTheme theme) {
    if (_progressAnalysis == null) return const SizedBox.shrink();
    return Container(
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
            'Progress Analysis',
            style: theme.titleSmall.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                    'Days', '${_progressAnalysis!['totalDays']}', theme),
              ),
              Expanded(
                child: _buildStatCard(
                    'Avg %',
                    '${_progressAnalysis!['averagePercentage']?.toStringAsFixed(1) ?? '0'}%',
                    theme),
              ),
              Expanded(
                child: _buildStatCard(
                    'Perfect', '${_progressAnalysis!['perfectDays']}', theme),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: theme.alternate,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: theme.titleSmall.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: theme.bodySmall.override(
              fontFamily: 'Readex Pro',
              color: theme.secondaryText,
            ),
          ),
        ],
      ),
    );
  }

  // Event handlers
  Future<void> _toggleSimulation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      if (_isSimulationMode) {
        DaySimulator.stopSimulation();
      } else {
        DaySimulator.startSimulation();
      }
      _updateStatus();
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _advanceDay() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await DaySimulator.advanceToNextDay();
      _updateStatus();
    } catch (e) {
      _showError('Error advancing day: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _advanceWeek() async {
    setState(() {
      _isLoading = true;
    });
    try {
      await DaySimulator.advanceDays(7);
      _updateStatus();
    } catch (e) {
      _showError('Error advancing week: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runWeekSimulation() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        _showError('No authenticated user');
        return;
      }
      await DaySimulatorTesting.simulateWeek(userId: userId);
      _showSuccess('Week simulation completed!');
    } catch (e) {
      _showError('Error running week simulation: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _runScenario(List<DaySimulationScenario> scenarios) async {
    setState(() {
      _isLoading = true;
    });
    try {
      final userId = currentUserUid;
      if (userId.isEmpty) {
        _showError('No authenticated user');
        return;
      }
      await DaySimulator.simulateDay(
        userId: userId,
        date: _simulatedDate,
        scenarios: scenarios,
      );
      _showSuccess('Scenario applied successfully!');
    } catch (e) {
      _showError('Error running scenario: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
}
