import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vendor360_core/vendor360_core.dart';

/// What the microphone heard, and how sure it is.
@immutable
class Heard {
  const Heard({
    required this.text,
    required this.confidence,
    this.simulated = false,
  });

  final String text;

  /// The engine's own confidence. Real ASR rarely returns certainty, and the
  /// parse pipeline downstream uses this to decide what needs review.
  final double confidence;

  /// True when this came from the sample set rather than a microphone.
  final bool simulated;
}

/// Dictation, with an honest answer when the platform cannot do it.
abstract class Dictation {
  /// Whether this platform can actually listen. Asked before offering to.
  Future<bool> available();

  /// Listens once and returns what it heard.
  ///
  /// [onPartial] fires as words arrive so the transcript field fills while
  /// the shopkeeper is still speaking — the feedback that tells them it is
  /// working.
  Future<Heard> listen({
    required AppLanguage language,
    void Function(String partial)? onPartial,
  });

  Future<void> stop();
}

/// The device's own speech engine.
///
/// Locale follows the app's language, because a shopkeeper who set the app to
/// Marathi is going to speak Marathi, and an engine listening for en-IN will
/// return confident nonsense rather than nothing — the worst failure of the
/// three.
class DeviceDictation implements Dictation {
  DeviceDictation([stt.SpeechToText? engine])
      : _engine = engine ?? stt.SpeechToText();

  final stt.SpeechToText _engine;
  bool? _ready;

  static const Map<AppLanguage, String> _locales = <AppLanguage, String>{
    AppLanguage.hindi: 'hi_IN',
    AppLanguage.marathi: 'mr_IN',
    AppLanguage.english: 'en_IN',
  };

  @override
  Future<bool> available() async {
    if (_ready != null) return _ready!;
    try {
      _ready = await _engine.initialize(
        // Errors and status are swallowed here on purpose: the caller's
        // question is only "can this platform listen", and a plugin that
        // throws on an unsupported browser must not take the screen with it.
        onError: (_) {},
        onStatus: (_) {},
      );
    } catch (_) {
      _ready = false;
    }
    return _ready!;
  }

  @override
  Future<Heard> listen({
    required AppLanguage language,
    void Function(String partial)? onPartial,
  }) async {
    final completer = Completer<Heard>();
    var best = '';
    var confidence = 0.0;

    await _engine.listen(
      onResult: (result) {
        best = result.recognizedWords;
        if (result.confidence > 0) confidence = result.confidence;
        onPartial?.call(best);
        if (result.finalResult && !completer.isCompleted) {
          completer.complete(
            Heard(
              text: best,
              // Some engines report zero rather than a figure; treating that
              // as "no confidence" would send every utterance to review, so
              // it falls back to a value that still trips the review path
              // when the parser is unsure.
              confidence: confidence == 0 ? 0.8 : confidence,
            ),
          );
        }
      },
      listenOptions: stt.SpeechListenOptions(
        localeId: _locales[language],
        partialResults: true,
        listenMode: stt.ListenMode.dictation,
        cancelOnError: true,
        // A sentence of stock, not a dictaphone: long enough for "20 doodh
        // packet aur 5 kilo chawal beche", short enough that a pocketed
        // phone is not left listening.
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 3),
      ),
    );

    return completer.future.timeout(
      const Duration(seconds: 25),
      onTimeout: () async {
        await stop();
        return Heard(text: best, confidence: confidence == 0 ? 0.6 : confidence);
      },
    );
  }

  @override
  Future<void> stop() => _engine.stop();
}

/// The sample utterances, for platforms with no engine.
///
/// Not a mock in the testing sense: it is what the product does on a desktop
/// browser, and it is labelled as simulated on screen so nobody mistakes the
/// demo for dictation. Everything downstream — parse, confirm, commit — is
/// the real pipeline either way, which was the point of the seam.
class SampleDictation implements Dictation {
  SampleDictation([Random? random]) : _random = random ?? Random();

  final Random _random;

  static const Map<AppLanguage, List<String>> samples =
      <AppLanguage, List<String>>{
    AppLanguage.hindi: <String>[
      '20 doodh packet aur 5 kilo chawal beche',
      'बीस दूध पैकेट और पांच किलो चावल बेचे',
      '10 kilo tamatar kharab ho gaya',
      '50 doodh packet aaya',
      'bees doodh packet',
      '3 kilo pyaz aur 2 litre tel liya',
    ],
    AppLanguage.marathi: <String>[
      'दहा किलो कांदा विकले',
      'पाच लिटर तेल घेतला',
      'वीस दूध पॅकेट विकले',
      'तीन किलो साखर विकली',
    ],
    AppLanguage.english: <String>[
      'sold 12 eggs and 2 packets of biscuits',
      'restocked 30 kg rice',
      '5 litre cooking oil wasted',
      'sold 8 bread',
    ],
  };

  @override
  Future<bool> available() async => true;

  @override
  Future<Heard> listen({
    required AppLanguage language,
    void Function(String partial)? onPartial,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final pool = samples[language] ?? samples[AppLanguage.hindi]!;
    final text = pool[_random.nextInt(pool.length)];
    onPartial?.call(text);
    return Heard(
      text: text,
      // Varied on purpose: a fixed 1.0 would mean the review path only ever
      // appears on contrived input.
      confidence: 0.62 + _random.nextDouble() * 0.36,
      simulated: true,
    );
  }

  @override
  Future<void> stop() async {}
}

/// Picks the engine once, and remembers which one answered.
class Microphone {
  Microphone({Dictation? device, Dictation? samples})
      : _device = device ?? DeviceDictation(),
        _samples = samples ?? SampleDictation();

  final Dictation _device;
  final Dictation _samples;

  bool? _real;

  /// True when a real engine answered; null until asked.
  bool? get isReal => _real;

  Future<Dictation> resolve() async {
    if (_real != null) return _real! ? _device : _samples;
    _real = await _device.available();
    return _real! ? _device : _samples;
  }
}
