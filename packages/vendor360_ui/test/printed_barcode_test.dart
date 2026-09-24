import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// The barcode has to be a real one.
///
/// A scanner validates the check digit and the module pattern before it
/// reports a read, so a pattern of stripes that merely looks like a barcode
/// never scans. These tests check the encoding against the standard rather
/// than against how the drawing looks.
void main() {
  group('the encoding', () {
    test('computes the check digit the way a scanner verifies it', () {
      // 890 is India's GS1 prefix; these are the codes the seeder prints.
      expect(Ean13.checkDigit('890900000000'), 8);
      expect(Ean13.checkDigit('890171910101'), 4);
    });

    test('accepts a well-formed code and rejects a mistyped one', () {
      expect(Ean13.isValid('8909000000008'), isTrue);
      // Last digit off by one: a real scanner would refuse this too.
      expect(Ean13.isValid('8909000000007'), isFalse);
      expect(Ean13.isValid('89090000000'), isFalse, reason: 'too short');
      expect(Ean13.isValid('890900000000X'), isFalse, reason: 'not digits');
    });

    test('lays out 95 modules with the guards where the standard puts them',
        () {
      final modules = Ean13.modules('8909000000008')!;

      expect(modules.length, 95);
      expect(modules.substring(0, 3), '101', reason: 'start guard');
      expect(modules.substring(45, 50), '01010', reason: 'centre guard');
      expect(modules.substring(92), '101', reason: 'end guard');
    });

    test('encodes the first digit as parity, never as bars', () {
      // Two codes differing only in their leading digit must still differ,
      // because that digit lives in the left group's L/G pattern.
      const a = '8909000000008';
      const bodyB = '790900000000';
      final b = '$bodyB${Ean13.checkDigit(bodyB)}';

      expect(Ean13.isValid(b), isTrue);
      expect(Ean13.modules(a), isNot(Ean13.modules(b)));
    });

    test('the bars decode back to the number, which is the real proof', () {
      // The guard positions can be right while the digit tables are wrong.
      // Reading the pattern back the way a scanner does is the only check
      // that catches a transposed row in the L, G or R table.
      for (final code in <String>[
        '8909000000008',
        '8909012331534',
        '8901719101014',
        '4006381333931',
      ]) {
        expect(_decode(Ean13.modules(code)!), code, reason: code);
      }
    });

    test('a code a scanner would reject produces no bars at all', () {
      expect(Ean13.modules('8909000000007'), isNull);
    });
  });

  group('the widget', () {
    Widget host(String code) => MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: Scaffold(
            body: Center(
              child: SizedBox(width: 240, child: PrintedBarcode(code: code)),
            ),
          ),
        );

    testWidgets('prints the digits grouped the way a pack prints them',
        (tester) async {
      await tester.pumpWidget(host('8909000000008'));

      expect(find.text('8  909000  000008'), findsOneWidget);
    });

    testWidgets('says so rather than drawing a pattern that cannot be read',
        (tester) async {
      await tester.pumpWidget(host('8909000000007'));

      expect(find.textContaining('not a readable code'), findsOneWidget);
      expect(find.byType(CustomPaint).evaluate().length, lessThan(3));
    });

    testWidgets('carries the number for anyone who cannot see the bars',
        (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(host('8909000000008'));

      expect(find.bySemanticsLabel('Barcode 8909000000008'), findsOneWidget);
      handle.dispose();
    });
  });
}

/// Read a 95-module pattern back to its thirteen digits, the way a scanner
/// does: match each seven-module cell against the three tables, recover the
/// leading digit from the left group's parity, and return the lot.
String _decode(String modules) {
  const left = <String>[
    '0001101', '0011001', '0010011', '0111101', '0100011',
    '0110001', '0101111', '0111011', '0110111', '0001011',
  ];
  const g = <String>[
    '0100111', '0110011', '0011011', '0100001', '0011101',
    '0111001', '0000101', '0010001', '0001001', '0010111',
  ];
  const right = <String>[
    '1110010', '1100110', '1101100', '1000010', '1011100',
    '1001110', '1010000', '1000100', '1001000', '1110100',
  ];
  const parity = <String>[
    'LLLLLL', 'LLGLGG', 'LLGGLG', 'LLGGGL', 'LGLLGG',
    'LGGLLG', 'LGGGLL', 'LGLGLG', 'LGLGGL', 'LGGLGL',
  ];

  final digits = StringBuffer();
  final seen = StringBuffer();

  for (var i = 0; i < 6; i++) {
    final cell = modules.substring(3 + i * 7, 10 + i * 7);
    final asL = left.indexOf(cell);
    if (asL >= 0) {
      digits.write(asL);
      seen.write('L');
    } else {
      digits.write(g.indexOf(cell));
      seen.write('G');
    }
  }
  for (var i = 0; i < 6; i++) {
    digits.write(right.indexOf(modules.substring(50 + i * 7, 57 + i * 7)));
  }

  return '${parity.indexOf(seen.toString())}$digits';
}
