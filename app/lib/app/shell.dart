import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import '../core/strings.dart';
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
    final s = ref.watch(stringsProvider);
    final sync = ref.watch(syncProvider);
    final v360 = context.v360;

    return Scaffold(
      backgroundColor: v360.colors.canvas,
      body: widget.navigationShell,
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
    Icons.mic_none_rounded,
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

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(top: BorderSide(color: colors.hairline)),
        boxShadow: V360Elevation.floating(v360.brightness),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 68,
          child: Row(
            children: <Widget>[
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: _NavItem(
                    // The voice tab is the product's primary action, so it is
                    // rendered as a saffron pill rather than another grey icon.
                    isVoice: i == 2,
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

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isVoice,
    this.badge,
    this.syncing = false,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isVoice;
  final int? badge;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    final v360 = context.v360;
    final colors = v360.colors;
    final motion = MotionScope.of(context);

    final tint = isVoice
        ? colors.voice
        : selected
            ? colors.accentText
            : colors.inkSubtle;

    return Semantics(
      button: true,
      selected: selected,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                AnimatedContainer(
                  duration: motion.base,
                  curve: motion.standard,
                  padding: EdgeInsets.symmetric(
                    horizontal: isVoice ? 18 : 14,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: isVoice
                        ? colors.voiceSurface
                        : selected
                            ? colors.accentSurface
                            : Colors.transparent,
                    borderRadius: BorderRadius.circular(V360Radius.pill),
                  ),
                  child: Icon(icon, size: 22, color: tint),
                ),
                if (badge != null)
                  Positioned(
                    right: 2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: syncing ? colors.accent : colors.warning,
                        borderRadius: BorderRadius.circular(V360Radius.pill),
                        border: Border.all(color: colors.surface, width: 1.5),
                      ),
                      child: Text(
                        '$badge',
                        style: v360.text.label.copyWith(
                          color: Colors.white,
                          fontSize: 9,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: v360.text.label.copyWith(
                color: tint,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
