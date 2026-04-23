import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Seed color used to derive both light and dark Material 3 schemes.
const Color _seed = Color(0xFF4F46E5);

class AppTheme {
  const AppTheme._();

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
    );
    // Inter for all prose. Google Fonts fetches the variable font from
    // the Google Fonts CDN on first use and caches it — subsequent
    // renders hit the cache.
    return base.copyWith(
      textTheme: GoogleFonts.interTextTheme(base.textTheme),
      primaryTextTheme: GoogleFonts.interTextTheme(base.primaryTextTheme),
    );
  }

  /// JetBrains Mono for code samples, inline code, and code-block
  /// headers. Returned as a factory (not a constant) because
  /// `GoogleFonts` lazy-loads the font on first call.
  static TextStyle codeTextStyle({
    double fontSize = 13,
    double height = 1.55,
    Color? color,
    FontWeight? fontWeight,
  }) {
    return GoogleFonts.jetBrainsMono(
      fontSize: fontSize,
      height: height,
      color: color,
      fontWeight: fontWeight,
    );
  }
}
