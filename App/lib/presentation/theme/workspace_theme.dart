import 'package:flutter/material.dart';

/// Surface tokens that have no Material slot: sidebar, hairlines and selection.
@immutable
class MacTokens extends ThemeExtension<MacTokens> {
  const MacTokens({
    required this.sidebar,
    required this.hairline,
    required this.selection,
    required this.onSelection,
    required this.offTrack,
    required this.secondary,
  });
  final Color sidebar, hairline, selection, onSelection, offTrack, secondary;

  static MacTokens of(BuildContext context) =>
      Theme.of(context).extension<MacTokens>()!;

  @override
  MacTokens copyWith({
    Color? sidebar,
    Color? hairline,
    Color? selection,
    Color? onSelection,
    Color? offTrack,
    Color? secondary,
  }) => MacTokens(
    sidebar: sidebar ?? this.sidebar,
    hairline: hairline ?? this.hairline,
    selection: selection ?? this.selection,
    onSelection: onSelection ?? this.onSelection,
    offTrack: offTrack ?? this.offTrack,
    secondary: secondary ?? this.secondary,
  );

  @override
  MacTokens lerp(MacTokens? other, double t) {
    if (other == null) return this;
    return MacTokens(
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      onSelection: Color.lerp(onSelection, other.onSelection, t)!,
      offTrack: Color.lerp(offTrack, other.offTrack, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
    );
  }
}

/// Presentation tokens shared by every settings surface, modelled on the
/// grouped layout of macOS System Settings in both appearances.
abstract final class WorkspaceTheme {
  static ThemeData build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final canvas = dark ? const Color(0xff1e1e21) : const Color(0xfff5f5f7);
    final sidebar = dark ? const Color(0xff252528) : const Color(0xffebebef);
    final surface = dark ? const Color(0xff2c2c2f) : Colors.white;
    final ink = dark ? const Color(0xfff2f2f5) : const Color(0xff1d1d1f);
    final secondary = dark ? const Color(0xff9a9aa0) : const Color(0xff6e6e73);
    final hairline = dark ? const Color(0xff3a3a3e) : const Color(0xffe3e3e8);
    final accent = dark ? const Color(0xff3d8bff) : const Color(0xff0a5fd6);
    final selection = dark ? const Color(0xff2468d8) : const Color(0xff0a5fd6);
    final offTrack = dark ? const Color(0xff48484c) : const Color(0xffd9d9de);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: brightness,
        ).copyWith(
          primary: accent,
          onPrimary: Colors.white,
          surface: surface,
          onSurface: ink,
          onSurfaceVariant: secondary,
          outline: hairline,
          outlineVariant: hairline,
          secondaryContainer: dark
              ? const Color(0xff1f3557)
              : const Color(0xffe4eeff),
          onSecondaryContainer: dark
              ? const Color(0xffc6dbff)
              : const Color(0xff0b4aa8),
        );
    final base = ThemeData(
      brightness: brightness,
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: '.AppleSystemUIFont',
      scaffoldBackgroundColor: canvas,
      splashFactory: NoSplash.splashFactory,
      visualDensity: VisualDensity.compact,
    );
    return base.copyWith(
      extensions: [
        MacTokens(
          sidebar: sidebar,
          hairline: hairline,
          selection: selection,
          onSelection: Colors.white,
          offTrack: offTrack,
          secondary: secondary,
        ),
      ],
      textTheme: base.textTheme
          .copyWith(
            headlineLarge: TextStyle(
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w700,
              letterSpacing: -.3,
              color: ink,
            ),
            titleLarge: TextStyle(
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
            titleMedium: TextStyle(
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
              color: secondary,
            ),
            bodyLarge: TextStyle(
              fontSize: 13,
              height: 1.45,
              letterSpacing: -.08,
              color: ink,
            ),
            bodyMedium: TextStyle(
              fontSize: 13,
              height: 1.45,
              letterSpacing: -.08,
              color: ink,
            ),
            bodySmall: TextStyle(
              fontSize: 12,
              height: 1.4,
              letterSpacing: 0,
              color: secondary,
            ),
            labelLarge: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          )
          .apply(fontFamily: '.AppleSystemUIFont'),
      dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
      cardTheme: CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: hairline),
        ),
      ),
      listTileTheme: ListTileThemeData(
        minTileHeight: 44,
        horizontalTitleGap: 12,
        minLeadingWidth: 20,
        titleTextStyle: TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontSize: 13,
          height: 1.4,
          color: ink,
        ),
        subtitleTextStyle: TextStyle(
          fontFamily: '.AppleSystemUIFont',
          fontSize: 12,
          height: 1.35,
          color: secondary,
        ),
      ),
      switchTheme: SwitchThemeData(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        thumbIcon: const WidgetStatePropertyAll(null),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled)
              ? (dark ? const Color(0xff8e8e93) : const Color(0xfff2f2f4))
              : Colors.white,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected)
              ? (s.contains(WidgetState.disabled)
                    ? accent.withValues(alpha: .4)
                    : accent)
              : offTrack,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 10,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(7),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          backgroundColor: surface,
          side: BorderSide(color: hairline),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          minimumSize: const Size(0, 30),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: selection,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          minimumSize: const Size(0, 30),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          side: WidgetStatePropertyAll(BorderSide(color: hairline)),
          backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? selection : surface,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? Colors.white : ink,
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        textStyle: TextStyle(fontSize: 13, color: ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: accent),
      tooltipTheme: const TooltipThemeData(
        waitDuration: Duration(milliseconds: 500),
      ),
    );
  }
}
