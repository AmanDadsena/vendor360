import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('resolves full durations when animations are enabled',
      (tester) async {
    late ResolvedMotion motion;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: MotionScope(
          child: Builder(builder: (context) {
            motion = MotionScope.of(context);
            return const SizedBox();
          }),
        ),
      ),
    );

    expect(motion.reduced, isFalse);
    expect(motion.base, const Duration(milliseconds: 220));
    expect(motion.fast, const Duration(milliseconds: 140));
  });

  // One switch at the root; the whole app complies.
  testWidgets('collapses every duration when reduce-motion is on',
      (tester) async {
    late ResolvedMotion motion;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MotionScope(
          child: Builder(builder: (context) {
            motion = MotionScope.of(context);
            return const SizedBox();
          }),
        ),
      ),
    );

    expect(motion.reduced, isTrue);
    for (final d in <Duration>[
      motion.instant, motion.fast, motion.base,
      motion.slow, motion.deliberate,
    ]) {
      expect(d, Duration.zero);
    }
  });

  testWidgets('curves are preserved even when motion is reduced',
      (tester) async {
    late ResolvedMotion motion;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: MotionScope(
          child: Builder(builder: (context) {
            motion = MotionScope.of(context);
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(motion.standard, isNotNull);
    expect(motion.emphasized, isNotNull);
  });

  testWidgets('falls back to full motion outside a MotionScope',
      (tester) async {
    late ResolvedMotion motion;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(builder: (context) {
          motion = MotionScope.of(context);
          return const SizedBox();
        }),
      ),
    );
    expect(motion.base, const Duration(milliseconds: 220));
  });

  test('duration scale is strictly ordered', () {
    const m = V360Motion();
    expect(m.instant < m.fast, isTrue);
    expect(m.fast < m.base, isTrue);
    expect(m.base < m.slow, isTrue);
    expect(m.slow < m.deliberate, isTrue);
  });
}
