import 'package:flutter/foundation.dart';

/// What this device can actually do with a camera.
///
/// The same discipline the microphone follows: ask once, answer honestly,
/// and let the screen say which case it is in rather than showing a control
/// that does nothing. A black rectangle where a viewfinder should be is the
/// worst outcome — it reads as a bug, not as an unsupported platform.
@immutable
class CameraSupport {
  const CameraSupport({this.platform, this.web});

  /// Stand in for the running platform. Null means ask the framework; a
  /// value is only passed by tests, which need to render both branches.
  final TargetPlatform? platform;
  final bool? web;

  bool get _isWeb => web ?? kIsWeb;
  TargetPlatform get _target => platform ?? defaultTargetPlatform;

  bool get _isPhone =>
      !_isWeb &&
      (_target == TargetPlatform.android || _target == TargetPlatform.iOS);

  /// Live barcode reading through the viewfinder.
  ///
  /// Phones only. `mobile_scanner` will build on a desktop browser, but the
  /// shopkeeper it is built for is holding a phone, and a viewfinder that
  /// half-works on a laptop is worse than a field to type the code into.
  bool get canScan => _isPhone;

  /// Taking a photograph then and there.
  bool get canTakePhoto => _isPhone;

  /// Choosing an image that already exists.
  ///
  /// True nearly everywhere, because on desktop `image_picker` opens a file
  /// dialog. That is what keeps the receipt flow real on a laptop instead of
  /// reducing it to the bundled samples.
  bool get canPickImage => true;
}
