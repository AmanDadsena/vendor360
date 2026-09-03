import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../../app/providers.dart';

/// Getting a shop usable in under two minutes.
///
/// A kirana store carries two hundred lines. Typing them is not a setup step,
/// it is a reason to abandon the app on the first evening — so this asks for
/// two taps (which aisles) and then presents the things shops in those aisles
/// actually stock, ranked by how commonly they are carried.
///
/// Quantities are deliberately not asked for. Guessing how much atta is on the
/// shelf would put a wrong number on the first screen, and a wrong number is
/// harder to trust than an empty one. The first voice entry or delivery fills
/// it in.
class SetupFlowScreen extends ConsumerStatefulWidget {
  const SetupFlowScreen({super.key});

  @override
  ConsumerState<SetupFlowScreen> createState() => _SetupFlowScreenState();
}

class _SetupFlowScreenState extends ConsumerState<SetupFlowScreen> {
  static const List<(String, String, IconData)> _aisles =
      <(String, String, IconData)>[
    ('staples', 'Staples & masala', Icons.rice_bowl_outlined),
    ('dairy', 'Dairy', Icons.egg_outlined),
    ('produce', 'Fruit & veg', Icons.eco_outlined),
    ('snacks', 'Snacks', Icons.cookie_outlined),
    ('beverages', 'Drinks', Icons.local_cafe_outlined),
    ('bakery', 'Bakery', Icons.bakery_dining_outlined),
    ('sweets', 'Sweets', Icons.cake_outlined),
    ('personal_care', 'Personal care', Icons.soap_outlined),
    ('household', 'Household', Icons.cleaning_services_outlined),
    ('monsoon', 'Monsoon', Icons.umbrella_outlined),
  ];

  final Set<String> _chosenAisles = <String>{'staples', 'dairy'};
  final Set<String> _chosenSkus = <String>{};
  int _step = 0;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Scaffold(
      backgroundColor: colors.canvas,
      appBar: AppBar(
        backgroundColor: colors.canvas,
        surfaceTintColor: Colors.transparent,
        leading: _step == 0
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() => _step = 0),
              ),
        actions: <Widget>[
          TextButton(
            // Skippable on purpose. Someone who wants to start by speaking
            // their stock should not be held behind a picker.
            onPressed: () => context.go('/'),
            child: Text('Skip', style: TextStyle(color: colors.inkMuted)),
          ),
        ],
      ),
      body: SafeArea(
        child: _step == 0 ? _aislesStep(context) : _skusStep(context),
      ),
    );
  }

  Widget _aislesStep(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Column(
      children: <Widget>[
        Expanded(
          child: ListView(
            padding: EdgeInsets.all(v360.spacing.gutter),
            children: <Widget>[
              Text(
                'What do you sell?',
                style: v360.text.display.copyWith(color: colors.ink),
              ),
              SizedBox(height: v360.spacing.sm),
              Text(
                'Pick the aisles you carry. We will show you the usual items '
                'in each, so you can tap instead of type.',
                style: v360.text.body.copyWith(color: colors.inkMuted),
              ),
              SizedBox(height: v360.spacing.xl),
              Wrap(
                spacing: v360.spacing.sm,
                runSpacing: v360.spacing.sm,
                children: <Widget>[
                  for (final (key, label, icon) in _aisles)
                    _AisleChip(
                      label: label,
                      icon: icon,
                      selected: _chosenAisles.contains(key),
                      onTap: () => setState(() {
                        if (!_chosenAisles.remove(key)) _chosenAisles.add(key);
                      }),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.all(v360.spacing.gutter),
          child: V360Button.primary(
            label: 'Next',
            expand: true,
            onPressed: _chosenAisles.isEmpty
                ? null
                : () => setState(() => _step = 1),
          ),
        ),
      ],
    );
  }

  Widget _skusStep(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final language = ref.watch(languageProvider);
    final catalog =
        ref.watch(masterCatalogProvider(_chosenAisles.join(',')));

    return Column(
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(
            v360.spacing.gutter,
            0,
            v360.spacing.gutter,
            v360.spacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Tap what you stock',
                style: v360.text.titleL.copyWith(color: colors.ink),
              ),
              SizedBox(height: v360.spacing.xs),
              Text(
                'Just the ones you carry — you can add more any time, or say '
                'them out loud later.',
                style: v360.text.caption.copyWith(color: colors.inkMuted),
              ),
            ],
          ),
        ),
        Expanded(
          child: catalog.when(
            loading: () => ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: v360.spacing.gutter),
              itemCount: 6,
              itemBuilder: (_, _) => Padding(
                padding: EdgeInsets.only(bottom: v360.spacing.sm),
                child: const V360Skeleton(height: 52),
              ),
            ),
            error: (error, _) => EmptyState(
              icon: Icons.cloud_off_rounded,
              title: 'Could not load the item list',
              body: 'You can still add items by hand or by speaking them.',
              action: V360Button.secondary(
                label: 'Go to the app',
                onPressed: () => context.go('/'),
              ),
            ),
            data: (skus) => ListView(
              padding: EdgeInsets.fromLTRB(
                v360.spacing.gutter,
                0,
                v360.spacing.gutter,
                v360.spacing.lg,
              ),
              children: <Widget>[
                for (final sku in skus)
                  _SkuTile(
                    title: sku.nameFor(language),
                    subtitle: sku.nameEn == sku.nameFor(language)
                        ? '₹${sku.typicalPrice.round()} / ${sku.unit}'
                        : '${sku.nameEn} · ₹${sku.typicalPrice.round()} / ${sku.unit}',
                    selected: _chosenSkus.contains(sku.key),
                    onTap: () => setState(() {
                      if (!_chosenSkus.remove(sku.key)) {
                        _chosenSkus.add(sku.key);
                        HapticFeedback.selectionClick();
                      }
                    }),
                  ),
              ],
            ),
          ),
        ),
        Container(
          padding: EdgeInsets.all(v360.spacing.gutter),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.hairline)),
          ),
          child: SafeArea(
            top: false,
            child: V360Button.primary(
              label: _chosenSkus.isEmpty
                  ? 'Add items later'
                  : 'Add ${_chosenSkus.length} '
                      '${_chosenSkus.length == 1 ? 'item' : 'items'}',
              expand: true,
              loading: _busy,
              onPressed: _busy ? null : _finish,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _finish() async {
    if (_chosenSkus.isEmpty) {
      context.go('/');
      return;
    }

    setState(() => _busy = true);
    try {
      final created =
          await ref.read(marketplaceProvider).quickAdd(_chosenSkus.toList());
      ref
        ..invalidate(inventoryProvider)
        ..invalidate(dashboardProvider);

      if (!mounted) return;
      HapticFeedback.mediumImpact();
      context.go('/');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$created ${created == 1 ? 'item' : 'items'} added. '
            'Say what you sell as you go and the counts fill in.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$error'),
          backgroundColor: context.v360.colors.danger,
        ),
      );
    }
  }
}

class _AisleChip extends StatelessWidget {
  const _AisleChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return V360Pressable(
      onTap: onTap,
      child: AnimatedContainer(
        duration: MotionScope.of(context).base,
        padding: EdgeInsets.symmetric(
          horizontal: v360.spacing.lg,
          vertical: v360.spacing.md,
        ),
        decoration: BoxDecoration(
          color: selected ? colors.accentSurfaceStrong : colors.surface,
          borderRadius: BorderRadius.circular(V360Radius.pill),
          border: Border.all(
            color: selected ? colors.accent : colors.hairline,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 17,
              color: selected ? colors.accentText : colors.inkMuted,
            ),
            SizedBox(width: v360.spacing.sm),
            Text(
              label,
              style: v360.text.body.copyWith(
                color: selected ? colors.accentText : colors.ink,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SkuTile extends StatelessWidget {
  const _SkuTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Padding(
      padding: EdgeInsets.only(bottom: v360.spacing.sm),
      child: V360Pressable(
        onTap: onTap,
        child: AnimatedContainer(
          duration: MotionScope.of(context).fast,
          padding: EdgeInsets.all(v360.spacing.md),
          decoration: BoxDecoration(
            color: selected ? colors.accentSurface : colors.surface,
            borderRadius: BorderRadius.circular(V360Radius.md),
            border: Border.all(
              color: selected ? colors.accent : colors.hairline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                size: 20,
                color: selected ? colors.accent : colors.inkSubtle,
              ),
              SizedBox(width: v360.spacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      title,
                      style: v360.text.body.copyWith(color: colors.ink),
                    ),
                    Text(
                      subtitle,
                      style:
                          v360.text.label.copyWith(color: colors.inkSubtle),
                    ),
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
