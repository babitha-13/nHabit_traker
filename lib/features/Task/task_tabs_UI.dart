import 'package:flutter/material.dart';
import 'package:habit_tracker/core/flutter_flow_theme.dart';

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
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? theme.primary : const Color(0xFFF0F0F0),
          borderRadius: BorderRadius.circular(20),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: theme.primary.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: DefaultTextStyle(
          style: TextStyle(
            color: isActive ? Colors.white : theme.primaryText.withValues(alpha: 0.75),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
            fontSize: 13,
            letterSpacing: 0.2,
          ),
          child: child,
        ),
      ),
    );
  }
}
