import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../features/alerts/demo_banner.dart';
import 'providers.dart';

/// The frame around the wholesaler's five destinations.
///
/// Deliberately not a copy of the vendor shell with different icons. The
/// vendor's centre tab is the voice orb, because speaking is the highest
/// frequency action in a shop. A wholesaler's equivalent is the order inbox —
/// they sit with a phone and a ledger and answer requests — so *that* gets the
/// prominent slot, with a live count of what is unanswered.
class DistShell extends ConsumerWidget {
  const DistShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref
      ..watch(liveLifecycleProvider)
      ..watch(liveRefreshProvider);

    final v360 = context.v360;

    // Watched rather than passed down: the badge has to move the moment an
    // order is confirmed on the Orders tab, without that screen knowing the
    // shell exists.
    final pending = ref
        .watch(distSummaryProvider)
        .maybeWhen(data: (s) => s.needsAction, orElse: () => 0);

    // The same pack line printed on a deeper bottle-green band, so a shop
    // screen and a wholesaler screen are never mistaken for each other.
    return Theme(
      data: buildV360Theme(v360.brightness, distributor: true),
      child: Scaffold(
        backgroundColor: v360.colors.canvas,
        body: Column(
          children: <Widget>[
            const DemoBanner(),
            Expanded(child: navigationShell),
          ],
        ),
        bottomNavigationBar: _DistNav(
          index: navigationShell.currentIndex,
          pending: pending,
          onTap: (index) => navigationShell.goBranch(
            index,
            initialLocation: index == navigationShell.currentIndex,
          ),
        ),
      ),
    );
  }
}

class _DistNav extends StatelessWidget {
  const _DistNav({
    required this.index,
    required this.onTap,
    required this.pending,
  });

  final int index;
  final ValueChanged<int> onTap;
  final int pending;

  static const List<String> _labels = <String>[
    'Today',
    'Orders',
    'Demand',
    'Catalog',
    'Shops',
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.today_outlined,
    Icons.inbox_outlined,
    Icons.insights_outlined,
    Icons.sell_outlined,
    Icons.storefront_outlined,
  ];

  static const List<IconData> _active = <IconData>[
    Icons.today_rounded,
    Icons.inbox_rounded,
    Icons.insights_rounded,
    Icons.sell_rounded,
    Icons.storefront_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    // Flat and ruled, like the shop's bar. The waiting count on Orders is the
    // emphasis; the tab itself does not need to shout.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var i = 0; i < _labels.length; i++)
                Expanded(
                  child: _NavItem(
                    selected: i == index,
                    icon: i == index ? _active[i] : _icons[i],
                    label: _labels[i],
                    badge: i == 1 && pending > 0 ? pending : null,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);
    final tint = selected ? colors.accentText : colors.inkMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge waiting',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Stack(
          children: <Widget>[
            Align(
              alignment: Alignment.topCenter,
              child: AnimatedContainer(
                duration: motion.fast,
                curve: motion.standard,
                width: selected ? 28 : 0,
                height: 3,
                color: colors.accent,
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Stack(
                    clipBehavior: Clip.none,
                    children: <Widget>[
                      Icon(icon, size: 24, color: tint),
                      if (badge != null)
                        Positioned(
                          right: -10,
                          top: -4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: colors.danger,
                              borderRadius: BorderRadius.circular(
                                V360Radius.sm,
                              ),
                              border: Border.all(
                                color: colors.surface,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              '$badge',
                              style: v360.text.label
                                  .copyWith(color: colors.onFill, fontSize: 10)
                                  .weight(FontWeight.w700),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: v360.text.label
                        .copyWith(color: tint)
                        .weight(selected ? FontWeight.w700 : FontWeight.w500),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
