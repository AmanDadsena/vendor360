import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../core/strings.dart';
import '../features/alerts/demo_banner.dart';
import 'providers.dart';

/// The persistent frame around the five primary destinations.
///
/// The bottom nav keeps every destination one tap away (UI/UX 4.4), and the
/// voice action sits in the middle where a thumb naturally rests — it is the
/// highest-frequency action in the product, so it gets the best position
/// rather than a corner.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Flush on launch: the app may have been killed with work still queued.
    WidgetsBinding.instance.addPostFrameCallback((_) => _flush());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the foreground is the most likely moment for signal to
    // have returned, so it is the cheapest place to retry the queue.
    if (state == AppLifecycleState.resumed) _flush();
  }

  Future<void> _flush() async {
    final outcome = await ref.read(syncProvider.notifier).flush();
    if (!mounted || outcome == null) return;

    if (outcome.conflicts > 0) {
      final s = ref.read(stringsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${outcome.applied} saved · ${outcome.conflicts} need review',
          ),
          action: SnackBarAction(
            label: s.retry,
            onPressed: () => context.go('/inventory'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Opens the socket while signed in and re-reads what each event touches.
    // Watched from the shell so liveness survives tab switches.
    ref
      ..watch(liveLifecycleProvider)
      ..watch(liveRefreshProvider);

    final s = ref.watch(stringsProvider);
    final sync = ref.watch(syncProvider);
    final v360 = context.v360;

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: Column(
        children: <Widget>[
          const DemoBanner(),
          Expanded(child: widget.navigationShell),
        ],
      ),
      bottomNavigationBar: _BottomNav(
        index: widget.navigationShell.currentIndex,
        onTap: (index) => widget.navigationShell.goBranch(
          index,
          // Tapping the active tab returns to that branch's root, which is the
          // behaviour people expect from a bottom nav.
          initialLocation: index == widget.navigationShell.currentIndex,
        ),
        labels: <String>[s.home, s.inventory, s.speak, s.forecast, s.score],
        queued: sync.queued,
        syncing: sync.syncing,
      ),
    );
  }
}

class _BottomNav extends StatelessWidget {
  const _BottomNav({
    required this.index,
    required this.onTap,
    required this.labels,
    required this.queued,
    required this.syncing,
  });

  final int index;
  final ValueChanged<int> onTap;
  final List<String> labels;
  final int queued;
  final bool syncing;

  static const List<IconData> _icons = <IconData>[
    Icons.home_outlined,
    Icons.inventory_2_outlined,
    Icons.mic_rounded,
    Icons.trending_up_rounded,
    Icons.verified_outlined,
  ];

  static const List<IconData> _activeIcons = <IconData>[
    Icons.home_rounded,
    Icons.inventory_2_rounded,
    Icons.mic_rounded,
    Icons.trending_up_rounded,
    Icons.verified_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    // Flat and ruled: a keyline on top, no shadow. The bar is part of the
    // printed page, not a card floating above it.
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
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: i == 2
                      ? _MicItem(
                          label: labels[i],
                          selected: i == index,
                          onTap: () => onTap(i),
                        )
                      : _NavItem(
                          selected: i == index,
                          icon: i == index ? _activeIcons[i] : _icons[i],
                          label: labels[i],
                          badge: i == 1 && queued > 0 ? queued : null,
                          syncing: syncing,
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

/// A plain destination: icon and word, with a short teal rule printed over
/// the selected one — the mark a pack uses to flag its variant.
class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    this.badge,
    this.syncing = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final int? badge;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);
    final tint = selected ? colors.accentText : colors.inkMuted;

    return Semantics(
      button: true,
      selected: selected,
      label: badge == null ? label : '$label, $badge waiting to sync',
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
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: syncing ? colors.accent : colors.danger,
                              borderRadius:
                                  BorderRadius.circular(V360Radius.sm),
                              border:
                                  Border.all(color: colors.surface, width: 1.5),
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

/// The microphone: a marigold disc set into the top edge of the bar.
///
/// It is the product's most frequent action, so it is the one round, loud
/// object on the screen, raised where the thumb rests. A white ring
/// separates it from the bar's keyline rather than a shadow.
class _MicItem extends StatelessWidget {
  const _MicItem({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  static const double _disc = 58;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.topCenter,
          children: <Widget>[
            Positioned(
              top: -20,
              child: Container(
                width: _disc,
                height: _disc,
                decoration: BoxDecoration(
                  color: colors.voice,
                  shape: BoxShape.circle,
                  border: Border.all(color: colors.surface, width: 4),
                ),
                child: Icon(Icons.mic_rounded, size: 28, color: colors.onVoice),
              ),
            ),
            Positioned(
              bottom: 8,
              child: Text(
                label,
                maxLines: 1,
                style: v360.text.label
                    .copyWith(color: colors.ink)
                    .weight(FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
