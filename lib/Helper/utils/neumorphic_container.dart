import 'package:flutter/material.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class NeumorphicContainer extends StatelessWidget {
  const NeumorphicContainer({
    Key? key,
    required this.child,
    this.margin,
    this.padding,
    this.radius,
    this.gradient,
    this.shadows,
    this.borderColor,
    this.compact = false,
  }) : super(key: key);

  final Widget child;
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;
  final double? radius;
  final Gradient? gradient;
  final List<BoxShadow>? shadows;
  final Color? borderColor;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = FlutterFlowTheme.of(context);
    final borderRadius = BorderRadius.circular(radius ?? theme.cardRadius);

    final EdgeInsetsGeometry effectivePadding = padding ??
        (compact
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 4)
            : EdgeInsets.zero);
    final EdgeInsetsGeometry? effectiveMargin = margin ??
        (compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 2)
            : null);

    return Container(
      margin: effectiveMargin,
      decoration: BoxDecoration(
        gradient: gradient ?? theme.neumorphicGradient,
        borderRadius: borderRadius,
        boxShadow: compact ? [] : (shadows ?? theme.neumorphicShadowsRaised),
        border: Border.all(
          color: borderColor ?? theme.surfaceBorderColor,
          width: compact ? 0.6 : 1,
        ),
      ),
      child: Padding(
        padding: effectivePadding,
        child: child,
      ),
    );
  }
}
