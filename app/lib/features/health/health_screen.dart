import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';
import '../../core/strings.dart';

/// The micro-credit Health Score.
///
/// The breakdown is always on screen, never behind a tap. This number can
/// influence whether a vendor gets credit, and the guide is explicit that it
/// must never feel like an opaque judgment — so the weights and the arithmetic
/// are shown, and a provisional score says so plainly rather than presenting
/// thin data as a firm result.
class HealthScreen extends ConsumerWidget {
  const HealthScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final s = ref.watch(stringsProvider);
    final score = ref.watch(healthScoreProvider);

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: v360.colors.accent,
          onRefresh: () async {
            HapticFeedback.lightImpact();
            ref.invalidate(healthScoreProvider);
            ref.invalidate(consentsProvider);
          },
          child: score.when(
            loading: () => ListView(
              padding: EdgeInsets.all(v360.spacing.gutter),
              children: <Widget>[
                const V360Skeleton(height: 220),
                SizedBox(height: v360.spacing.xl),
                const V360Skeleton(height: 260),
              ],
            ),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load your score',
              body: '$error',
              action: V360Button.primary(
                label: s.retry,
                onPressed: () => ref.invalidate(healthScoreProvider),
              ),
            ),
            data: (data) => _Body(score: data, strings: s),
          ),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.score, required this.strings});

  final HealthScore score;
  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        v360.spacing.gutter,
        v360.spacing.lg,
        v360.spacing.gutter,
        v360.spacing.x5,
      ),
      children: <Widget>[
        Text(
          strings.healthScore,
          style: v360.text.titleL.copyWith(color: colors.ink),
        ),
        SizedBox(height: v360.spacing.xxl),

        V360Reveal(
          child: Center(
            child: HealthDial(
              score: score.score,
              provisional: score.provisional,
              bandLabel: score.band.label,
            ),
          ),
        ),
        SizedBox(height: v360.spacing.xl),

        V360Reveal(
          delayIndex: 1,
          child: Container(
            padding: EdgeInsets.all(v360.spacing.lg),
            decoration: BoxDecoration(
              color: score.provisional ? colors.warningSurface : colors.accentSurface,
              borderRadius: BorderRadius.circular(V360Radius.md),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  score.provisional
                      ? Icons.hourglass_bottom_rounded
                      : Icons.insights_rounded,
                  size: 18,
                  color: score.provisional ? colors.warningText : colors.accentText,
                ),
                SizedBox(width: v360.spacing.sm),
                Expanded(
                  child: Text(
                    score.explanation,
                    style: v360.text.body.copyWith(
                      color: score.provisional
                          ? colors.warningText
                          : colors.accentText,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: v360.spacing.x3),

        V360Reveal(delayIndex: 2, child: const SectionLabel('How this is calculated')),
        SizedBox(height: v360.spacing.sm),

        V360Reveal(
          delayIndex: 3,
          child: V360Card(
            child: Column(
              children: <Widget>[
                for (var i = 0; i < score.components.length; i++) ...<Widget>[
                  ScoreFactorBar(
                    label: score.components[i].label,
                    value: score.components[i].value,
                    weight: score.components[i].weight,
                    contribution: score.components[i].contribution,
                    detail: score.components[i].detail,
                    delayIndex: i,
                  ),
                  if (i < score.components.length - 1)
                    Divider(color: colors.hairline, height: 1),
                ],
                Divider(color: colors.hairline, height: v360.spacing.xl),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        'Total',
                        style: v360.text.bodyStrong.copyWith(color: colors.ink),
                      ),
                    ),
                    Text(
                      score.score.toStringAsFixed(1),
                      style: v360.text.titleM.copyWith(color: colors.accentText),
                    ),
                  ],
                ),
                SizedBox(height: v360.spacing.sm),
                Text(
                  'Based on ${score.daysOfHistory} days of your own activity. '
                  'Nothing else is used.',
                  style: v360.text.caption.copyWith(color: colors.inkSubtle),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: v360.spacing.x3),

        V360Reveal(delayIndex: 4, child: SectionLabel(strings.shareWithLender)),
        SizedBox(height: v360.spacing.sm),
        V360Reveal(delayIndex: 5, child: _ConsentList(strings: strings)),

        SizedBox(height: v360.spacing.xl),
        V360Button.ghost(
          label: 'Sign out',
          expand: true,
          onPressed: () {
            HapticFeedback.lightImpact();
            ref.read(sessionProvider.notifier).signOut();
          },
        ),
      ],
    );
  }
}

/// Per-lender consent toggles.
///
/// Off by default and revocable. The PRD names data-sharing hesitancy as a
/// risk and prescribes showing the vendor their score before any lender sees
/// it — so consent is granted per lender rather than as one blanket switch.
class _ConsentList extends ConsumerWidget {
  const _ConsentList({required this.strings});

  final Strings strings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final v360 = context.v360;
    final colors = v360.colors;
    final consents = ref.watch(consentsProvider);

    return V360Card(
      child: consents.when(
        loading: () => const V360Skeleton(height: 120),
        error: (_, _) => Text(
          'Lender list unavailable offline.',
          style: v360.text.caption.copyWith(color: colors.inkMuted),
        ),
        data: (list) => Column(
          children: <Widget>[
            for (final consent in list)
              // ListTile paints its ink splash on the nearest Material
              // ancestor, and V360Card's coloured Container occludes it — so
              // without this the toggle gives no touch feedback at all. That
              // matters most on exactly this control: it decides whether a
              // lender can see the vendor's score, and a vendor who cannot tell
              // whether the tap registered will tap again and flip it back.
              Material(
                color: Colors.transparent,
                child: SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: consent.granted,
                  activeThumbColor: colors.accent,
                  title: Text(
                    consent.lenderName,
                    style: v360.text.bodyStrong.copyWith(color: colors.ink),
                  ),
                  subtitle: Text(
                    consent.lenderKind.toUpperCase(),
                    style: v360.text.label.copyWith(color: colors.inkSubtle),
                  ),
                  onChanged: (value) async {
                    HapticFeedback.selectionClick();
                    await ref
                        .read(repositoryProvider)
                        .setConsent(consent.lenderId, value);
                    ref.invalidate(consentsProvider);
                  },
                ),
              ),
            SizedBox(height: v360.spacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(Icons.lock_outline_rounded, size: 14, color: colors.inkSubtle),
                SizedBox(width: v360.spacing.xs),
                Expanded(
                  child: Text(
                    strings.consentNote,
                    style: v360.text.caption.copyWith(color: colors.inkSubtle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
