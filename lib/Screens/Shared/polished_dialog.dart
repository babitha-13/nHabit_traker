import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/Helpers/flutter_flow_theme.dart';

/// A polished dialog component with neumorphic styling that matches the app theme
class PolishedDialog extends StatelessWidget {
  final String? title;
  final Widget? content;
  final List<Widget>? actions;
  final double? maxWidth;
  final double? maxHeight;
  final EdgeInsetsGeometry? contentPadding;
  final bool barrierDismissible;

  const PolishedDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.maxWidth,
    this.maxHeight,
    this.contentPadding,
    this.barrierDismissible = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: maxWidth ?? 500,
          maxHeight: maxHeight ?? 600,
        ),
        decoration: BoxDecoration(
          gradient: theme.neumorphicGradient,
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
            // Header with title and close button
            if (title != null) _buildHeader(context, theme),
            // Content
            if (content != null)
              Flexible(
                child: Padding(
                  padding: contentPadding ??
                      const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: content!,
                ),
              ),
            // Actions
            if (actions != null) _buildActions(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FlutterFlowTheme theme) {
    return Container(
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
              title!,
              style: theme.titleLarge.override(
                fontFamily: 'Readex Pro',
                fontWeight: FontWeight.w600,
                color: theme.primaryText,
              ),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: Icon(
              Icons.close,
              color: theme.secondaryText,
              size: 20,
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context, FlutterFlowTheme theme) {
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
        mainAxisAlignment: MainAxisAlignment.end,
        children: actions!
            .map((action) => Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: action,
                ))
            .toList(),
      ),
    );
  }
}

/// A polished alert dialog with consistent styling
class PolishedAlertDialog extends StatelessWidget {
  final String title;
  final String content;
  final String? confirmText;
  final String? cancelText;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final Color? confirmColor;
  final bool isDestructive;

  const PolishedAlertDialog({
    super.key,
    required this.title,
    required this.content,
    this.confirmText,
    this.cancelText,
    this.onConfirm,
    this.onCancel,
    this.confirmColor,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return PolishedDialog(
      title: title,
      content: Text(
        content,
        style: theme.bodyMedium.override(
          color: theme.secondaryText,
        ),
      ),
      actions: [
        if (cancelText != null)
          OutlinedButton(
            onPressed: onCancel ?? () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              side: BorderSide(color: theme.surfaceBorderColor),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.buttonRadius),
              ),
            ),
            child: Text(
              cancelText!,
              style: TextStyle(color: theme.secondaryText),
            ),
          ),
        if (confirmText != null)
          ElevatedButton(
            onPressed: onConfirm ?? () => Navigator.of(context).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  confirmColor ?? (isDestructive ? theme.error : theme.primary),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(theme.buttonRadius),
              ),
              elevation: 0,
            ),
            child: Text(
              confirmText!,
              style: const TextStyle(color: Colors.white),
            ),
          ),
      ],
    );
  }
}

/// Helper function to show a polished alert dialog
Future<bool?> showPolishedAlertDialog({
  required BuildContext context,
  required String title,
  required String content,
  String? confirmText,
  String? cancelText,
  VoidCallback? onConfirm,
  VoidCallback? onCancel,
  Color? confirmColor,
  bool isDestructive = false,
}) async {
  return await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) => PolishedAlertDialog(
      title: title,
      content: content,
      confirmText: confirmText,
      cancelText: cancelText,
      onConfirm: onConfirm,
      onCancel: onCancel,
      confirmColor: confirmColor,
      isDestructive: isDestructive,
    ),
  );
}

/// Helper function to show a polished dialog
Future<T?> showPolishedDialog<T>({
  required BuildContext context,
  String? title,
  Widget? content,
  List<Widget>? actions,
  double? maxWidth,
  double? maxHeight,
  EdgeInsetsGeometry? contentPadding,
  bool barrierDismissible = true,
}) async {
  return await showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (context) => PolishedDialog(
      title: title,
      content: content,
      actions: actions,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      contentPadding: contentPadding,
      barrierDismissible: barrierDismissible,
    ),
  );
}
