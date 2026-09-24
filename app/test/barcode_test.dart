import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/camera.dart';
import 'package:vendor360/data/demo_data.dart';
import 'package:vendor360/data/models.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/data/repository.dart';
import 'package:vendor360/features/scan/scan_screen.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// Scanning a pack, on the client.
///
/// The interesting case is the counter with no signal. Barcodes travel down
/// with the inventory snapshot, so a scan resolves against the cached shelf
/// exactly as it would against the server — which is the whole reason the
/// code lives on the item rather than behind a lookup service.
void main() {
  VendorRepository offline() => VendorRepository(
        api: ApiClient(
          client: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
        ),
        queue: OfflineQueue.inMemory(),
      );

  VendorRepository serving(Object? body, {int status = 200}) =>
      VendorRepository(
        api: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(body),
              status,
              headers: <String, String>{
                'content-type': 'application/json; charset=utf-8',
              },
            ),
          ),
        ),
        queue: OfflineQueue.inMemory(),
      );

  group('normalising what the scanner hands over', () {
    test('punctuation and stray whitespace are not part of the code', () {
      expect(normaliseBarcode('890-1234 567894\n'), '8901234567894');
    });

    test('nothing to read is null, not an empty code', () {
      // An empty string would otherwise match every unbarcoded row at once.
      expect(normaliseBarcode(''), isNull);
      expect(normaliseBarcode('   '), isNull);
      expect(normaliseBarcode(null), isNull);
    });
  });

  group('offline at the counter', () {
    test('a code on the cached shelf still finds its row', () async {
      final hit = await offline().scanBarcode(DemoData.barcodes['Milk']!);

      expect(hit, isNotNull);
      expect(hit!.skuName, 'Milk');
      expect(hit.onTheShelf, isTrue);
      expect(hit.item!.quantity.unit, 'pkt');
    });

    test('a code nobody knows is null, not an error', () async {
      // The catalogue lives on the server; offline there is no second place
      // to look, and the screen has to say so rather than spin.
      expect(await offline().scanBarcode('8999999999990'), isNull);
    });

    test('a scanner that read nothing does not match the loose goods',
        () async {
      expect(await offline().scanBarcode('----'), isNull);
    });
  });

  group('against the server', () {
    test('a pack the shop does not stock comes back named but shelfless',
        () async {
      final repo = serving(<String, dynamic>{
        'barcode': '8901719101014',
        'sku_name': 'Parle-G 800g',
        'category': 'snacks',
        'unit': 'pkt',
        'item': null,
      });

      final hit = await repo.scanBarcode('8901719101014');

      expect(hit!.skuName, 'Parle-G 800g');
      // Enough to open the add-item form; not enough to log a sale against.
      expect(hit.onTheShelf, isFalse);
      expect(hit.category, 'snacks');
    });

    test('a stocked pack arrives with its shelf row', () async {
      final repo = serving(<String, dynamic>{
        'barcode': '8909000000008',
        'sku_name': 'Milk',
        'category': 'dairy',
        'unit': 'pkt',
        'item': <String, dynamic>{
          'id': 'srv-1',
          'sku_name': 'Milk',
          'category': 'dairy',
          'barcode': '8909000000008',
          'current_qty': 40.0,
          'unit': 'pkt',
          'reorder_point': 20.0,
          'unit_cost': 24.0,
          'unit_price': 28.0,
          'sync_status': 'synced',
        },
      });

      final hit = await repo.scanBarcode('8909000000008');

      expect(hit!.item!.id, 'srv-1');
      expect(hit.item!.barcode, '8909000000008');
      expect(hit.item!.isScannable, isTrue);
    });
  });

  group('what the device can do', () {
    test('a phone scans; a laptop does not pretend to', () {
      const phone = CameraSupport(platform: TargetPlatform.android, web: false);
      const laptop =
          CameraSupport(platform: TargetPlatform.windows, web: false);
      const browser =
          CameraSupport(platform: TargetPlatform.android, web: true);

      expect(phone.canScan, isTrue);
      expect(laptop.canScan, isFalse);
      expect(browser.canScan, isFalse, reason: 'a phone browser is not the app');

      // Choosing a file works everywhere, which is what keeps the receipt
      // flow real on a laptop rather than reducing it to samples.
      expect(laptop.canPickImage, isTrue);
      expect(laptop.canTakePhoto, isFalse);
    });
  });

  testWidgets('with no camera the scan screen explains instead of going black',
      (tester) async {
    final container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(
          ApiClient(
            client: MockClient((_) async => throw const SocketException('x')),
          ),
        ),
        cameraSupportProvider.overrideWithValue(
          const CameraSupport(platform: TargetPlatform.windows, web: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: const MotionScope(child: ScanScreen()),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('यहाँ कैमरा नहीं है — नंबर लिखें'), findsOneWidget);

    // And the way through is offered, not just the bad news.
    expect(find.byType(TextField), findsOneWidget);

    // Real codes are printed on the page, so the flow can be demonstrated by
    // pointing a phone at the screen.
    expect(find.byType(PrintedBarcode), findsWidgets);
  });

  testWidgets('the printed codes are wide enough to actually scan',
      (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(
          ApiClient(
            client: MockClient((_) async => throw const SocketException('x')),
          ),
        ),
        cameraSupportProvider.overrideWithValue(
          const CameraSupport(platform: TargetPlatform.windows, web: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: const MotionScope(child: ScanScreen()),
        ),
      ),
    );
    await tester.pump();

    // An EAN-13 is 95 modules wide. Below roughly three logical pixels a
    // module it still looks like a barcode and a phone camera cannot read
    // it — which would quietly defeat the only reason it is on the page.
    final width = tester.getSize(find.byType(PrintedBarcode).first).width;
    expect(width / 95, greaterThan(3.0), reason: 'only $width wide');
  });

  testWidgets('typing a code off the pack finds the row', (tester) async {
    final container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(
          ApiClient(
            client: MockClient((_) async => throw const SocketException('x')),
          ),
        ),
        cameraSupportProvider.overrideWithValue(
          const CameraSupport(platform: TargetPlatform.windows, web: false),
        ),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: const MotionScope(child: ScanScreen()),
        ),
      ),
    );
    await tester.pump();

    await tester.enterText(find.byType(TextField), '8909000000007');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    // A mistyped check digit is a code no pack carries, and the screen says
    // so rather than silently doing nothing.
    expect(find.text('इस नंबर का कोई सामान नहीं'), findsOneWidget);
  });
}
