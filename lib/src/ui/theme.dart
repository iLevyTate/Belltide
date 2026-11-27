import 'package:material_ui/material_ui.dart';

/// Deep sea teal: calm, readable in both light and dark mode.
const Color belltideSeed = Color(0xFF1F6F78);

ThemeData belltideTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: belltideSeed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    listTileTheme: const ListTileThemeData(contentPadding: EdgeInsets.symmetric(horizontal: 16)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder()),
  );
}

/// Digits that keep their width, so countdowns don't jitter.
const List<FontFeature> tabularFigures = [FontFeature.tabularFigures()];
