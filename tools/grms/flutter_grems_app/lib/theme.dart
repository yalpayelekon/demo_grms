import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const background = Color(0xFF141827);
  const surface = Color(0xFF1C2236);
  const card = Color(0xFF252C42);
  const accent = Color(0xFF6366F1);

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: Brightness.dark,
    surface: surface,
  );
  final textTheme = Typography.material2021(
    platform: TargetPlatform.android,
  ).white.apply(
    fontFamily: 'Arial',
    bodyColor: Colors.white,
    displayColor: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Arial',
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    cardColor: card,
    dividerColor: Colors.white.withOpacity(0.1),
    appBarTheme: const AppBarTheme(
      backgroundColor: surface,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF374151)),
      ),
    ),
  );
}
