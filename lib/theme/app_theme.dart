import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../domain/anomaly.dart';

/// Ember Almanac palette: charcoal background, ember accents.
abstract final class Ember {
  static const background = Color(0xFF14100E);
  static const surface = Color(0xFF1F1916);
  static const surfaceHigh = Color(0xFF2A221E);
  static const outline = Color(0xFF3D322C);
  static const text = Color(0xFFF3E9DC);
  static const textMuted = Color(0xFFA8998A);

  static const ember = Color(0xFFFF6B2C);
  static const amber = Color(0xFFFFB547);
  static const ash = Color(0xFF6E625A);
  static const calm = Color(0xFF7FB7A4);
  static const extreme = Color(0xFFE5383B);

  /// Sequential scale for fire intensity, 0 → none, 1 → maximum.
  static Color heat(double t) {
    t = t.clamp(0.0, 1.0);
    const stops = [
      Color(0xFF241C18),
      Color(0xFF5A2A17),
      Color(0xFFA63F1B),
      Color(0xFFFF6B2C),
      Color(0xFFFFB547),
      Color(0xFFFFE8A8),
    ];
    final scaled = t * (stops.length - 1);
    final i = scaled.floor().clamp(0, stops.length - 2);
    return Color.lerp(stops[i], stops[i + 1], scaled - i)!;
  }

  static Color forStatus(FireStatus s) => switch (s) {
        FireStatus.below => calm,
        FireStatus.normal => amber,
        FireStatus.above => ember,
        FireStatus.extreme => extreme,
      };

  static String labelForStatus(FireStatus s) => switch (s) {
        FireStatus.below => 'Below normal',
        FireStatus.normal => 'Normal',
        FireStatus.above => 'Above normal',
        FireStatus.extreme => 'Extreme',
      };
}

ThemeData buildEmberTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: const ColorScheme.dark(
      primary: Ember.ember,
      secondary: Ember.amber,
      surface: Ember.surface,
      onSurface: Ember.text,
      outline: Ember.outline,
    ),
    scaffoldBackgroundColor: Ember.background,
  );

  final body = GoogleFonts.ibmPlexSansTextTheme(base.textTheme)
      .apply(bodyColor: Ember.text, displayColor: Ember.text);
  final display = GoogleFonts.frauncesTextTheme(base.textTheme)
      .apply(bodyColor: Ember.text, displayColor: Ember.text);

  return base.copyWith(
    textTheme: body.copyWith(
      displaySmall: display.displaySmall,
      headlineLarge: display.headlineLarge,
      headlineMedium: display.headlineMedium,
      headlineSmall: display.headlineSmall,
      titleLarge: display.titleLarge,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Ember.background,
      foregroundColor: Ember.text,
      elevation: 0,
      titleTextStyle: GoogleFonts.fraunces(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: Ember.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: Ember.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Ember.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Ember.surface,
      indicatorColor: Ember.ember.withValues(alpha: 0.22),
      labelTextStyle: WidgetStatePropertyAll(
        GoogleFonts.ibmPlexSans(fontSize: 12, color: Ember.text),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Ember.surface,
      selectedColor: Ember.ember.withValues(alpha: 0.25),
      side: const BorderSide(color: Ember.outline),
      labelStyle: GoogleFonts.ibmPlexSans(color: Ember.text),
    ),
  );
}

/// Monospaced numbers (IBM Plex Mono).
TextStyle monoStyle({double size = 13, Color color = Ember.textMuted}) =>
    GoogleFonts.ibmPlexMono(fontSize: size, color: color);
