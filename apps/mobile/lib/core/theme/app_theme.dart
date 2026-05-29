import 'package:flutter/material.dart';

class AppTheme {
  // ── Brand colours ──────────────────────────────────────────────────
  static const Color primary   = Color(0xFF003b8a); // navy
  static const Color secondary = Color(0xFF0cc0df); // cyan
  static const Color accent    = Color(0xFFff00bf); // hot-pink CTA

  static ThemeData theme = ThemeData(
    useMaterial3: true,
    fontFamily: 'Garet',

    colorScheme: const ColorScheme(
      brightness:   Brightness.light,
      primary:      primary,
      onPrimary:    Colors.white,
      secondary:    secondary,
      onSecondary:  Colors.black,
      error:        Colors.red,
      onError:      Colors.white,
      surface:      Colors.white,
      onSurface:    Colors.black,
    ),

    // ── AppBar ────────────────────────────────────────────────────────
    appBarTheme: const AppBarTheme(
      backgroundColor:        primary,
      foregroundColor:        Colors.white,
      centerTitle:            true,
      elevation:              0,
      scrolledUnderElevation: 0,
    ),

    // ── Cards ─────────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFE8EAF6)),
      ),
      margin: EdgeInsets.zero,
    ),

    // ── Inputs ────────────────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F7FA),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFFDDE1EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),

    // ── ElevatedButton — hot-pink CTA ─────────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(
            fontFamily: 'Garet', fontWeight: FontWeight.w600),
      ),
    ),

    // ── OutlinedButton — secondary action ─────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: const BorderSide(color: primary),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        textStyle: const TextStyle(
            fontFamily: 'Garet', fontWeight: FontWeight.w500),
      ),
    ),

    // ── FilledButton ──────────────────────────────────────────────────
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(
            fontFamily: 'Garet', fontWeight: FontWeight.w600),
      ),
    ),

    // ── FAB ───────────────────────────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: Colors.white,
      elevation: 2,
      shape: StadiumBorder(),
    ),

    // ── Bottom NavigationBar ──────────────────────────────────────────
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.black12,
      indicatorColor: primary.withValues(alpha: 0.10),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final sel = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontFamily: 'Garet',
          fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
          color: sel ? primary : Colors.black54,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? primary
              : Colors.black45,
          size: 22,
        );
      }),
    ),

    // ── TabBar ────────────────────────────────────────────────────────
    tabBarTheme: const TabBarThemeData(
      dividerColor:          Colors.transparent,
      indicatorColor:        Colors.white,
      labelColor:            Colors.white,
      unselectedLabelColor:  Colors.white60,
      indicatorSize:         TabBarIndicatorSize.label,
      labelStyle:   TextStyle(fontFamily: 'Garet', fontWeight: FontWeight.w600, fontSize: 14),
      unselectedLabelStyle: TextStyle(fontFamily: 'Garet', fontSize: 14),
    ),

    // ── Chips ─────────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF0F1F8),
      selectedColor: primary,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      showCheckmark: false,
      labelStyle:
          const TextStyle(fontFamily: 'Garet', fontSize: 13),
    ),

    // ── Divider ───────────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: Color(0xFFEEF0F8),
      space: 1,
      thickness: 1,
    ),
  );
}
