import 'package:flutter/widgets.dart';

/// The Vendor360 colour palette.
///
/// Structure is inherited from the CarryO design system; the hues are
/// Vendor360's own, from the UI/UX Design Guide: a primary teal `#0F7A6B`
/// with saffron `#D98A0F` as the attention accent, on a warm off-white canvas
/// rather than pure white. The guide's stated intent is "warm, not corporate",
/// deliberately unlike generic blue enterprise software.
///
/// This is the only file in the codebase permitted to contain colour literals.
/// Everything else reads tokens through `context.v360.colors`, which is why
/// re-skinning the entire product was a change to one file.
///
/// Two contrast decisions are load-bearing, and both were derived rather than
/// eyeballed:
///
/// 1. [accentText] differs from [accent] in light mode. Brand teal `#0F7A6B`
///    sits at 0.151 relative luminance, giving 4.97:1 on the warm canvas —
///    just past the 4.5:1 WCAG AA floor for body text, so it is usable but has
///    no margin. [accentText] drops to `#0A5A4F` for 7.71:1, which holds up at
///    small sizes and in sunlight. Saffron `#D98A0F` manages only 2.63:1 and
///    fails AA outright, which is why [voice] and [warning] are fill-and-icon
///    colours and never text; [voiceText] and [warningText] carry the readable
///    deep amber instead.
///
/// 2. [actionFill] inverts between modes — near-black in light, teal in dark.
///    Dark mode fills the primary button with a bright colour and sets *dark*
///    text on it, which only works if the accent is light enough. `#2FB39D`
///    (0.353 luminance) carries 6.50:1 against [onActionFill]; the brand
///    `#0F7A6B` at 0.151 would have forced white text and changed the design,
///    so dark mode lightens the teal rather than reusing it.
@immutable
class V360Colors {
  const V360Colors({
    required this.canvas,
    required this.surface,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.inkSubtle,
    required this.hairline,
    required this.accent,
    required this.accentText,
    required this.accentSurface,
    required this.accentSurfaceStrong,
    required this.actionFill,
    required this.onActionFill,
    required this.onFill,
    required this.voice,
    required this.voiceText,
    required this.voiceSurface,
    required this.warning,
    required this.warningText,
    required this.warningSurface,
    required this.danger,
    required this.dangerText,
    required this.dangerSurface,
  });

  /// Page background. Warm off-white — the guide's rationale is legibility in
  /// bright sunlight at a market stall, where pure white glares.
  final Color canvas;

  /// Card background.
  final Color surface;

  /// Inset elements — chips, OTP boxes, quantity steppers.
  final Color surfaceMuted;

  /// Primary text.
  final Color ink;

  /// Secondary text — timestamps, captions, meta.
  final Color inkMuted;

  /// Section labels and disabled text.
  final Color inkSubtle;

  /// Dividers and unselected borders.
  final Color hairline;

  /// Accent fills, icons, indicators, progress. The brand teal.
  final Color accent;

  /// Teal used for *text*.
  ///
  /// Differs from [accent] in light mode, where the brand teal has only 4.97:1
  /// on the canvas — past the AA floor but with no margin at small sizes. In
  /// dark mode the lifted teal is already readable and the two are equal.
  final Color accentText;

  /// Pale accent banner fill.
  final Color accentSurface;

  /// Raised accent surface.
  final Color accentSurfaceStrong;

  /// Saffron, reserved for the voice affordance.
  ///
  /// The UI/UX guide makes the microphone the most prominent action on every
  /// data-entry screen. Giving it its own token — rather than reusing
  /// [warning] — means a designer cannot accidentally dilute the one control
  /// the product is built around by using the same colour for a stock alert.
  final Color voice;
  final Color voiceText;
  final Color voiceSurface;

  /// Attention states — low stock, approaching expiry, pending sync.
  final Color warning;
  final Color warningText;
  final Color warningSurface;

  /// Destructive actions, expired stock, sync errors.
  final Color danger;
  final Color dangerText;
  final Color dangerSurface;

  /// Primary button background. **Near-black in light, teal in dark.**
  ///
  /// This inversion is the most load-bearing rule in the design system.
  final Color actionFill;

  /// Primary button label. Inverts with [actionFill].
  final Color onActionFill;

  /// Content sitting on a saturated brand or status fill — a count on a
  /// [danger] badge, a label on an [accent] chip, the dashboard hero over its
  /// gradient.
  ///
  /// White in both themes, because those fills are saturated in both and
  /// white is what stays legible on them. It is a token rather than a literal
  /// so the *role* is stated: these were thirteen scattered `Colors.white`
  /// calls, and the design system permits colour literals in this file only.
  /// Distinct from [onActionFill], which inverts with the button fill and is
  /// near-black in dark mode.
  final Color onFill;

  factory V360Colors.light() => const V360Colors(
        // Warmed neutrals, so the off-white canvas reads as intentional rather
        // than as a grey that failed to be white.
        canvas: Color(0xFFFAF9F6),
        surface: Color(0xFFFFFFFF),
        surfaceMuted: Color(0xFFF2F1EC),
        ink: Color(0xFF1A2E2A),
        inkMuted: Color(0xFF5B6B67),
        inkSubtle: Color(0xFF8A9793),
        hairline: Color(0xFFD8E4E1),
        accent: Color(0xFF0F7A6B),
        accentText: Color(0xFF0A5A4F),
        accentSurface: Color(0xFFE4F2EF),
        accentSurfaceStrong: Color(0xFFCCE6E0),
        voice: Color(0xFFD98A0F),
        voiceText: Color(0xFF8A5600),
        voiceSurface: Color(0xFFFDF1DC),
        actionFill: Color(0xFF1A2E2A),
        onActionFill: Color(0xFFFFFFFF),
        onFill: Color(0xFFFFFFFF),
        warning: Color(0xFFD98A0F),
        warningText: Color(0xFF8A5600),
        warningSurface: Color(0xFFFAEFD9),
        danger: Color(0xFFE85D4C),
        dangerText: Color(0xFFB03B2C),
        dangerSurface: Color(0xFFFCEBE8),
      );

  factory V360Colors.dark() => const V360Colors(
        // Cool near-black with a faint green cast, so the teal accent sits on
        // it without looking pasted on.
        canvas: Color(0xFF0B1210),
        surface: Color(0xFF151E1B),
        surfaceMuted: Color(0xFF111A17),
        ink: Color(0xFFEDF3F1),
        inkMuted: Color(0xFF8A9C97),
        inkSubtle: Color(0xFF6B7C78),
        hairline: Color(0xFF223029),
        accent: Color(0xFF2FB39D),
        // Identical to [accent] here, unlike light mode. The lifted teal
        // carries 6.53:1 on `surface` and 5.61:1 on `accentSurface`, so it is
        // already readable as text and a second value would be a token that
        // has to be kept in sync for no benefit.
        accentText: Color(0xFF2FB39D),
        accentSurface: Color(0xFF0C2E28),
        accentSurfaceStrong: Color(0xFF124039),
        voice: Color(0xFFE9A22E),
        voiceText: Color(0xFFF5C069),
        voiceSurface: Color(0xFF2E2210),
        actionFill: Color(0xFF2FB39D),
        onActionFill: Color(0xFF04211C),
        onFill: Color(0xFFFFFFFF),
        warning: Color(0xFFE9A22E),
        warningText: Color(0xFFF5C069),
        warningSurface: Color(0xFF2E2410),
        danger: Color(0xFFFF6B59),
        dangerText: Color(0xFFFF9484),
        dangerSurface: Color(0xFF2E1512),
      );

  V360Colors lerp(V360Colors other, double t) => V360Colors(
        canvas: Color.lerp(canvas, other.canvas, t)!,
        surface: Color.lerp(surface, other.surface, t)!,
        surfaceMuted: Color.lerp(surfaceMuted, other.surfaceMuted, t)!,
        ink: Color.lerp(ink, other.ink, t)!,
        inkMuted: Color.lerp(inkMuted, other.inkMuted, t)!,
        inkSubtle: Color.lerp(inkSubtle, other.inkSubtle, t)!,
        hairline: Color.lerp(hairline, other.hairline, t)!,
        accent: Color.lerp(accent, other.accent, t)!,
        accentText: Color.lerp(accentText, other.accentText, t)!,
        accentSurface: Color.lerp(accentSurface, other.accentSurface, t)!,
        accentSurfaceStrong:
            Color.lerp(accentSurfaceStrong, other.accentSurfaceStrong, t)!,
        voice: Color.lerp(voice, other.voice, t)!,
        voiceText: Color.lerp(voiceText, other.voiceText, t)!,
        voiceSurface: Color.lerp(voiceSurface, other.voiceSurface, t)!,
        actionFill: Color.lerp(actionFill, other.actionFill, t)!,
        onActionFill: Color.lerp(onActionFill, other.onActionFill, t)!,
        onFill: Color.lerp(onFill, other.onFill, t)!,
        warning: Color.lerp(warning, other.warning, t)!,
        warningText: Color.lerp(warningText, other.warningText, t)!,
        warningSurface: Color.lerp(warningSurface, other.warningSurface, t)!,
        danger: Color.lerp(danger, other.danger, t)!,
        dangerText: Color.lerp(dangerText, other.dangerText, t)!,
        dangerSurface: Color.lerp(dangerSurface, other.dangerSurface, t)!,
      );
}
