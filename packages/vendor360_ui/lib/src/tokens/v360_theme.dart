import 'package:flutter/material.dart';

import '../motion/motion_scope.dart';
import 'v360_colors.dart';
import 'v360_motion.dart';
import 'v360_spacing.dart';
import 'v360_typography.dart';

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
/// Material's own colour scheme is populated so stock widgets do not look
/// foreign, but Vendor360 components should always read `context.v360`.
ThemeData buildV360Theme(Brightness brightness) {
  final colors =
      brightness == Brightness.dark ? V360Colors.dark() : V360Colors.light();
  const type = V360Typography();

  final scheme = ColorScheme(
    brightness: brightness,
    primary: colors.accent,
    onPrimary: colors.onActionFill,
    secondary: colors.voice,
    onSecondary: colors.onActionFill,
    error: colors.danger,
    onError: const Color(0xFFFFFFFF),
    surface: colors.surface,
    onSurface: colors.ink,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: colors.canvas,
    // Package-qualified. `ThemeData` has no `package` argument, so a bare
    // 'Inter' here names a global family that was never registered — and the
    // old fallback repeated the family, which could never supply a glyph the
    // family itself was missing. Devanagari behind it is what stops dialogs,
    // snackbars and field hints rendering Hindi as boxes.
    fontFamily: V360Typography.qualifiedFamily,
    fontFamilyFallback: const <String>[V360Typography.qualifiedDevanagari],
    textTheme: TextTheme(
      displayLarge: type.display,
      titleLarge: type.titleL,
      titleMedium: type.titleM,
      titleSmall: type.titleS,
      bodyLarge: type.body,
      bodyMedium: type.body,
      bodySmall: type.caption,
      labelSmall: type.label,
    ).apply(bodyColor: colors.ink, displayColor: colors.ink),
    dividerColor: colors.hairline,
    extensions: <ThemeExtension<dynamic>>[
      V360ThemeData(colors: colors, brightness: brightness),
    ],
  );
}

/// Token access for widgets.
///
/// `context.v360.colors.accent` is the only sanctioned way to read a colour.
/// Colour literals outside `carry_colors.dart` are a review failure.
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
