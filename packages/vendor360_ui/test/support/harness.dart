import 'package:vendor360_ui/vendor360_ui.dart';
import 'package:flutter/material.dart';

/// Wraps a widget in the Vendor360 theme for tests.
Widget carryHarness(
  Widget child, {
  Brightness brightness = Brightness.light,
  bool disableAnimations = false,
}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildV360Theme(brightness),
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: MotionScope(
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}
