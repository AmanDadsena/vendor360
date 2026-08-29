import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('context.v360 exposes the light palette', (tester) async {
    late V360ThemeData v360;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildV360Theme(Brightness.light),
        home: Builder(builder: (context) {
          v360 = context.v360;
          return const SizedBox();
        }),
      ),
    );
    expect(v360.brightness, Brightness.light);
    expect(v360.isDark, isFalse);
    expect(v360.colors.actionFill, const Color(0xFF1A2E2A));
    expect(v360.spacing.gutter, 20);
  });

  testWidgets('context.v360 exposes the dark palette', (tester) async {
    late V360ThemeData v360;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildV360Theme(Brightness.dark),
        home: Builder(builder: (context) {
          v360 = context.v360;
          return const SizedBox();
        }),
      ),
    );
    expect(v360.brightness, Brightness.dark);
    expect(v360.isDark, isTrue);
    expect(v360.colors.actionFill, const Color(0xFF2FB39D));
  });

  // Regression: ThemeExtension files itself in ThemeData.extensions under a
  // getter named `type`. A field of that name on the extension shadows it,
  // so the entry lands under the wrong key and every lookup returns null.
  // Hence the typography field is called `text`.
  test('extension is filed under its own type', () {
    final theme = buildV360Theme(Brightness.light);
    expect(theme.extensions.keys, contains(V360ThemeData));
    expect(theme.extension<V360ThemeData>(), isNotNull);
  });

  test('scaffold background is the canvas token in both themes', () {
    expect(buildV360Theme(Brightness.light).scaffoldBackgroundColor,
        const Color(0xFFFAF9F6));
    expect(buildV360Theme(Brightness.dark).scaffoldBackgroundColor,
        const Color(0xFF0B1210));
  });

  test('theme uses bundled Inter as its default family', () {
    expect(buildV360Theme(Brightness.light).textTheme.bodyMedium?.fontFamily,
        contains('Inter'));
  });

  test('theme extension lerps between light and dark', () {
    final light =
        buildV360Theme(Brightness.light).extension<V360ThemeData>()!;
    final dark = buildV360Theme(Brightness.dark).extension<V360ThemeData>()!;
    final mid = light.lerp(dark, 0.5);
    expect(mid.colors.canvas, isNot(light.colors.canvas));
    expect(mid.colors.canvas, isNot(dark.colors.canvas));
  });

  testWidgets('context.motion resolves through MotionScope', (tester) async {
    late ResolvedMotion motion;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildV360Theme(Brightness.light),
        home: MotionScope(
          child: Builder(builder: (context) {
            motion = context.motion;
            return const SizedBox();
          }),
        ),
      ),
    );
    expect(motion.base, const Duration(milliseconds: 220));
  });
}
