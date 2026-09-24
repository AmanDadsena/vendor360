import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/demo_data.dart';
import 'package:vendor360/data/models.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/data/repository.dart';

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
}
