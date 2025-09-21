import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:habit_tracker/Helper/utils/flutter_flow_theme.dart';

class GradientButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Gradient gradient;
  final double height;
  final double borderRadius;
  final TextStyle? textStyle;
  final EdgeInsetsGeometry? padding;
  final Widget? icon;

  const GradientButton({
    super.key,
    required this.text,
    required this.onPressed,
    required this.gradient,
    this.height = 52.0,
    this.borderRadius = 40.0,
    this.textStyle,
    this.padding,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: text,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(borderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(borderRadius),
          onTap: onPressed,
          child: Ink(
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(borderRadius),
            ),
            child: Container(
              height: height,
              alignment: Alignment.center,
              padding: padding ?? const EdgeInsets.symmetric(horizontal: 8.0),
              child: Text(
                text,
                style: textStyle ??
                    FlutterFlowTheme.of(context).titleSmall.override(
                      font: GoogleFonts.interTight(),
                      color: FlutterFlowTheme.of(context).secondaryText,
                    ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
