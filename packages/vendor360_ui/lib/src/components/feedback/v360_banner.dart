import 'package:flutter/material.dart';

import '../../tokens/v360_spacing.dart';
import '../../tokens/v360_theme.dart';

enum V360BannerTone { info, success, warning, danger }

/// A tinted informational banner.
///
/// Note each tone pairs a *surface* colour with a distinct *text* colour.
/// The fill colours (`danger`, `warning`) fail contrast as text on their own
/// tinted backgrounds, which is why `dangerText` and `warningText` exist.
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

    final (Color surface, Color content) = switch (tone) {
      V360BannerTone.info => (colors.surfaceMuted, colors.inkMuted),
      V360BannerTone.success => (colors.accentSurface, colors.accentText),
      V360BannerTone.warning => (colors.warningSurface, colors.warningText),
      V360BannerTone.danger => (colors.dangerSurface, colors.dangerText),
    };

    final banner = Container(
      padding: EdgeInsets.all(v360.spacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(V360Radius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: content),
          SizedBox(width: v360.spacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  style: v360.text.bodyStrong.copyWith(color: content),
                ),
                if (body != null) ...<Widget>[
                  SizedBox(height: v360.spacing.xs),
                  Text(
                    body!,
                    style: v360.text.caption.copyWith(color: colors.inkMuted),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return banner;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: banner,
    );
  }
}

/// A pale pill showing a supplier's rating — "4.6 ★ · 2-day lead".
///
/// Inherited from the CarryO operator badge; in Vendor360 it rates the
/// distributors and mandis surfaced beside the demand heatmap.
class TrustBadge extends StatelessWidget {
  const TrustBadge({super.key, required this.rating, required this.countLabel});

  final double rating;
  final String countLabel;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: v360.spacing.md,
        vertical: v360.spacing.xs,
      ),
      decoration: BoxDecoration(
        color: v360.colors.accentSurface,
        borderRadius: BorderRadius.circular(V360Radius.pill),
      ),
      child: Text(
        '${rating.toStringAsFixed(1)} ★ · $countLabel',
        style: v360.text.caption.copyWith(
          color: v360.colors.accentText,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Placeholder shown when a list has nothing in it.
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
    return Center(
      child: Padding(
        padding: EdgeInsets.all(v360.spacing.x3),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 40, color: v360.colors.inkSubtle),
            SizedBox(height: v360.spacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: v360.text.titleS.copyWith(color: v360.colors.ink),
            ),
            if (body != null) ...<Widget>[
              SizedBox(height: v360.spacing.sm),
              Text(
                body!,
                textAlign: TextAlign.center,
                style: v360.text.body.copyWith(color: v360.colors.inkMuted),
              ),
            ],
            if (action != null) ...<Widget>[
              SizedBox(height: v360.spacing.xxl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
