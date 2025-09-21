// ignore_for_file: overridden_fields, annotate_overrides

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:shared_preferences/shared_preferences.dart';

const kThemeModeKey = '__theme_mode__';

SharedPreferences? _prefs;

abstract class FlutterFlowTheme {
  static Future initialize() async =>
      _prefs = await SharedPreferences.getInstance();

  static ThemeMode get themeMode {
    final darkMode = _prefs?.getBool(kThemeModeKey);
    return darkMode == null
        ? ThemeMode.system
        : darkMode
            ? ThemeMode.dark
            : ThemeMode.light;
  }

  static void saveThemeMode(ThemeMode mode) => mode == ThemeMode.system
      ? _prefs?.remove(kThemeModeKey)
      : _prefs?.setBool(kThemeModeKey, mode == ThemeMode.dark);

  static FlutterFlowTheme of(BuildContext context) {
    return Theme.of(context).brightness == Brightness.dark
        ? DarkModeTheme()
        : LightModeTheme();
  }

  @Deprecated('Use primary instead')
  Color get primaryColor => primary;
  @Deprecated('Use secondary instead')
  Color get secondaryColor => secondary;
  @Deprecated('Use tertiary instead')
  Color get tertiaryColor => tertiary;

  late Color primary;
  late Color secondary;
  late Color tertiary;
  late Color alternate;
  late Color primaryText;
  late Color secondaryText;
  late Color tertiaryText;
  late Color primaryBackground;
  late Color secondaryBackground;
  late Color accent1;
  late Color accent2;
  late Color accent3;
  late Color accent4;
  late Color success;
  late Color warning;
  late Color error;
  late Color info;

  // Neumorphic tokens (available across themes)
  late double cardRadius;
  late double buttonRadius;
  late double chipRadius;
  late Color surfaceBorderColor;
  late List<BoxShadow> neumorphicShadowsRaised;

  // Gradient helpers expected on all themes
  LinearGradient get neumorphicGradient;
  LinearGradient get neumorphicGradientAlt;
  LinearGradient get neumorphicGradientSubtle;
  LinearGradient get primaryButtonGradient;
  LinearGradient get tabIndicatorGradient;
  RadialGradient get neumorphicRadialGradient;
  LinearGradient? get headerSheenGradient => null;

  @Deprecated('Use displaySmallFamily instead')
  String get title1Family => displaySmallFamily;
  @Deprecated('Use displaySmall instead')
  TextStyle get title1 => displaySmall;
  @Deprecated('Use headlineMediumFamily instead')
  String get title2Family => headlineMediumFamily;
  @Deprecated('Use headlineMedium instead')
  TextStyle get title2 => headlineMedium;
  @Deprecated('Use titleMediumFamily instead')
  String get title3Family => titleMediumFamily;
  @Deprecated('Use titleMedium instead')
  TextStyle get title3 => titleMedium;
  @Deprecated('Use titleSmallFamily instead')
  String get subtitle1Family => titleSmallFamily;
  @Deprecated('Use titleSmall instead')
  TextStyle get subtitle1 => titleSmall;
  @Deprecated('Use bodyMediumFamily instead')
  String get subtitle2Family => bodyMediumFamily;
  @Deprecated('Use bodyMedium instead')
  TextStyle get subtitle2 => bodyMedium;
  @Deprecated('Use bodyMediumFamily instead')
  String get bodyText1Family => bodyMediumFamily;
  @Deprecated('Use bodyMedium instead')
  TextStyle get bodyText1 => bodyMedium;
  @Deprecated('Use bodySmallFamily instead')
  String get bodyText2Family => bodySmallFamily;
  @Deprecated('Use bodySmall instead')
  TextStyle get bodyText2 => bodySmall;

  String get displayLargeFamily => typography.displayLargeFamily;
  bool get displayLargeIsCustom => typography.displayLargeIsCustom;
  TextStyle get displayLarge => typography.displayLarge;
  String get displayMediumFamily => typography.displayMediumFamily;
  bool get displayMediumIsCustom => typography.displayMediumIsCustom;
  TextStyle get displayMedium => typography.displayMedium;
  String get displaySmallFamily => typography.displaySmallFamily;
  bool get displaySmallIsCustom => typography.displaySmallIsCustom;
  TextStyle get displaySmall => typography.displaySmall;
  String get headlineLargeFamily => typography.headlineLargeFamily;
  bool get headlineLargeIsCustom => typography.headlineLargeIsCustom;
  TextStyle get headlineLarge => typography.headlineLarge;
  String get headlineMediumFamily => typography.headlineMediumFamily;
  bool get headlineMediumIsCustom => typography.headlineMediumIsCustom;
  TextStyle get headlineMedium => typography.headlineMedium;
  String get headlineSmallFamily => typography.headlineSmallFamily;
  bool get headlineSmallIsCustom => typography.headlineSmallIsCustom;
  TextStyle get headlineSmall => typography.headlineSmall;
  String get titleLargeFamily => typography.titleLargeFamily;
  bool get titleLargeIsCustom => typography.titleLargeIsCustom;
  TextStyle get titleLarge => typography.titleLarge;
  String get titleMediumFamily => typography.titleMediumFamily;
  bool get titleMediumIsCustom => typography.titleMediumIsCustom;
  TextStyle get titleMedium => typography.titleMedium;
  String get titleSmallFamily => typography.titleSmallFamily;
  bool get titleSmallIsCustom => typography.titleSmallIsCustom;
  TextStyle get titleSmall => typography.titleSmall;
  String get labelLargeFamily => typography.labelLargeFamily;
  bool get labelLargeIsCustom => typography.labelLargeIsCustom;
  TextStyle get labelLarge => typography.labelLarge;
  String get labelMediumFamily => typography.labelMediumFamily;
  bool get labelMediumIsCustom => typography.labelMediumIsCustom;
  TextStyle get labelMedium => typography.labelMedium;
  String get labelSmallFamily => typography.labelSmallFamily;
  bool get labelSmallIsCustom => typography.labelSmallIsCustom;
  TextStyle get labelSmall => typography.labelSmall;
  String get bodyLargeFamily => typography.bodyLargeFamily;
  bool get bodyLargeIsCustom => typography.bodyLargeIsCustom;
  TextStyle get bodyLarge => typography.bodyLarge;
  String get bodyMediumFamily => typography.bodyMediumFamily;
  bool get bodyMediumIsCustom => typography.bodyMediumIsCustom;
  TextStyle get bodyMedium => typography.bodyMedium;
  String get bodySmallFamily => typography.bodySmallFamily;
  bool get bodySmallIsCustom => typography.bodySmallIsCustom;
  TextStyle get bodySmall => typography.bodySmall;

  Typography get typography => ThemeTypography(this);
}

class LightModeTheme extends FlutterFlowTheme {
  @Deprecated('Use primary instead')
  Color get primaryColor => primary;
  @Deprecated('Use secondary instead')
  Color get secondaryColor => secondary;
  @Deprecated('Use tertiary instead')
  Color get tertiaryColor => tertiary;

  // Slate + Copper (editorial, sophisticated)
  late Color primary = const Color(0xFF2D3A43); // Slate
  late Color secondary = const Color(0xFF7D8A96); // Cool grey
  late Color tertiary = const Color(0xFFDDE3EA); // Soft slate tint
  late Color alternate = const Color(0xFFD1D5DB); // More visible gray
  late Color primaryText = const Color(0xFF2C2C2C);
  late Color secondaryText = const Color(0xFF7A7A7A);
  late Color tertiaryText = const Color(0xFF2C2C2C);
  late Color primaryBackground = const Color(0xFFF0EDE8); // Darker warm base
  late Color secondaryBackground =
      const Color(0xFFFFFFFF); // Pure white sections
  late Color accent1 = const Color(0xFFC57B57); // Copper (achievements)
  late Color accent2 = const Color(0xFFE7DAD0); // Light sand
  late Color accent3 = const Color(0xFFB4BEC8); // Neutral cool
  late Color accent4 = const Color(0xFF8F9AA5); // Muted slate
  late Color success =
      const Color(0xFFC57B57); // Copper as success (per choice)
  late Color warning = const Color(0xFFF59E0B); // Amber
  late Color error = const Color(0xFFEF4444); // Red
  late Color info = const Color(0xFFA0AEC0); // Cool grey

  // Neumorphic tokens (light)
  late double cardRadius = 20.0;
  late double buttonRadius = 16.0;
  late double chipRadius = 12.0;
  late Color surfaceBorderColor = const Color(0x0A000000); // 4% black
  late List<BoxShadow> neumorphicShadowsRaised = [
    BoxShadow(
      color: Colors.white.withOpacity(0.9),
      offset: const Offset(-6, -6),
      blurRadius: 14,
    ),
    BoxShadow(
      color: const Color(0xFFC9D2E1).withOpacity(0.7),
      offset: const Offset(6, 6),
      blurRadius: 16,
    ),
  ];

  // Gradient helpers
  LinearGradient get neumorphicGradient => const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFFAF9F7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  LinearGradient get primaryButtonGradient => const LinearGradient(
        colors: [Color(0xFF2D3A43), Color(0xFF405460)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  LinearGradient get tabIndicatorGradient => const LinearGradient(
        colors: [Color(0xFFC57B57), Color(0xFFE7DAD0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  RadialGradient get neumorphicRadialGradient => const RadialGradient(
        colors: [Color(0xFFFBF8F4), Color(0xFFFFFFFF)],
        center: Alignment.topCenter,
        radius: 3.5,
      );

  // Additional neumorphic gradients for variety
  LinearGradient get neumorphicGradientAlt => const LinearGradient(
        colors: [Color(0xFFFDFBF8), Color(0xFFF8F5F1)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get neumorphicGradientSubtle => const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFF9F7F4)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  // Subtle AppBar sheen (slate to slightly lighter slate)
  @override
  LinearGradient? get headerSheenGradient => const LinearGradient(
        colors: [Color(0xFF2D3A43), Color(0xFF3A4852)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
}

abstract class Typography {
  String get displayLargeFamily;
  bool get displayLargeIsCustom;
  TextStyle get displayLarge;
  String get displayMediumFamily;
  bool get displayMediumIsCustom;
  TextStyle get displayMedium;
  String get displaySmallFamily;
  bool get displaySmallIsCustom;
  TextStyle get displaySmall;
  String get headlineLargeFamily;
  bool get headlineLargeIsCustom;
  TextStyle get headlineLarge;
  String get headlineMediumFamily;
  bool get headlineMediumIsCustom;
  TextStyle get headlineMedium;
  String get headlineSmallFamily;
  bool get headlineSmallIsCustom;
  TextStyle get headlineSmall;
  String get titleLargeFamily;
  bool get titleLargeIsCustom;
  TextStyle get titleLarge;
  String get titleMediumFamily;
  bool get titleMediumIsCustom;
  TextStyle get titleMedium;
  String get titleSmallFamily;
  bool get titleSmallIsCustom;
  TextStyle get titleSmall;
  String get labelLargeFamily;
  bool get labelLargeIsCustom;
  TextStyle get labelLarge;
  String get labelMediumFamily;
  bool get labelMediumIsCustom;
  TextStyle get labelMedium;
  String get labelSmallFamily;
  bool get labelSmallIsCustom;
  TextStyle get labelSmall;
  String get bodyLargeFamily;
  bool get bodyLargeIsCustom;
  TextStyle get bodyLarge;
  String get bodyMediumFamily;
  bool get bodyMediumIsCustom;
  TextStyle get bodyMedium;
  String get bodySmallFamily;
  bool get bodySmallIsCustom;
  TextStyle get bodySmall;
}

class ThemeTypography extends Typography {
  ThemeTypography(this.theme);

  final FlutterFlowTheme theme;

  String get displayLargeFamily => 'Inter Tight';
  bool get displayLargeIsCustom => false;
  TextStyle get displayLarge => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 64.0,
      );
  String get displayMediumFamily => 'Inter Tight';
  bool get displayMediumIsCustom => false;
  TextStyle get displayMedium => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 44.0,
      );
  String get displaySmallFamily => 'Inter Tight';
  bool get displaySmallIsCustom => false;
  TextStyle get displaySmall => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 36.0,
      );
  String get headlineLargeFamily => 'Inter Tight';
  bool get headlineLargeIsCustom => false;
  TextStyle get headlineLarge => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 32.0,
      );
  String get headlineMediumFamily => 'Inter Tight';
  bool get headlineMediumIsCustom => false;
  TextStyle get headlineMedium => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 28.0,
      );
  String get headlineSmallFamily => 'Inter Tight';
  bool get headlineSmallIsCustom => false;
  TextStyle get headlineSmall => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 24.0,
      );
  String get titleLargeFamily => 'Inter Tight';
  bool get titleLargeIsCustom => false;
  TextStyle get titleLarge => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 20.0,
      );
  String get titleMediumFamily => 'Inter Tight';
  bool get titleMediumIsCustom => false;
  TextStyle get titleMedium => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 18.0,
      );
  String get titleSmallFamily => 'Inter Tight';
  bool get titleSmallIsCustom => false;
  TextStyle get titleSmall => GoogleFonts.interTight(
        color: theme.primaryText,
        fontWeight: FontWeight.w600,
        fontSize: 16.0,
      );
  String get labelLargeFamily => 'Inter';
  bool get labelLargeIsCustom => false;
  TextStyle get labelLarge => GoogleFonts.inter(
        color: theme.secondaryText,
        fontWeight: FontWeight.normal,
        fontSize: 16.0,
      );
  String get labelMediumFamily => 'Inter';
  bool get labelMediumIsCustom => false;
  TextStyle get labelMedium => GoogleFonts.inter(
        color: theme.secondaryText,
        fontWeight: FontWeight.normal,
        fontSize: 14.0,
      );
  String get labelSmallFamily => 'Inter';
  bool get labelSmallIsCustom => false;
  TextStyle get labelSmall => GoogleFonts.inter(
        color: theme.secondaryText,
        fontWeight: FontWeight.normal,
        fontSize: 12.0,
      );
  String get bodyLargeFamily => 'Inter';
  bool get bodyLargeIsCustom => false;
  TextStyle get bodyLarge => GoogleFonts.inter(
        color: theme.primaryText,
        fontWeight: FontWeight.normal,
        fontSize: 16.0,
      );
  String get bodyMediumFamily => 'Inter';
  bool get bodyMediumIsCustom => false;
  TextStyle get bodyMedium => GoogleFonts.inter(
        color: theme.primaryText,
        fontWeight: FontWeight.normal,
        fontSize: 14.0,
      );
  String get bodySmallFamily => 'Inter';
  bool get bodySmallIsCustom => false;
  TextStyle get bodySmall => GoogleFonts.inter(
        color: theme.primaryText,
        fontWeight: FontWeight.normal,
        fontSize: 12.0,
      );
}

class DarkModeTheme extends FlutterFlowTheme {
  @Deprecated('Use primary instead')
  Color get primaryColor => primary;
  @Deprecated('Use secondary instead')
  Color get secondaryColor => secondary;
  @Deprecated('Use tertiary instead')
  Color get tertiaryColor => tertiary;

  late Color primary = const Color(0xFF7ED957); // Pastel Green
  late Color secondary = const Color(0xFFFFB877); // Pastel Orange
  late Color tertiary = const Color(0xFFB2F7EF); // Soft Aqua
  late Color alternate = const Color(0xFF23272A); // Deep Grey
  late Color primaryText = const Color(0xFFF9FAFB); // Soft White
  late Color secondaryText = const Color(0xFFB0BEC5); // Soft Blue Grey
  late Color tertiaryText = const Color(0xFFF9FAFB); // Soft White
  late Color primaryBackground = const Color(0xFF181C1F); // Very Dark Grey
  late Color secondaryBackground = const Color(0xFF23272A); // Deep Grey
  late Color accent1 = const Color(0xFF2E7D32); // Dark Green
  late Color accent2 = const Color(0xFFFFB300); // Orange
  late Color accent3 = const Color(0xFFB2F7EF); // Soft Aqua
  late Color accent4 = const Color(0xFF6D6D6D); // Muted Grey
  late Color success = const Color(0xFF43A047);
  late Color warning = const Color(0xFFFFB300);
  late Color error = const Color(0xFFFF7043);
  late Color info = const Color(0xFFB2F7EF);

  // Neumorphic tokens (dark)
  late double cardRadius = 20.0;
  late double buttonRadius = 16.0;
  late double chipRadius = 12.0;
  late Color surfaceBorderColor = const Color(0x0FFFFFFF); // 6% white
  late List<BoxShadow> neumorphicShadowsRaised = [
    BoxShadow(
      color: Colors.white.withOpacity(0.06),
      offset: const Offset(-6, -6),
      blurRadius: 14,
    ),
    BoxShadow(
      color: Colors.black.withOpacity(0.35),
      offset: const Offset(6, 6),
      blurRadius: 16,
    ),
  ];

  LinearGradient get neumorphicGradient => const LinearGradient(
        colors: [Color(0xFF23272A), Color(0xFF181C1F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  LinearGradient get primaryButtonGradient => const LinearGradient(
        colors: [Color(0xFF7ED957), Color(0xFFB2F7EF)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
  LinearGradient get tabIndicatorGradient => const LinearGradient(
        colors: [Color(0xFFFFB877), Color(0xFFFFF3E0)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  RadialGradient get neumorphicRadialGradient => const RadialGradient(
        colors: [Color(0xFF23272A), Color(0xFF181C1F)],
        center: Alignment.topCenter,
        radius: 3.5,
      );

  // Additional neumorphic gradients for variety (dark mode)
  LinearGradient get neumorphicGradientAlt => const LinearGradient(
        colors: [Color(0xFF1F2326), Color(0xFF181C1F)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get neumorphicGradientSubtle => const LinearGradient(
        colors: [Color(0xFF23272A), Color(0xFF1C2024)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  @override
  LinearGradient? get headerSheenGradient => const LinearGradient(
        colors: [Color(0xFF23272A), Color(0xFF2A3136)],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );
}

extension TextStyleHelper on TextStyle {
  TextStyle override({
    TextStyle? font,
    String? fontFamily,
    Color? color,
    double? fontSize,
    FontWeight? fontWeight,
    double? letterSpacing,
    FontStyle? fontStyle,
    bool useGoogleFonts = false,
    TextDecoration? decoration,
    double? lineHeight,
    List<Shadow>? shadows,
    String? package,
  }) {
    if (useGoogleFonts && fontFamily != null) {
      font = GoogleFonts.getFont(fontFamily,
          fontWeight: fontWeight ?? this.fontWeight,
          fontStyle: fontStyle ?? this.fontStyle);
    }

    return font != null
        ? font.copyWith(
            color: color ?? this.color,
            fontSize: fontSize ?? this.fontSize,
            letterSpacing: letterSpacing ?? this.letterSpacing,
            fontWeight: fontWeight ?? this.fontWeight,
            fontStyle: fontStyle ?? this.fontStyle,
            decoration: decoration,
            height: lineHeight,
            shadows: shadows,
          )
        : copyWith(
            fontFamily: fontFamily,
            package: package,
            color: color,
            fontSize: fontSize,
            letterSpacing: letterSpacing,
            fontWeight: fontWeight,
            fontStyle: fontStyle,
            decoration: decoration,
            height: lineHeight,
            shadows: shadows,
          );
  }
}
