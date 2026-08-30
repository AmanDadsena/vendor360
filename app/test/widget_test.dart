import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/core/strings.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// App-level wiring tests.
///
/// These cover the pieces that are easy to break and hard to notice: the
/// offline queue's durability contract, the language switch that governs both
/// ASR and on-screen text, and the theme the whole design system hangs off.
void main() {
  setUp(() {
    // In-memory backing store, so each test starts with an empty queue.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('OfflineQueue', () {
    test('mints a stable device id', () async {
      final queue = await OfflineQueue.open();
      final first = queue.deviceId;
      expect(first, startsWith('dev-'));
      expect(queue.deviceId, first, reason: 'device id must not change per read');
    });

    test('assigns monotonic sequence numbers', () async {
      final queue = await OfflineQueue.open();
      final a = await queue.enqueueMovement(itemId: 'i1', qty: 2, movement: 'sale');
      final b = await queue.enqueueMovement(itemId: 'i1', qty: 3, movement: 'sale');
      final c = await queue.enqueueMovement(itemId: 'i2', qty: 1, movement: 'restock');

      expect(a.localSeq < b.localSeq, isTrue);
      expect(b.localSeq < c.localSeq, isTrue);
      expect(queue.depth, 3);
    });

    test('event ids are unique', () async {
      final queue = await OfflineQueue.open();
      for (var i = 0; i < 25; i++) {
        await queue.enqueueMovement(itemId: 'i', qty: 1, movement: 'sale');
      }
      final ids = queue.pending.map((e) => e.clientEventId).toSet();
      expect(ids.length, 25);
    });

    test('sends deltas, never absolute quantities', () async {
      final queue = await OfflineQueue.open();
      final event = await queue.enqueueMovement(
        itemId: 'i1', qty: 5, movement: 'sale',
      );
      // Absolute values cannot merge across two offline devices; deltas can.
      expect(event.payload['qty'], 5);
      expect(event.payload['movement'], 'sale');
      expect(event.payload.containsKey('current_qty'), isFalse);
    });

    test('settling removes applied and duplicate events', () async {
      final queue = await OfflineQueue.open();
      final a = await queue.enqueueMovement(itemId: 'i', qty: 1, movement: 'sale');
      final b = await queue.enqueueMovement(itemId: 'i', qty: 2, movement: 'sale');
      final c = await queue.enqueueMovement(itemId: 'i', qty: 3, movement: 'sale');

      await queue.settle(<String, String>{
        a.clientEventId: 'applied',
        // A duplicate means the server already has it — retrying forever would
        // leave a permanent badge on the vendor's screen for safe work.
        b.clientEventId: 'duplicate',
        c.clientEventId: 'rejected: item not found',
      });

      expect(queue.depth, 1);
      expect(queue.pending.single.clientEventId, c.clientEventId);
      expect(queue.pending.single.attempts, 1);
    });

    test('parks an event that keeps being rejected', () async {
      final queue = await OfflineQueue.open();
      final event = await queue.enqueueMovement(
        itemId: 'gone', qty: 1, movement: 'sale',
      );

      // A poison entry must not block everything queued behind it.
      for (var i = 0; i < OfflineQueue.maxAttempts; i++) {
        await queue.settle(<String, String>{event.clientEventId: 'rejected'});
      }
      expect(queue.depth, 0);
    });

    test('in-memory fallback works and reports itself as not durable', () {
      // Startup must never block or fail on storage. When platform storage
      // cannot be opened the app runs on this instead of showing a blank
      // screen — but it says so, rather than implying work is safely stored.
      final queue = OfflineQueue.inMemory();

      expect(queue.isDurable, isFalse);
      expect(queue.deviceId, startsWith('dev-'));
      expect(queue.depth, 0);
    });

    test('prefs-backed queue reports itself as durable', () async {
      final queue = await OfflineQueue.open();
      expect(queue.isDurable, isTrue);
    });

    test('in-memory queue supports the full enqueue/settle cycle', () async {
      final queue = OfflineQueue.inMemory();
      final event = await queue.enqueueMovement(
        itemId: 'i', qty: 3, movement: 'sale',
      );

      expect(queue.depth, 1);
      await queue.settle(<String, String>{event.clientEventId: 'applied'});
      expect(queue.depth, 0);
    });

    test('survives being reopened', () async {
      final first = await OfflineQueue.open();
      await first.enqueueMovement(itemId: 'i', qty: 4, movement: 'sale');

      // TC-S04: the app is killed and relaunched with entries still queued.
      final reopened = await OfflineQueue.open();
      expect(reopened.depth, 1);
      expect(reopened.pending.single.payload['qty'], 4);
    });
  });

  group('Strings', () {
    test('cover all three languages', () {
      for (final language in AppLanguage.values) {
        final strings = Strings(language);
        expect(strings.home, isNotEmpty);
        expect(strings.speak, isNotEmpty);
        expect(strings.healthScore, isNotEmpty);
      }
    });

    test('Hindi and Marathi are not English', () {
      // Guards against a translation being silently left as the English
      // string, which is invisible to a reviewer who does not read Devanagari.
      final english = Strings(AppLanguage.english);
      final hindi = Strings(AppLanguage.hindi);
      final marathi = Strings(AppLanguage.marathi);

      expect(hindi.welcome, isNot(english.welcome));
      expect(marathi.welcome, isNot(english.welcome));
      expect(hindi.tapToSpeak, isNot(english.tapToSpeak));
    });
  });

  group('Theme', () {
    testWidgets('builds in both brightnesses and exposes tokens', (tester) async {
      for (final brightness in Brightness.values) {
        late V360ThemeData tokens;
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              // Keyed by brightness so the second pump replaces the element
              // rather than reusing it — without this the Builder never runs
              // again and the test silently re-asserts the first theme.
              key: ValueKey<Brightness>(brightness),
              theme: buildV360Theme(brightness),
              home: Builder(builder: (context) {
                tokens = context.v360;
                return const SizedBox();
              }),
            ),
          ),
        );
        expect(tokens.brightness, brightness);
        expect(tokens.colors.accent, isNotNull);
      }
    });
  });

  group('Language provider', () {
    testWidgets('switching mid-session changes the strings', (tester) async {
      final container = ProviderContainer(
        overrides: [
          offlineQueueProvider.overrideWithValue(await OfflineQueue.open()),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(languageProvider), AppLanguage.hindi);
      expect(container.read(stringsProvider).home, 'होम');

      // TC-V05: the switch must take effect immediately, not after a round trip.
      container.read(languageProvider.notifier).value = AppLanguage.marathi;

      expect(container.read(languageProvider), AppLanguage.marathi);
      expect(
        container.read(languageProvider).speechLocale,
        'mr-IN',
        reason: 'ASR locale must follow the on-screen language',
      );
    });
  });
}
