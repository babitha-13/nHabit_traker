import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';
import 'frequency_config_widget.dart';
import 'frequency_config_model.dart';

/// Dialog for configuring task/habit frequency
class FrequencyConfigDialog extends StatefulWidget {
  final FrequencyConfig initialConfig;
  final Set<FrequencyType>? allowedTypes;
  const FrequencyConfigDialog({
    super.key,
    required this.initialConfig,
    this.allowedTypes,
  });
  @override
  State<FrequencyConfigDialog> createState() => _FrequencyConfigDialogState();
}

class _FrequencyConfigDialogState extends State<FrequencyConfigDialog> {
  late FrequencyConfig _config;
  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  void _updateConfig(FrequencyConfig newConfig) {
    setState(() {
      _config = newConfig;
    });
  }

  void _save() {
    Navigator.pop(context, _config);
  }

  void _cancel() {
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 500,
          maxHeight: 600,
        ),
        decoration: BoxDecoration(
          color: theme.secondaryBackground,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              offset: const Offset(0, 2),
              blurRadius: 4,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(24, 24, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.surfaceBorderColor,
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Frequency Configuration',
                      style: theme.titleLarge.override(
                        fontFamily: 'Readex Pro',
                        fontWeight: FontWeight.w600,
                        color: theme.primaryText,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _cancel,
                    icon: Icon(Icons.close, color: theme.secondaryText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                  ),
                ],
              ),
            ),
            // Scrollable content
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                child: SingleChildScrollView(
                  child: FrequencyConfigWidget(
                    initialConfig: _config,
                    onChanged: _updateConfig,
                    allowedTypes: widget.allowedTypes,
                  ),
                ),
              ),
            ),
            // Action buttons
            _buildActionButtons(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(FlutterFlowTheme theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: theme.surfaceBorderColor,
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _cancel,
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                side: BorderSide(color: theme.surfaceBorderColor),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
              ),
              child: Text(
                'Cancel',
                style: TextStyle(color: theme.secondaryText),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(theme.buttonRadius),
                ),
                elevation: 0,
              ),
              child: Text(
                'Save',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to show the frequency configuration dialog
Future<FrequencyConfig?> showFrequencyConfigDialog({
  required BuildContext context,
  FrequencyConfig? initialConfig,
  Set<FrequencyType>? allowedTypes,
}) async {
  return await showDialog<FrequencyConfig>(
    context: context,
    barrierDismissible: false,
    builder: (context) => FrequencyConfigDialog(
      initialConfig:
          initialConfig ?? FrequencyConfig(type: FrequencyType.everyXPeriod),
      allowedTypes: allowedTypes,
    ),
  );
}
