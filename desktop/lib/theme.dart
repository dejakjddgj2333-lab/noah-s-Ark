import 'package:flutter/material.dart';

/// Design tokens — "Obsidian Precision" (mirrors stitch_ref/web_terminal/DESIGN.md).
abstract final class Mc {
  // Surfaces
  static const canvas = Color(0xFF070D1C); // page background
  static const surface = Color(0xFF0D1528); // sidebar / panels
  static const card = Color(0xFF121D34); // cards, table rows
  static const cardHigh = Color(0xFF1A2742); // hover / selected rows / badges
  static const hairline = Color(0xFF34415E); // 1px structural borders

  // Accents
  static const cobalt = Color(0xFF2E5CFF); // the ONLY primary accent
  static const cobaltSoft = Color(0xFF82A4FF);

  // Text
  static const ink = Color(0xFFF0F0FF); // primary text
  static const muted = Color(0xFF9EA0B2); // secondary text / table headers

  // Semantics — 状态色 (成功/失败等, 不随涨跌方案变化)
  static const bull = Color(0xFF00E388);
  static const bear = Color(0xFFFF5F6D);
  static const amber = Color(0xFFF7B733);

  // 涨跌语义色: 默认绿涨红跌 (国际); cnScheme=true 时红涨绿跌 (国内习惯)。
  // 仅用于涨/跌含义 (涨跌百分比、K线、走势), 状态徽标仍用 bull/bear。
  static bool cnScheme = false;
  static Color get up => cnScheme ? bear : bull;
  static Color get down => cnScheme ? bull : bear;

  // Metrics
  static const sidebarWidth = 240.0;
  static const topbarHeight = 56.0;
  static const cardRadius = 12.0;
  static const cardPadding = 18.0;

  static Color upDown(num? v) => (v ?? 0) >= 0 ? up : down;

  // Typography helpers
  static TextStyle display(double size,
          {FontWeight w = FontWeight.w600, Color color = ink}) =>
      TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: size,
          fontWeight: w,
          color: color,
          letterSpacing: -0.3,
          height: 1.2);

  static TextStyle body(double size,
          {FontWeight w = FontWeight.w400, Color color = ink}) =>
      TextStyle(
          fontFamily: 'Inter',
          fontSize: size,
          fontWeight: w,
          color: color,
          height: 1.5);

  /// All numbers / prices / timestamps — JetBrains Mono, usually right-aligned.
  static TextStyle mono(double size,
          {FontWeight w = FontWeight.w500, Color color = ink}) =>
      TextStyle(
          fontFamily: 'JetBrainsMono',
          fontSize: size,
          fontWeight: w,
          color: color,
          height: 1.4);

  /// Small uppercase mono label, e.g. `MARKET`, `WHALE ALERT`.
  static TextStyle tag({Color? color}) => TextStyle(
      fontFamily: 'JetBrainsMono',
      fontSize: 10,
      fontWeight: FontWeight.w600,
      color: color ?? muted,
      letterSpacing: 1.5);

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: canvas,
        fontFamily: 'Inter',
        colorScheme: const ColorScheme.dark(
          primary: cobalt,
          surface: surface,
          onSurface: ink,
          error: bear,
        ),
        dividerColor: hairline,
        splashColor: cobalt.withValues(alpha: 0.08),
        hoverColor: cardHigh.withValues(alpha: 0.6),
        textSelectionTheme: const TextSelectionThemeData(
          cursorColor: cobaltSoft,
          selectionColor: Color(0x332E5CFF),
        ),
        scrollbarTheme: ScrollbarThemeData(
          thumbColor: WidgetStateProperty.all(hairline),
          thickness: WidgetStateProperty.all(6),
          radius: const Radius.circular(3),
        ),
      );
}
