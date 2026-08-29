import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

void main() {
  final light = V360Colors.light();

  group('CapacityBar', () {
    test('colour thresholds follow the design', () {
      expect(CapacityBar.colorFor(light, 0.00), light.accent);
      expect(CapacityBar.colorFor(light, 0.50), light.accent);
      expect(CapacityBar.colorFor(light, 0.74), light.accent);
      expect(CapacityBar.colorFor(light, 0.75), light.warning);
      expect(CapacityBar.colorFor(light, 0.94), light.warning);
      expect(CapacityBar.colorFor(light, 0.96), light.danger);
    });

    test('fraction is clamped to 0..1', () {
      expect(CapacityBar.colorFor(light, -1), light.accent);
      expect(CapacityBar.colorFor(light, 5), light.danger);
    });

    testWidgets('animates to its fraction and settles', (tester) async {
      await tester.pumpWidget(carryHarness(
        const SizedBox(width: 200, child: CapacityBar(fraction: 0.8)),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(CapacityBar), findsOneWidget);
    });

    testWidgets('has no running animation under reduce-motion',
        (tester) async {
      await tester.pumpWidget(carryHarness(
        const SizedBox(width: 200, child: CapacityBar(fraction: 0.8)),
        disableAnimations: true,
      ));
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('V360Banner', () {
    testWidgets('danger uses dangerText, not the danger fill', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360Banner(
          icon: Icons.warning_amber_rounded,
          title: 'Say the code only at the counter',
          tone: V360BannerTone.danger,
        ),
      ));
      final style = tester
          .widget<Text>(find.text('Say the code only at the counter'))
          .style!;
      expect(style.color, const Color(0xFFB03B2C));
      expect(style.color, isNot(light.danger));
    });

    testWidgets('success uses accentSurface and accentText', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360Banner(
          icon: Icons.check_circle,
          title: 'Loaded in boot',
          tone: V360BannerTone.success,
        ),
      ));
      expect(
        tester.widget<Text>(find.text('Loaded in boot')).style!.color,
        const Color(0xFF0A5A4F),
      );
    });

    testWidgets('renders an optional body line', (tester) async {
      await tester.pumpWidget(carryHarness(
        const V360Banner(
          icon: Icons.info,
          title: 'Title',
          body: 'Supporting detail',
        ),
      ));
      expect(find.text('Supporting detail'), findsOneWidget);
    });
  });

  group('StatusPill and TrustBadge', () {
    testWidgets('StatusPill renders its label', (tester) async {
      await tester.pumpWidget(carryHarness(
        const StatusPill(label: 'In stock', tone: PillTone.healthy),
      ));
      expect(find.text('In stock'), findsOneWidget);
      // Colour is never the only status signal — the guide requires an icon
      // or label alongside it for colour-blind users.
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('TrustBadge formats rating and count', (tester) async {
      await tester.pumpWidget(carryHarness(
        const TrustBadge(rating: 4.6, countLabel: '2-day lead'),
      ));
      expect(find.text('4.6 ★ · 2-day lead'), findsOneWidget);
    });
  });

  group('EmptyState', () {
    testWidgets('renders title, body and action', (tester) async {
      await tester.pumpWidget(carryHarness(
        EmptyState(
          icon: Icons.inbox,
          title: 'No requests yet',
          body: 'New parcel requests appear here.',
          action: V360Button.primary(label: 'Refresh', onPressed: () {}),
        ),
      ));
      expect(find.text('No requests yet'), findsOneWidget);
      expect(find.text('New parcel requests appear here.'), findsOneWidget);
      expect(find.byType(V360Button), findsOneWidget);
    });
  });

  group('RollingNumber and MetricTile', () {
    testWidgets('renders its value with prefix and suffix', (tester) async {
      await tester.pumpWidget(carryHarness(
        const RollingNumber(value: 340, prefix: '₹'),
      ));
      expect(find.text('₹'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('MetricTile uppercases its label', (tester) async {
      await tester.pumpWidget(carryHarness(
        const MetricTile(label: 'parcels moved', value: 18),
      ));
      expect(find.text('PARCELS MOVED'), findsOneWidget);
    });
  });

  group('V360Segmented', () {
    testWidgets('selected chip uses actionFill and inverts by theme',
        (tester) async {
      Widget build() => V360Segmented<String>(
            segments: const <V360Segment<String>>[
              V360Segment<String>(value: 'a', label: 'Tonight'),
              V360Segment<String>(value: 'b', label: 'Tomorrow'),
            ],
            value: 'a',
            onChanged: (_) {},
          );

      await tester.pumpWidget(carryHarness(build()));
      await tester.pumpAndSettle();
      var decoration = tester
          .widget<AnimatedContainer>(
              find.byType(AnimatedContainer).first)
          .decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF1A2E2A));

      await tester.pumpWidget(
        carryHarness(build(), brightness: Brightness.dark),
      );
      await tester.pumpAndSettle();
      decoration = tester
          .widget<AnimatedContainer>(
              find.byType(AnimatedContainer).first)
          .decoration! as BoxDecoration;
      expect(decoration.color, const Color(0xFF2FB39D));
    });

    testWidgets('tapping an unselected chip reports its value',
        (tester) async {
      String? picked;
      await tester.pumpWidget(carryHarness(
        V360Segmented<String>(
          segments: const <V360Segment<String>>[
            V360Segment<String>(value: 'a', label: 'Tonight'),
            V360Segment<String>(value: 'b', label: 'Tomorrow'),
          ],
          value: 'a',
          onChanged: (v) => picked = v,
        ),
      ));
      await tester.tap(find.text('Tomorrow'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
    });

    testWidgets('tapping the selected chip does not fire', (tester) async {
      var fired = 0;
      await tester.pumpWidget(carryHarness(
        V360Segmented<String>(
          segments: const <V360Segment<String>>[
            V360Segment<String>(value: 'a', label: 'Tonight'),
          ],
          value: 'a',
          onChanged: (_) => fired++,
        ),
      ));
      await tester.tap(find.text('Tonight'));
      await tester.pumpAndSettle();
      expect(fired, 0);
    });

    testWidgets('renders a sublabel when given one', (tester) async {
      await tester.pumpWidget(carryHarness(
        V360Segmented<String>(
          segments: const <V360Segment<String>>[
            V360Segment<String>(
                value: 'm', label: 'Medium', sublabel: '≤ 18 cu ft'),
          ],
          value: 'm',
          onChanged: (_) {},
        ),
      ));
      expect(find.text('Medium'), findsOneWidget);
      expect(find.text('≤ 18 cu ft'), findsOneWidget);
    });
  });
}
