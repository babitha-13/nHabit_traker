import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class CustomTabDecorator extends StatelessWidget {
  final Widget child;
  final bool isActive;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;

  const CustomTabDecorator({
    super.key,
    required this.child,
    required this.isActive,
    this.onTap,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        padding:
            padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isActive ? theme.primary : theme.secondaryBackground,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(12),
          ),
          border: Border(
            bottom: BorderSide(
              color: isActive ? theme.accent1 : Colors.transparent,
              width: 3,
            ),
          ),
          boxShadow: isActive ? theme.neumorphicShadowsRaised : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: isActive ? Colors.white : theme.primaryText,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
          child: child,
        ),
      ),
    );
  }
}
