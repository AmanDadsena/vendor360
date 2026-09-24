import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/data/speech.dart';
import 'package:vendor360/features/voice/voice_screen.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// Dictation, and the honest fallback behind it.
///
/// The product runs where there is no speech engine — a desktop browser, a
/// device that refuses the permission — and it has to keep working there
/// without pretending. These tests hold both halves of that promise: the
/// right source is chosen, and the screen says which one it got.
void main() {
  group('choosing a source', () {
    test('no engine means the samples, and the screen can tell', () async {
      final microphone = Microphone(device: _Silent(), samples: _Fixed('x'));

      expect(microphone.isReal, isNull, reason: 'nothing asked yet');
      final chosen = await microphone.resolve();

      expect(chosen, isA<_Fixed>());
      expect(microphone.isReal, isFalse);
    });

    test('an engine that answers is used', () async {
      final device = _Fixed('sold 8 bread');
      final microphone = Microphone(device: device, samples: _Fixed('sample'));

      expect(await microphone.resolve(), same(device));
      expect(microphone.isReal, isTrue);
    });

    test('the platform is asked once, not on every tap', () async {
      final device = _Silent();
      final microphone = Microphone(device: device, samples: _Fixed('x'));

      await microphone.resolve();
      await microphone.resolve();
      await microphone.resolve();

      // Initialising a speech engine is slow and, on a phone, can put a
      // permission sheet on screen. Asking three times would do it three
      // times.
      expect(device.asked, 1);
    });
  });

  group('the sample source', () {
    test('speaks the language the app is set to', () async {
      // Seeded, so the assertion is about the pool and not about luck.
      final samples = SampleDictation(Random(7));

      final marathi = await samples.listen(language: AppLanguage.marathi);
      expect(SampleDictation.samples[AppLanguage.marathi], contains(marathi.text));

      final english = await samples.listen(language: AppLanguage.english);
      expect(SampleDictation.samples[AppLanguage.english], contains(english.text));
    });

    test('admits it is a sample, and varies its confidence', () async {
      final heard = await SampleDictation(Random(3))
          .listen(language: AppLanguage.hindi);

      expect(heard.simulated, isTrue);
      // A flat 1.0 would mean the review path only ever appears on input
      // contrived to fail, which is the bug this range exists to prevent.
      expect(heard.confidence, greaterThan(0.6));
      expect(heard.confidence, lessThan(1.0));
    });

    test('fills the transcript as words arrive', () async {
      final partials = <String>[];
      await SampleDictation(Random(1)).listen(
        language: AppLanguage.hindi,
        onPartial: partials.add,
      );

      expect(partials, isNotEmpty);
    });
  });

  testWidgets('with no engine the screen says so and still parses', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(
          ApiClient(
            client: MockClient((_) async => throw const SocketException('x')),
          ),
        ),
        microphoneProvider.overrideWithValue(
          Microphone(device: _Silent(), samples: _Fixed('sold 8 bread')),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: const MotionScope(child: VoiceScreen()),
        ),
      ),
    );

    // Nothing is claimed before the microphone has been asked.
    expect(find.text(_noMic), findsNothing);

    await tester.tap(find.byType(VoiceOrb));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // In Hindi, because that is the default a shopkeeper opens the app in.
    expect(find.text(_noMic), findsOneWidget);
    // The words still reach the transcript, so the pipeline behind the
    // microphone is the same one either way.
    expect(find.text('sold 8 bread'), findsOneWidget);
  });
}

/// The unavailable notice, in the app's default language.
const _noMic = 'यहाँ माइक नहीं है — नमूना चल रहा है';

/// A platform with no speech engine, counting how often it is asked.
class _Silent implements Dictation {
  int asked = 0;

  @override
  Future<bool> available() async {
    asked++;
    return false;
  }

  @override
  Future<Heard> listen({
    required AppLanguage language,
    void Function(String partial)? onPartial,
  }) async =>
      const Heard(text: '', confidence: 0);

  @override
  Future<void> stop() async {}
}

/// A source that always hears the same thing.
class _Fixed implements Dictation {
  _Fixed(this.text);

  final String text;

  @override
  Future<bool> available() async => true;

  @override
  Future<Heard> listen({
    required AppLanguage language,
    void Function(String partial)? onPartial,
  }) async {
    onPartial?.call(text);
    return Heard(text: text, confidence: 0.9);
  }

  @override
  Future<void> stop() async {}
}
