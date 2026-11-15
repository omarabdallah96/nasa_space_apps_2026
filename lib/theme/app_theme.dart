import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../data/models/danger_forecast.dart';
import '../domain/anomaly.dart';

/// Firesight palette: charcoal (dark) or warm paper (light) neutrals,
/// ember accents in both.
abstract final class Ember {
  /// Which neutrals are active. Set from [AppState.darkMode] by the app root.
  static bool isDark = true;

  /// Brand charcoal, fixed in both modes (logo tile, native splash).
  static const night = Color(0xFF14100E);

  static Color get background => isDark ? night : const Color(0xFFFAF5EE);
  static Color get surface =>
      isDark ? const Color(0xFF1F1916) : const Color(0xFFFFFDF9);
  static Color get surfaceHigh =>
      isDark ? const Color(0xFF2A221E) : const Color(0xFFF1E8DD);
  static Color get outline =>
      isDark ? const Color(0xFF3D322C) : const Color(0xFFE3D6C7);
  static Color get text =>
      isDark ? const Color(0xFFF3E9DC) : const Color(0xFF241A15);
  static Color get textMuted =>
      isDark ? const Color(0xFFA8998A) : const Color(0xFF6E6055);

  static const ember = Color(0xFFFF6B2C);
  static const amber = Color(0xFFFFB547);
  static const ash = Color(0xFF6E625A);
  static const calm = Color(0xFF7FB7A4);
  static const extreme = Color(0xFFE5383B);

  /// Sequential scale for fire intensity, 0 → none, 1 → maximum.
  static Color heat(double t) {
    t = t.clamp(0.0, 1.0);
    final stops = [
      isDark ? const Color(0xFF241C18) : const Color(0xFFEFE4D6),
      const Color(0xFF5A2A17),
      const Color(0xFFA63F1B),
      const Color(0xFFFF6B2C),
      const Color(0xFFFFB547),
      const Color(0xFFFFE8A8),
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

  /// Fire danger classes, green to deep red in EFFIS order.
  static Color forDanger(DangerLevel l) => switch (l) {
        DangerLevel.veryLow => calm,
        DangerLevel.low => const Color(0xFFB8C46A),
        DangerLevel.moderate => amber,
        DangerLevel.high => ember,
        DangerLevel.veryHigh => extreme,
        DangerLevel.extreme => const Color(0xFFB0246E),
      };

  static String labelForStatus(FireStatus s) => switch (s) {
        FireStatus.below => 'Below normal',
        FireStatus.normal => 'Normal',
        FireStatus.above => 'Above normal',
        FireStatus.extreme => 'Extreme',
      };
}

/// Arabic pairing: IBM Plex Sans Arabic (body, same family as the Latin
/// Plex) and Amiri, a classical Naskh serif, for headings next to Fraunces.
/// Uses whichever neutrals [Ember.isDark] selects.
ThemeData buildEmberTheme({bool arabic = false}) {
  final scheme = Ember.isDark
      ? ColorScheme.dark(
          primary: Ember.ember,
          secondary: Ember.amber,
          surface: Ember.surface,
          onSurface: Ember.text,
          outline: Ember.outline,
        )
      : ColorScheme.light(
          primary: Ember.ember,
          secondary: Ember.amber,
          surface: Ember.surface,
          onSurface: Ember.text,
          outline: Ember.outline,
        );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Ember.isDark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: Ember.background,
  );

  final body = (arabic
          ? GoogleFonts.ibmPlexSansArabicTextTheme(base.textTheme)
          : GoogleFonts.ibmPlexSansTextTheme(base.textTheme))
      .apply(bodyColor: Ember.text, displayColor: Ember.text);
  final display = (arabic
          ? GoogleFonts.amiriTextTheme(base.textTheme)
          : GoogleFonts.frauncesTextTheme(base.textTheme))
      .apply(bodyColor: Ember.text, displayColor: Ember.text);
  TextStyle sans({double? fontSize, Color? color}) => arabic
      ? GoogleFonts.ibmPlexSansArabic(fontSize: fontSize, color: color)
      : GoogleFonts.ibmPlexSans(fontSize: fontSize, color: color);

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
      systemOverlayStyle: Ember.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      titleTextStyle: arabic
          ? GoogleFonts.amiri(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Ember.text,
            )
          : GoogleFonts.fraunces(
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
        side: BorderSide(color: Ember.outline),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Ember.surface,
      indicatorColor: Ember.ember.withValues(alpha: 0.22),
      labelTextStyle: WidgetStatePropertyAll(
        sans(fontSize: 12, color: Ember.text),
      ),
    ),
    // Comfortable touch targets and one consistent button shape.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: sans(fontSize: 15).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 44),
        foregroundColor: Ember.text,
        side: BorderSide(color: Ember.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: sans(fontSize: 14).copyWith(fontWeight: FontWeight.w600),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Ember.surfaceHigh,
      contentTextStyle: sans(fontSize: 14, color: Ember.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Ember.surface,
      dragHandleColor: Ember.outline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      backgroundColor: Ember.surface,
      selectedColor: Ember.ember.withValues(alpha: 0.25),
      side: BorderSide(color: Ember.outline),
      labelStyle: sans(color: Ember.text),
    ),
  );
}

/// Monospaced numbers (IBM Plex Mono). Arabic words in a mono label fall
/// back to IBM Plex Sans Arabic instead of the system font.
TextStyle monoStyle({double size = 13, Color? color}) =>
    GoogleFonts.ibmPlexMono(fontSize: size, color: color ?? Ember.textMuted).copyWith(
      fontFamilyFallback: [GoogleFonts.ibmPlexSansArabic().fontFamily!],
    );
