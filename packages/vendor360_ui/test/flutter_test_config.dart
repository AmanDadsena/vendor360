import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled Inter font before any test runs.
///
/// Without this, `flutter test` renders text with a placeholder font that
/// draws every glyph as a filled box. Goldens would still catch layout and
/// colour regressions, but they would be useless for verifying typography
/// against the Vendor360 UI/UX Design Guide — which is the main thing they are for here.
///
/// Flutter picks this file up automatically for every test in this package.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  final bytes = File('assets/fonts/Inter-Variable.ttf').readAsBytesSync();
  ByteData toData() => ByteData.sublistView(bytes);

  // Styles built by V360Typography v360 `package: 'vendor360_ui'`, so Flutter
  // resolves them as 'packages/vendor360_ui/Inter'. The bare family is loaded
  // too, for the ThemeData-level fontFamily.
  for (final family in <String>['Inter', 'packages/vendor360_ui/Inter']) {
    final loader = FontLoader(family)..addFont(Future<ByteData>.value(toData()));
    await loader.load();
  }

  await testMain();
}
