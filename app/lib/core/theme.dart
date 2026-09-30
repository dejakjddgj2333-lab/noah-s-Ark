import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// 明策 MINGCE design tokens — extracted from Stitch screens (cobalt terminal theme).
/// Reference: stitch_ref/*.html tailwind configs.
class McColors {
  McColors._();

  // Surfaces
  static const surface = Color(0xFF10131A);
  static const surfaceDim = Color(0xFF10131A);
  static const surfaceContainerLowest = Color(0xFF0B0E14);
  static const surfaceContainerLow = Color(0xFF191C22);
  static const surfaceContainer = Color(0xFF1D2026);
  static const surfaceContainerHigh = Color(0xFF272A31);
  static const surfaceContainerHighest = Color(0xFF32353C);
  static const surfaceVariant = Color(0xFF32353C);

  // Content
  static const onSurface = Color(0xFFE1E2EB);
  static const onSurfaceVariant = Color(0xFF9EA0B2);
  static const outline = Color(0xFF434656);
  static const outlineVariant = Color(0xFF2B2E3A);

  // Brand (cobalt terminal)
  static const primary = Color(0xFFB8C3FF);
  static const primaryContainer = Color(0xFF2E5CFF);
  static const primarySoft = Color(0xFF82A4FF);
  static const onPrimaryContainer = Color(0xFFF0F0FF);

  // Telemetry
  static const secondary = Color(0xFF00D7F4); // cyan
  static const tertiary = Color(0xFF00E388);
  static const bull = Color(0xFF00E388); // up / long / positive
  static const bear = Color(0xFFFF6363); // down / short / negative
  static const error = Color(0xFFFFB4AB);

  // Gold (news screen variant)
  static const gold = Color(0xFFD4AF37);
  static const goldBright = Color(0xFFF2CA50);

  static Color alpha(Color c, double opacity) =>
      c.withValues(alpha: opacity);
}

/// Text styles. display = Space Grotesk, mono = JetBrains Mono, sans = Inter.
class McText {
  McText._();

  // Global minimum font size: 用户看不清, clamp anything below 12 up to 12.
  static double _fs(double size) => size.clamp(12.0, double.infinity);

  static TextStyle display({
    double size = 16,
    FontWeight weight = FontWeight.w600,
    Color color = McColors.onSurface,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.spaceGrotesk(
        fontSize: _fs(size),
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle mono({
    double size = 12,
    FontWeight weight = FontWeight.w400,
    Color color = McColors.onSurface,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: _fs(size),
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );

  static TextStyle sans({
    double size = 13,
    FontWeight weight = FontWeight.w400,
    Color color = McColors.onSurface,
    double? height,
    double? letterSpacing,
  }) =>
      GoogleFonts.inter(
        fontSize: _fs(size),
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
}

ThemeData buildMcTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: McColors.surface,
    colorScheme: const ColorScheme.dark(
      surface: McColors.surface,
      primary: McColors.primary,
      primaryContainer: McColors.primaryContainer,
      secondary: McColors.secondary,
      tertiary: McColors.tertiary,
      error: McColors.error,
      onSurface: McColors.onSurface,
      onSurfaceVariant: McColors.onSurfaceVariant,
      outline: McColors.outline,
      outlineVariant: McColors.outlineVariant,
      surfaceContainerLowest: McColors.surfaceContainerLowest,
      surfaceContainerLow: McColors.surfaceContainerLow,
      surfaceContainer: McColors.surfaceContainer,
      surfaceContainerHigh: McColors.surfaceContainerHigh,
      surfaceContainerHighest: McColors.surfaceContainerHighest,
    ),
    textTheme: GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: McColors.onSurface,
      displayColor: McColors.onSurface,
    ),
    splashFactory: InkSparkle.splashFactory,
    dividerTheme: const DividerThemeData(
      color: McColors.outlineVariant,
      thickness: 1,
      space: 1,
    ),
  );
}
