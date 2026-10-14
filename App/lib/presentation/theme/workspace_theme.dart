import 'package:flutter/material.dart';

/// Presentation tokens shared by every settings surface.
abstract final class WorkspaceTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? const Color(0xff1c1d20) : const Color(0xfff5f5f7);
    final surface = dark ? const Color(0xff26272b) : Colors.white;
    final ink = dark ? const Color(0xfff4f5f7) : const Color(0xff202124);
    final secondary = dark ? const Color(0xffa5a9b2) : const Color(0xff6c7078);
    final border = dark ? const Color(0xff3b3d43) : const Color(0xffe3e5ea);
    final blue = dark ? const Color(0xff75a7ff) : const Color(0xff246bfd);
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
        .copyWith(
          primary: blue,
          onPrimary: dark ? const Color(0xff10284e) : Colors.white,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: secondary,
          outlineVariant: border,
          secondaryContainer: dark
              ? const Color(0xff293b59)
              : const Color(0xffe6eeff),
          onSecondaryContainer: dark
              ? const Color(0xffc1d7ff)
              : const Color(0xff2359bd),
        );
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: '.AppleSystemUIFont',
      scaffoldBackgroundColor: canvas,
    );
    return base.copyWith(
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 24,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.6,
              color: ink,
            ),
            titleLarge: TextStyle(
              fontSize: 16,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            titleMedium: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            bodyLarge: TextStyle(fontSize: 13, height: 1.5, color: ink),
            bodyMedium: TextStyle(fontSize: 13, height: 1.45, color: ink),
            bodySmall: TextStyle(fontSize: 12, height: 1.4, color: secondary),
            labelLarge: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          )
          .apply(fontFamily: '.AppleSystemUIFont'),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        minTileHeight: 46,
        horizontalTitleGap: 12,
        minLeadingWidth: 20,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (s) =>
              !s.contains(WidgetState.disabled) &&
                  s.contains(WidgetState.selected)
              ? Colors.white
              : null,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) =>
              !s.contains(WidgetState.disabled) &&
                  s.contains(WidgetState.selected)
              ? blue
              : null,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Colors.transparent : border,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: border),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          side: BorderSide(color: border),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}
