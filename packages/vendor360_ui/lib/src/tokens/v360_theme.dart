import 'package:flutter/material.dart';

import '../motion/motion_scope.dart';
import 'v360_colors.dart';
import 'v360_motion.dart';
import 'v360_spacing.dart';
import 'v360_typography.dart';

// Every widget that reads `context.v360` also adjusts styles, so the
// axis-aware helpers travel with the theme import.
export 'v360_typography.dart' show V360TextStyleX, v360Strut;

/// All Vendor360 design tokens, carried on [ThemeData.extensions].
///
/// Note: the typography field is called `text`, not `type`. [ThemeExtension]
/// uses a getter named `type` as the key under which it files itself in
/// `ThemeData.extensions`; a field of that name shadows it and every
/// `extension<V360ThemeData>()` lookup silently returns null.
@immutable
class V360ThemeData extends ThemeExtension<V360ThemeData> {
  const V360ThemeData({
    required this.colors,
    required this.brightness,
    this.text = const V360Typography(),
    this.spacing = const V360Spacing(),
    this.motion = const V360Motion(),
  });

  final V360Colors colors;
  final Brightness brightness;
  final V360Typography text;
  final V360Spacing spacing;
  final V360Motion motion;

  bool get isDark => brightness == Brightness.dark;

  @override
  V360ThemeData copyWith({
    V360Colors? colors,
    Brightness? brightness,
    V360Typography? text,
    V360Spacing? spacing,
    V360Motion? motion,
  }) =>
      V360ThemeData(
        colors: colors ?? this.colors,
        brightness: brightness ?? this.brightness,
        text: text ?? this.text,
        spacing: spacing ?? this.spacing,
        motion: motion ?? this.motion,
      );

  @override
  V360ThemeData lerp(ThemeExtension<V360ThemeData>? other, double t) {
    if (other is! V360ThemeData) return this;
    return V360ThemeData(
      colors: colors.lerp(other.colors, t),
      brightness: t < 0.5 ? brightness : other.brightness,
      text: text,
      spacing: spacing,
      motion: motion,
    );
  }
}

/// Builds the Vendor360 [ThemeData] for a brightness.
///
/// Material's colour roles and component themes are all populated, so the
/// stock widgets a screen reaches for — an AppBar, a snackbar, a dialog, a
/// text field — print in the same four inks as the custom ones instead of
/// arriving in Material's default purple-grey. Vendor360 components should
/// still read `context.v360`.
///
/// Pass [distributor] to print the distributor shell's deeper band.
ThemeData buildV360Theme(Brightness brightness, {bool distributor = false}) {
  final base =
      brightness == Brightness.dark ? V360Colors.dark() : V360Colors.light();
  final colors = distributor ? base.distributorVariant() : base;
  const type = V360Typography();

  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onActionFill,
    primaryContainer: colors.accentSurface,
    onPrimaryContainer: colors.accentText,
    secondary: colors.voice,
    onSecondary: colors.onVoice,
    secondaryContainer: colors.voiceSurface,
    onSecondaryContainer: colors.voiceText,
    tertiary: colors.warning,
    onTertiary: colors.onVoice,
    tertiaryContainer: colors.warningSurface,
    onTertiaryContainer: colors.warningText,
    error: colors.danger,
    onError: colors.onFill,
    errorContainer: colors.dangerSurface,
    onErrorContainer: colors.dangerText,
    surface: colors.surface,
    onSurface: colors.ink,
    onSurfaceVariant: colors.inkMuted,
    surfaceContainerLowest: colors.canvas,
    surfaceContainerLow: colors.surface,
    surfaceContainer: colors.surfaceMuted,
    surfaceContainerHigh: colors.surfaceMuted,
    surfaceContainerHighest: colors.surfaceMuted,
    outline: colors.inkSubtle,
    outlineVariant: colors.hairline,
    inverseSurface: colors.ink,
    onInverseSurface: colors.canvas,
    inversePrimary: colors.accentSurfaceStrong,
    // Print has no tonal tint: a raised Material surface stays the colour
    // it was printed in.
    surfaceTint: const Color(0x00000000),
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(V360Radius.md),
  );
  const controlSize = Size(64, 48);

  OutlineInputBorder field(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(V360Radius.md),
        borderSide: BorderSide(color: color, width: width),
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.canvas,
    // Package-qualified. `ThemeData` has no `package` argument, so a bare
    // family name here would name a global family that was never registered.
    // Devanagari behind it is what stops dialogs, snackbars and field hints
    // rendering Hindi as boxes.
    fontFamily: V360Typography.qualifiedFamily,
    fontFamilyFallback: const <String>[V360Typography.qualifiedDevanagari],
    textTheme: TextTheme(
      displayLarge: type.display,
      displayMedium: type.figure,
      headlineSmall: type.titleL,
      titleLarge: type.titleM,
      titleMedium: type.titleS,
      titleSmall: type.bodyStrong,
      bodyLarge: type.body,
      bodyMedium: type.body,
      bodySmall: type.caption,
      labelLarge: type.bodyStrong,
      labelMedium: type.label,
      labelSmall: type.label,
    ).apply(bodyColor: colors.ink, displayColor: colors.ink),
    dividerColor: colors.hairline,
    dividerTheme: DividerThemeData(
      color: colors.hairline,
      thickness: 1,
      space: 1,
    ),

    // Every secondary screen opens on the band: the front of the pack.
    appBarTheme: AppBarTheme(
      backgroundColor: colors.band,
      foregroundColor: colors.onBand,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: 4,
      titleTextStyle: type.titleL.copyWith(color: colors.onBand, fontSize: 22),
      iconTheme: IconThemeData(color: colors.onBand),
      actionsIconTheme: IconThemeData(color: colors.onBand),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: colors.actionFill,
        foregroundColor: colors.onActionFill,
        minimumSize: controlSize,
        shape: controlShape,
        textStyle: type.bodyStrong,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: colors.actionFill,
        foregroundColor: colors.onActionFill,
        elevation: 0,
        minimumSize: controlSize,
        shape: controlShape,
        textStyle: type.bodyStrong,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        side: BorderSide(color: colors.keyline, width: 1.5),
        minimumSize: controlSize,
        shape: controlShape,
        textStyle: type.bodyStrong,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.accentText,
        minimumSize: const Size(48, 48),
        shape: controlShape,
        textStyle: type.bodyStrong,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: colors.voice,
      foregroundColor: colors.onVoice,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: const CircleBorder(),
    ),

    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: type.body.copyWith(color: colors.inkSubtle),
      labelStyle: type.body.copyWith(color: colors.inkMuted),
      floatingLabelStyle: type.label.copyWith(color: colors.accentText),
      prefixIconColor: colors.inkMuted,
      suffixIconColor: colors.inkMuted,
      // A field's edge is a control boundary, so it needs 3:1 against the
      // page (WCAG 1.4.11); the hairline alone would not clear it.
      border: field(colors.inkSubtle),
      enabledBorder: field(colors.inkSubtle),
      focusedBorder: field(colors.accent, 2),
      errorBorder: field(colors.danger),
      focusedErrorBorder: field(colors.danger, 2),
      disabledBorder: field(colors.hairline),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: colors.accent,
      selectionColor: colors.accentSurfaceStrong,
      selectionHandleColor: colors.accent,
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: colors.ink,
      contentTextStyle: type.body.copyWith(color: colors.canvas),
      actionTextColor: colors.voice,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.md),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.xl),
      ),
      titleTextStyle: type.titleM.copyWith(color: colors.ink),
      contentTextStyle: type.body.copyWith(color: colors.inkMuted),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.surface,
      modalBackgroundColor: colors.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 0,
      modalElevation: 0,
      // Off: the app's sheets draw their own handle inside their own
      // surface, and a themed one would print a second handle above it.
      dragHandleColor: colors.hairline,
      dragHandleSize: const Size(36, 4),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(V360Radius.xl),
        ),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surface,
      surfaceTintColor: const Color(0x00000000),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.lg),
        side: BorderSide(color: colors.hairline),
      ),
      textStyle: type.body.copyWith(color: colors.ink),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: colors.ink,
        borderRadius: BorderRadius.circular(V360Radius.sm),
      ),
      textStyle: type.caption.copyWith(color: colors.canvas),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: colors.surface,
      selectedColor: colors.accentSurface,
      disabledColor: colors.surfaceMuted,
      side: BorderSide(color: colors.hairline),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.sm),
      ),
      labelStyle:
          type.caption.copyWith(color: colors.ink).weight(FontWeight.w600),
      secondaryLabelStyle: type.caption.copyWith(color: colors.accentText),
      checkmarkColor: colors.accentText,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: colors.inkMuted,
      titleTextStyle: type.titleS.copyWith(color: colors.ink),
      subtitleTextStyle: type.caption.copyWith(color: colors.inkMuted),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: colors.accent,
      linearTrackColor: colors.surfaceMuted,
      circularTrackColor: colors.surfaceMuted,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.onActionFill
            : colors.inkSubtle,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.surfaceMuted,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : const Color(0x00000000),
      ),
      checkColor: WidgetStatePropertyAll<Color>(colors.onActionFill),
      side: BorderSide(color: colors.inkSubtle, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.sm),
      ),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? colors.accent
            : colors.inkSubtle,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll<Color>(
        colors.inkSubtle.withValues(alpha: 0.5),
      ),
      radius: const Radius.circular(V360Radius.sm),
      thickness: const WidgetStatePropertyAll<double>(4),
    ),
    extensions: <ThemeExtension<dynamic>>[
      V360ThemeData(colors: colors, brightness: brightness),
    ],
  );
}

/// Token access for widgets.
///
/// `context.v360.colors.accent` is the only sanctioned way to read a colour.
/// Colour literals outside `v360_colors.dart` are a review failure.
///
/// The assert fires loudly in debug if the theme was not built with
/// [buildV360Theme]; the fallback keeps release builds rendering rather than
/// crashing on stage.
extension V360ThemeContext on BuildContext {
  V360ThemeData get v360 {
    final ext = Theme.of(this).extension<V360ThemeData>();
    assert(
      ext != null,
      'V360ThemeData missing. Build your ThemeData with buildV360Theme().',
    );
    final brightness = Theme.of(this).brightness;
    return ext ??
        V360ThemeData(
          colors: brightness == Brightness.dark
              ? V360Colors.dark()
              : V360Colors.light(),
          brightness: brightness,
        );
  }

  /// Motion durations resolved against the reduce-motion setting.
  ResolvedMotion get motion => MotionScope.of(this);
}
