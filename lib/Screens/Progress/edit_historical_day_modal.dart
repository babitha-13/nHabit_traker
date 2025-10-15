import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/backend/schema/activity_instance_record.dart';
import 'package:habit_tracker/Helper/backend/schema/daily_progress_record.dart';
import 'package:habit_tracker/Helper/backend/historical_edit_service.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';
import 'package:habit_tracker/Helper/flutter_flow/flutter_flow_util.dart';
import 'package:intl/intl.dart';

class EditHistoricalDayModal extends StatefulWidget {
  final DateTime selectedDate;
  final List<ActivityInstanceRecord> habitInstances;
  final DailyProgressRecord? dailyProgress;

  const EditHistoricalDayModal({
    Key? key,
    required this.selectedDate,
    required this.habitInstances,
    this.dailyProgress,
  }) : super(key: key);

  @override
  State<EditHistoricalDayModal> createState() => _EditHistoricalDayModalState();
}

class _EditHistoricalDayModalState extends State<EditHistoricalDayModal> {
  final Map<String, String> _completionStatusChanges = {};
  final Map<String, dynamic> _currentValueChanges = {};
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    // Initialize changes with current values
    for (final instance in widget.habitInstances) {
      _completionStatusChanges[instance.reference.id] =
          instance.completionStatus;
      _currentValueChanges[instance.reference.id] = instance.currentValue;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme),
            Flexible(
              child: _buildContent(theme),
            ),
            _buildFooter(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(FlutterFlowTheme theme) {
    final dateStr = DateFormat('MMM d, yyyy').format(widget.selectedDate);
    final originalPercentage =
        widget.dailyProgress?.completionPercentage ?? 0.0;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.primary,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Edit Day: $dateStr',
                style: theme.titleLarge.override(
                  fontFamily: 'Readex Pro',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Original: ${originalPercentage.toStringAsFixed(0)}% (${widget.dailyProgress?.completedHabits ?? 0}/${widget.dailyProgress?.totalHabits ?? 0} habits)',
            style: theme.bodyMedium.override(
              fontFamily: 'Readex Pro',
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(FlutterFlowTheme theme) {
    if (widget.habitInstances.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.event_busy,
                size: 48,
                color: theme.secondaryText,
              ),
              const SizedBox(height: 16),
              Text(
                'No habits for this day',
                style: theme.titleMedium.override(
                  fontFamily: 'Readex Pro',
                  color: theme.secondaryText,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'There were no habits scheduled for this date.',
                style: theme.bodyMedium.override(
                  fontFamily: 'Readex Pro',
                  color: theme.secondaryText,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.habitInstances.length,
      itemBuilder: (context, index) {
        final instance = widget.habitInstances[index];
        return _buildHabitItem(instance, theme);
      },
    );
  }

  Widget _buildHabitItem(
      ActivityInstanceRecord instance, FlutterFlowTheme theme) {
    final instanceId = instance.reference.id;
    final currentStatus =
        _completionStatusChanges[instanceId] ?? instance.completionStatus;
    final currentValue =
        _currentValueChanges[instanceId] ?? instance.currentValue;

    // For now, assume all habits have a simple quantity target of 1
    // In a real implementation, this would come from the template
    final hasQuantity = true;
    final quantityTarget = 1; // Simplified for now
    final currentQuantity = currentValue is int ? currentValue : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.alternate,
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  instance.templateName,
                  style: theme.titleMedium.override(
                    fontFamily: 'Readex Pro',
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              _buildStatusToggle(instanceId, currentStatus, theme),
            ],
          ),
          const SizedBox(height: 12),
          if (hasQuantity) ...[
            Text(
              'Progress: $currentQuantity / $quantityTarget',
              style: theme.bodyMedium.override(
                fontFamily: 'Readex Pro',
                color: theme.secondaryText,
              ),
            ),
            const SizedBox(height: 8),
            _buildQuantityControls(
                instanceId, currentQuantity, quantityTarget, theme),
          ],
          if (currentStatus == 'completed') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.3)),
              ),
              child: Text(
                'Completed',
                style: theme.bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: Colors.green[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else if (currentStatus == 'skipped') ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Text(
                'Skipped',
                style: theme.bodySmall.override(
                  fontFamily: 'Readex Pro',
                  color: Colors.orange[700],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusToggle(
      String instanceId, String currentStatus, FlutterFlowTheme theme) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildStatusButton(
          instanceId,
          'completed',
          'Completed',
          currentStatus == 'completed',
          Colors.green,
          theme,
        ),
        const SizedBox(width: 8),
        _buildStatusButton(
          instanceId,
          'skipped',
          'Skipped',
          currentStatus == 'skipped',
          Colors.orange,
          theme,
        ),
      ],
    );
  }

  Widget _buildStatusButton(
    String instanceId,
    String status,
    String label,
    bool isSelected,
    Color color,
    FlutterFlowTheme theme,
  ) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _completionStatusChanges[instanceId] = status;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? color : theme.alternate,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.bodySmall.override(
            fontFamily: 'Readex Pro',
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _buildQuantityControls(
    String instanceId,
    int currentQuantity,
    int quantityTarget,
    FlutterFlowTheme theme,
  ) {
    return Row(
      children: [
        IconButton(
          onPressed: currentQuantity > 0
              ? () {
                  setState(() {
                    _currentValueChanges[instanceId] =
                        (currentQuantity - 1).clamp(0, quantityTarget);
                  });
                }
              : null,
          icon: Icon(
            Icons.remove,
            color:
                currentQuantity > 0 ? theme.primaryText : theme.secondaryText,
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: theme.alternate,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            '$currentQuantity',
            style: theme.titleMedium.override(
              fontFamily: 'Readex Pro',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          onPressed: currentQuantity < quantityTarget
              ? () {
                  setState(() {
                    _currentValueChanges[instanceId] =
                        (currentQuantity + 1).clamp(0, quantityTarget);
                  });
                }
              : null,
          icon: Icon(
            Icons.add,
            color: currentQuantity < quantityTarget
                ? theme.primaryText
                : theme.secondaryText,
          ),
        ),
        const Spacer(),
        Text(
          'of $quantityTarget',
          style: theme.bodyMedium.override(
            fontFamily: 'Readex Pro',
            color: theme.secondaryText,
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(FlutterFlowTheme theme) {
    final hasChanges = _hasChanges();
    final newPercentage = _calculateNewPercentage();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.primaryBackground,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border(
          top: BorderSide(color: theme.alternate, width: 1),
        ),
      ),
      child: Column(
        children: [
          if (hasChanges) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: theme.primary, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'New Total: ${newPercentage.toStringAsFixed(0)}%',
                      style: theme.bodyMedium.override(
                        fontFamily: 'Readex Pro',
                        color: theme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.secondaryText,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Cancel',
                    style: theme.titleSmall.override(
                      fontFamily: 'Readex Pro',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveChanges,
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        hasChanges ? theme.primary : theme.secondaryText,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    _isSaving ? 'Saving...' : 'Save Changes',
                    style: theme.titleSmall.override(
                      fontFamily: 'Readex Pro',
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _hasChanges() {
    for (final instance in widget.habitInstances) {
      final instanceId = instance.reference.id;
      if (_completionStatusChanges[instanceId] != instance.completionStatus) {
        return true;
      }
      if (_currentValueChanges[instanceId] != instance.currentValue) {
        return true;
      }
    }
    return false;
  }

  double _calculateNewPercentage() {
    // This is a simplified calculation - in a real implementation,
    // you'd want to recalculate the actual percentage based on the changes
    int completedCount = 0;
    for (final instance in widget.habitInstances) {
      final instanceId = instance.reference.id;
      final status =
          _completionStatusChanges[instanceId] ?? instance.completionStatus;
      if (status == 'completed') {
        completedCount++;
      }
    }
    return widget.habitInstances.isEmpty
        ? 0.0
        : (completedCount / widget.habitInstances.length) * 100;
  }

  Future<void> _saveChanges() async {
    if (!_hasChanges()) {
      Navigator.of(context).pop();
      return;
    }

    setState(() {
      _isSaving = true;
    });

    try {
      final userId = 'szbvXb6Z5TXikcqaU1SfChU6iXl2'; // TODO: Get from auth

      for (final instance in widget.habitInstances) {
        final instanceId = instance.reference.id;
        final newStatus = _completionStatusChanges[instanceId];
        final newValue = _currentValueChanges[instanceId];

        if (newStatus != null && newStatus != instance.completionStatus) {
          await HistoricalEditService.updateHabitInstance(
            instanceId: instance.reference.id,
            userId: userId,
            newCompletionStatus: newStatus,
          );
        }

        if (newValue != null && newValue != instance.currentValue) {
          await HistoricalEditService.updateHabitInstance(
            instanceId: instance.reference.id,
            userId: userId,
            newCurrentValue: newValue,
          );
        }
      }

      if (mounted) {
        Navigator.of(context)
            .pop(true); // Return true to indicate changes were saved
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Historical data updated successfully'),
            backgroundColor: FlutterFlowTheme.of(context).success,
          ),
        );
      }
    } catch (e) {
      print('EditHistoricalDayModal: Error saving changes: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error updating historical data: $e'),
            backgroundColor: FlutterFlowTheme.of(context).error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }
}
