import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF147D6F);
  static const primaryDark = Color(0xFF0D5F55);
  static const mint = Color(0xFFDDF3EC);
  static const canvas = Color(0xFFF5F7F6);
  static const ink = Color(0xFF17211F);
  static const muted = Color(0xFF66736F);
  static const border = Color(0xFFDDE4E1);
  static const taken = Color(0xFF198754);
  static const missed = Color(0xFFD54B4B);
  static const skipped = Color(0xFF7B8490);
  static const warning = Color(0xFFE99A2F);

  static const medicinePalette = <Color>[
    Color(0xFF147D6F),
    Color(0xFF4D6EC9),
    Color(0xFF9A5ABD),
    Color(0xFFD66B51),
    Color(0xFFD39A2C),
    Color(0xFF3B8FB8),
  ];
}

ThemeData buildAppTheme() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.canvas,
    visualDensity: VisualDensity.standard,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.canvas,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.ink,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 72,
      backgroundColor: Colors.white,
      indicatorColor: AppColors.mint,
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}
