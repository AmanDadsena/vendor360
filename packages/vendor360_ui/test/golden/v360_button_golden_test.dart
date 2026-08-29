import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

Widget _allVariants() => SizedBox(
      width: 320,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          V360Button.primary(
            label: 'Find space',
            onPressed: () {},
            trailingIcon: Icons.arrow_forward,
            expand: true,
          ),
          const SizedBox(height: 12),
          V360Button.secondary(
            label: 'Directions',
            onPressed: () {},
            leadingIcon: Icons.place_outlined,
            expand: true,
          ),
          const SizedBox(height: 12),
          V360Button.ghost(
            label: 'Custom dimensions',
            onPressed: () {},
            expand: true,
          ),
          const SizedBox(height: 12),
          V360Button.danger(
            label: 'Reject parcel',
            onPressed: () {},
            expand: true,
          ),
          const SizedBox(height: 12),
          const V360Button.primary(
            label: 'Disabled',
            onPressed: null,
            expand: true,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              V360Button.primary(
                label: 'Small',
                onPressed: () {},
                size: V360ButtonSize.sm,
              ),
              V360Button.primary(
                label: 'Medium',
                onPressed: () {},
                size: V360ButtonSize.md,
              ),
            ],
          ),
        ],
      ),
    );

void main() {
  testWidgets('golden - buttons light', (tester) async {
    await tester.pumpWidget(carryHarness(_allVariants()));
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SizedBox).first,
      matchesGoldenFile('goldens/buttons_light.png'),
    );
  });

  testWidgets('golden - buttons dark', (tester) async {
    await tester.pumpWidget(
      carryHarness(_allVariants(), brightness: Brightness.dark),
    );
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(SizedBox).first,
      matchesGoldenFile('goldens/buttons_dark.png'),
    );
  });
}
