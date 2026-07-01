import 'package:flutter/material.dart';

/// A dark, cinema-inspired theme for The Marquee.
ThemeData buildTheme() {
  const seed = Color(0xFFE50914); // marquee red
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF0E0E12),
    appBarTheme: const AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
  );
}
