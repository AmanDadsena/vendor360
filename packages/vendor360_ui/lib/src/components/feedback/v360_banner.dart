import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

enum V360BannerTone { info, success, warning, danger }

/// A boxed notice, the way a pack boxes its "Caution" or "Storage" note.
///
/// White, with a one-pixel rule in the tone's colour all the way round and
/// the icon in that colour; the words stay ink. A tinted wash with coloured
/// text was the old treatment, and coloured text is what washes out first.
class V360Banner extends StatelessWidget {
  const V360Banner({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.tone = V360BannerTone.info,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? body;
  final V360BannerTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    final (Color rule, Color mark) = switch (tone) {
      V360BannerTone.info => (colors.hairline, colors.inkMuted),
      V360BannerTone.success => (colors.accent, colors.accent),
      V360BannerTone.warning => (colors.warning, colors.warningText),
      V360BannerTone.danger => (colors.danger, colors.dangerText),
    };

    return Material(
      color: tone == V360BannerTone.info ? colors.surfaceMuted : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(V360Radius.lg),
        side: BorderSide(color: rule),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(v360.spacing.md + 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, size: 20, color: mark),
              SizedBox(width: v360.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      style: v360.text.bodyStrong.copyWith(color: colors.ink),
                    ),
                    if (body != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        body!,
                        style:
                            v360.text.caption.copyWith(color: colors.inkMuted),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A supplier's rating — "4.6 · 2-day lead" behind a drawn star.
///
/// The star is an icon, not a text glyph: Anek has no star, and a glyph
/// borrowed from a fallback font never matches the line it sits in.
class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.rating, required this.countLabel});

  final double rating;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(Icons.star_rounded, size: 15, color: colors.voice),
        const SizedBox(width: 3),
        Text(
          '${rating.toStringAsFixed(1)} · $countLabel',
          style: v360.text.caption
              .copyWith(color: colors.ink)
              .weight(FontWeight.w600),
        ),
      ],
    );
  }
}

/// What a list says when it has nothing in it.
///
/// Left-aligned and small, like a note on the page rather than a poster in
/// the middle of it: a shopkeeper reading "No orders yet" should see what to
/// do next, not a large grey icon. The [body] is where a screen teaches —
/// say what will appear here and how it gets there.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String? body;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: v360.spacing.gutter,
        vertical: v360.spacing.x3,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 28, color: colors.inkSubtle),
          SizedBox(height: v360.spacing.md),
          Text(
            title,
            style: v360.text.titleS.copyWith(color: colors.ink),
          ),
          if (body != null) ...<Widget>[
            SizedBox(height: v360.spacing.xs),
            Text(
              body!,
              style: v360.text.body.copyWith(color: colors.inkMuted),
            ),
          ],
          if (action != null) ...<Widget>[
            SizedBox(height: v360.spacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
