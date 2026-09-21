import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Loads the bundled fonts before any test runs.
///
/// Without this, `flutter test` renders text with a placeholder font that
/// draws every glyph as a filled box. Goldens would still catch layout and
/// colour regressions, but they would be useless for checking typography —
/// which is the main thing they are for here.
///
/// Flutter picks this file up automatically for every test in this package.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();

  const files = <String, String>{
    'AnekLatin': 'assets/fonts/AnekLatin-Variable.ttf',
    'AnekDevanagari': 'assets/fonts/AnekDevanagari-Variable.ttf',
  };

  // Styles built by V360Typography pass `package: 'vendor360_ui'`, so Flutter
  // resolves them as 'packages/vendor360_ui/<family>'. The bare family is
  // loaded too, for the ThemeData-level fontFamily.
  for (final entry in files.entries) {
    final file = File(entry.value);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in <String>[
      entry.key,
      'packages/vendor360_ui/${entry.key}',
    ]) {
      final loader = FontLoader(family)
        ..addFont(Future<ByteData>.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  }

  await testMain();
}
