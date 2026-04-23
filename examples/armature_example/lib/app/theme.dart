import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _seed = Colors.indigo;

ThemeData _theme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
  );
  return base.copyWith(textTheme: GoogleFonts.interTextTheme(base.textTheme));
}

ThemeData buildLightTheme() => _theme(Brightness.light);

ThemeData buildDarkTheme() => _theme(Brightness.dark);
