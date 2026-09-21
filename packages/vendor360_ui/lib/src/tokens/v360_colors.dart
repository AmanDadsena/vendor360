import 'package:flutter/widgets.dart';

/// The Vendor360 colour palette — printed, not glowing.
///
/// The palette is taken from the packets on a kirana shelf, which are printed
/// in a few flat inks on white board: a brand colour that owns the front of
/// the pack, a dark ink for the small print, and one or two spot colours for
/// the thing that must be seen. Nothing on a printed pack has a gradient, a
/// glow or a drop shadow, and nothing here does either.
///
/// Four inks on white:
///
/// * **Teal** — the brand. Owns one flat [band] per screen and the primary
///   action. Teal is also the one colour that marks something *live*.
/// * **Ink** — a green-black for text and keylines.
/// * **Marigold** — attention: the microphone, low stock, a festival heads-up.
/// * **MRP red** — out of stock, expired, overdue.
///
/// This is the only file in the codebase permitted to contain colour literals.
/// Everything else reads tokens through `context.v360.colors`.
///
/// Contrast is asserted by test, not eyeballed: every text token clears
/// WCAG AA 4.5:1 on the surfaces it is used on, and [onBandMuted] is tinted
/// from the teal rather than greyed, so secondary text on the band still
/// reads in sunlight.
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
    required this.keyline,
    required this.accent,
    required this.accentText,
    required this.accentSurface,
    required this.accentSurfaceStrong,
    required this.band,
    required this.onBand,
    required this.onBandMuted,
    required this.actionFill,
    required this.onActionFill,
    required this.onFill,
    required this.voice,
    required this.onVoice,
    required this.voiceText,
    required this.voiceSurface,
    required this.warning,
    required this.warningText,
    required this.warningSurface,
    required this.danger,
    required this.dangerText,
    required this.dangerSurface,
  });

  /// Page background. White board, like the back of a pack.
  final Color canvas;

  /// Panel background. Also white: panels are separated by rules, not by
  /// being lifted off the page.
  final Color surface;

  /// The second neutral layer — inset fields, steppers, the declaration
  /// strip, skeletons. A cool board grey, never cream.
  final Color surfaceMuted;

  /// Primary text.
  final Color ink;

  /// Secondary text — timestamps, captions, meta.
  final Color inkMuted;

  /// The quietest readable text — placeholders, disabled labels.
  final Color inkSubtle;

  /// Light rule between rows.
  final Color hairline;

  /// Strong rule — outlined buttons, a focused field, a panel that must hold
  /// its edge.
  final Color keyline;

  /// Brand teal for fills, icons, indicators and live state.
  final Color accent;

  /// Teal for *text* on white; deeper than [accent] so it holds at 13px.
  final Color accentText;

  /// Pale teal for a selected row or a pressed surface. Never on the band.
  final Color accentSurface;

  /// Stronger pale teal, for a selected control inside a selected row.
  final Color accentSurfaceStrong;

  /// The flat colour field at the top of a screen — the front of the pack.
  ///
  /// One per screen. The distributor shell prints on a darker variant of the
  /// same teal (see [distributorVariant]), the way one product line uses a
  /// second colour for a second pack.
  final Color band;

  /// Text and icons on the [band].
  final Color onBand;

  /// Secondary text on the [band], tinted from the teal rather than greyed.
  final Color onBandMuted;

  /// Primary button background. Teal in both themes.
  final Color actionFill;

  /// Primary button label.
  final Color onActionFill;

  /// Content on any saturated brand or status fill — a count on a [danger]
  /// badge, a label on a teal chip. White in both themes.
  final Color onFill;

  /// Marigold, reserved for the voice affordance.
  ///
  /// The microphone is the product's most frequent action and its most
  /// prominent control. It has its own token — rather than reusing
  /// [warning] — so a designer cannot dilute it by reaching for "the orange"
  /// for a stock alert.
  final Color voice;

  /// Icon on a [voice] fill. Ink, not white: white on marigold fails contrast.
  final Color onVoice;
  final Color voiceText;
  final Color voiceSurface;

  /// Attention — low stock, approaching expiry, pending sync. A marker and
  /// fill colour; [warningText] carries readable text.
  final Color warning;
  final Color warningText;
  final Color warningSurface;

  /// Out of stock, expired, overdue, destructive actions.
  final Color danger;
  final Color dangerText;
  final Color dangerSurface;

  factory V360Colors.light() => const V360Colors(
        canvas: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        surfaceMuted: Color(0xFFEEF3F1),
        ink: Color(0xFF10201C),
        inkMuted: Color(0xFF475853),
        inkSubtle: Color(0xFF63726D),
        hairline: Color(0xFFD5DEDA),
        keyline: Color(0xFF10201C),
        accent: Color(0xFF0B7768),
        accentText: Color(0xFF075A4F),
        accentSurface: Color(0xFFE1EFEB),
        accentSurfaceStrong: Color(0xFFC6E3DC),
        band: Color(0xFF0B7768),
        onBand: Color(0xFFFFFFFF),
        onBandMuted: Color(0xFFD9F0EA),
        actionFill: Color(0xFF0B7768),
        onActionFill: Color(0xFFFFFFFF),
        onFill: Color(0xFFFFFFFF),
        voice: Color(0xFFF2A20C),
        onVoice: Color(0xFF10201C),
        voiceText: Color(0xFF8A5300),
        voiceSurface: Color(0xFFFDF0D5),
        warning: Color(0xFFE39A00),
        warningText: Color(0xFF7F4C00),
        warningSurface: Color(0xFFFCF0D6),
        danger: Color(0xFFC62A1F),
        dangerText: Color(0xFFA3221A),
        dangerSurface: Color(0xFFFBE9E7),
      );

  factory V360Colors.dark() => const V360Colors(
        canvas: Color(0xFF0D1412),
        surface: Color(0xFF131C1A),
        surfaceMuted: Color(0xFF1A2522),
        ink: Color(0xFFE8EFEC),
        inkMuted: Color(0xFFA3B2AD),
        inkSubtle: Color(0xFF879792),
        hairline: Color(0xFF27342F),
        keyline: Color(0xFF9FB0AA),
        accent: Color(0xFF2DB39D),
        // Identical to [accent] here: the lifted teal already reads as text
        // on the dark surfaces, so a second value would be a token to keep
        // in sync for no benefit.
        accentText: Color(0xFF2DB39D),
        accentSurface: Color(0xFF11322C),
        accentSurfaceStrong: Color(0xFF17443B),
        band: Color(0xFF0B5F54),
        onBand: Color(0xFFFFFFFF),
        onBandMuted: Color(0xFFBFE3DB),
        actionFill: Color(0xFF2DB39D),
        onActionFill: Color(0xFF04211C),
        onFill: Color(0xFFFFFFFF),
        voice: Color(0xFFF4AE2A),
        onVoice: Color(0xFF10201C),
        voiceText: Color(0xFFF7C66A),
        voiceSurface: Color(0xFF33260E),
        warning: Color(0xFFF0A928),
        warningText: Color(0xFFF6C56A),
        warningSurface: Color(0xFF332710),
        danger: Color(0xFFE24A3B),
        dangerText: Color(0xFFFF8E7F),
        dangerSurface: Color(0xFF341713),
      );

  /// The distributor shell's variant: the same pack line printed on a deeper
  /// bottle-green teal, so a shop screen and a wholesaler screen can never be
  /// mistaken for each other across a room — or across a demo.
  V360Colors distributorVariant() {
    final dark = canvas.computeLuminance() < 0.2;
    return withBand(
      band: dark ? const Color(0xFF123B35) : const Color(0xFF16433C),
      onBandMuted: dark ? const Color(0xFFBBD9D2) : const Color(0xFFCFE7E1),
    );
  }

  /// A copy printed on a different [band].
  V360Colors withBand({required Color band, Color? onBandMuted}) => V360Colors(
        canvas: canvas,
        surface: surface,
        surfaceMuted: surfaceMuted,
        ink: ink,
        inkMuted: inkMuted,
        inkSubtle: inkSubtle,
        hairline: hairline,
        keyline: keyline,
        accent: accent,
        accentText: accentText,
        accentSurface: accentSurface,
        accentSurfaceStrong: accentSurfaceStrong,
        band: band,
        onBand: onBand,
        onBandMuted: onBandMuted ?? this.onBandMuted,
        actionFill: actionFill,
        onActionFill: onActionFill,
        onFill: onFill,
        voice: voice,
        onVoice: onVoice,
        voiceText: voiceText,
        voiceSurface: voiceSurface,
        warning: warning,
        warningText: warningText,
        warningSurface: warningSurface,
        danger: danger,
        dangerText: dangerText,
        dangerSurface: dangerSurface,
      );

  V360Colors lerp(V360Colors other, double t) {
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return V360Colors(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surfaceMuted: l(surfaceMuted, other.surfaceMuted),
      ink: l(ink, other.ink),
      inkMuted: l(inkMuted, other.inkMuted),
      inkSubtle: l(inkSubtle, other.inkSubtle),
      hairline: l(hairline, other.hairline),
      keyline: l(keyline, other.keyline),
      accent: l(accent, other.accent),
      accentText: l(accentText, other.accentText),
      accentSurface: l(accentSurface, other.accentSurface),
      accentSurfaceStrong: l(accentSurfaceStrong, other.accentSurfaceStrong),
      band: l(band, other.band),
      onBand: l(onBand, other.onBand),
      onBandMuted: l(onBandMuted, other.onBandMuted),
      actionFill: l(actionFill, other.actionFill),
      onActionFill: l(onActionFill, other.onActionFill),
      onFill: l(onFill, other.onFill),
      voice: l(voice, other.voice),
      onVoice: l(onVoice, other.onVoice),
      voiceText: l(voiceText, other.voiceText),
      voiceSurface: l(voiceSurface, other.voiceSurface),
      warning: l(warning, other.warning),
      warningText: l(warningText, other.warningText),
      warningSurface: l(warningSurface, other.warningSurface),
      danger: l(danger, other.danger),
      dangerText: l(dangerText, other.dangerText),
      dangerSurface: l(dangerSurface, other.dangerSurface),
    );
  }
}
