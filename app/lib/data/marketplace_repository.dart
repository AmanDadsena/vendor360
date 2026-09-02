import 'dart:math' as math;

// Unfiltered: `AppLanguage.code` lives on an extension, and a `show`
// clause filters extensions out along with everything else it omits.
import 'package:vendor360_core/vendor360_core.dart';

import 'api_client.dart';
import 'marketplace_models.dart';
import 'offline_queue.dart';

/// Data access for the two-sided marketplace.
///
/// Separate from `VendorRepository` because it serves two different
/// principals: the vendor-facing half is scoped by the shop's token, the
/// `/dist` half by the wholesaler's, and mixing them in one class would make
/// it easy to call a distributor method from a vendor screen and get a 403 at
/// runtime instead of a compile error.
///
/// Reads follow the house rule and degrade rather than block. Writes never
/// do: an order the vendor was told was placed, that does not exist, is the
/// one failure this product cannot afford.
class MarketplaceRepository {
  MarketplaceRepository({required this.api, required this.queue});

  final ApiClient api;
  final OfflineQueue queue;

  // ==================================================== vendor: discovery
  Future<List<SupplierCard>> distributors({String? category}) => withFallback(
        () async {
          final json = await api.get('/distributors', query: {
            if (category != null) 'category': category,
          }) as List;
          return <SupplierCard>[
            for (final s in json)
              SupplierCard.fromJson(Map<String, dynamic>.from(s as Map)),
          ];
        },
        () => const <SupplierCard>[],
        label: 'distributors',
      );

  Future<List<Connection>> connections() => withFallback(
        () async {
          final json = await api.get('/connections') as List;
          return <Connection>[
            for (final c in json)
              Connection.fromJson(Map<String, dynamic>.from(c as Map)),
          ];
        },
        () => const <Connection>[],
        label: 'connections',
      );

  Future<Connection> connect(
    String supplierId, {
    bool sharesDemand = true,
    int creditTermsDays = 0,
  }) =>
      withoutFallback(() async {
        final json = await api.post(
          '/distributors/$supplierId/connect',
          body: {
            'shares_demand': sharesDemand,
            'credit_terms_days': creditTermsDays,
          },
        ) as Map<String, dynamic>;
        return Connection.fromJson(json);
      });

  Future<void> disconnect(String supplierId) =>
      withoutFallback(() => api.delete('/distributors/$supplierId/connect'));

  // ===================================================== vendor: sourcing
  Future<Sourcing> sourcing(String itemId) => withoutFallback(() async {
        final json = await api.get('/sourcing/$itemId') as Map<String, dynamic>;
        return Sourcing.fromJson(json);
      });

  // ======================================================= vendor: orders
  Future<List<PurchaseOrder>> orders({String? status, bool openOnly = false}) =>
      withFallback(
        () async {
          final json = await api.get('/orders', query: {
            if (status != null) 'status': status,
            if (openOnly) 'open_only': true,
          }) as List;
          return <PurchaseOrder>[
            for (final o in json)
              PurchaseOrder.fromJson(Map<String, dynamic>.from(o as Map)),
          ];
        },
        () => const <PurchaseOrder>[],
        label: 'orders',
      );

  Future<PurchaseOrder> order(String id) => withoutFallback(() async {
        final json = await api.get('/orders/$id') as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  /// Place an order.
  ///
  /// The `client_event_id` is minted here rather than server-side, which is
  /// what makes a retry safe: the app cannot tell whether a request that timed
  /// out actually landed, so it sends the same id again and the server
  /// recognises it. Without this, a shopkeeper on a bad connection who taps
  /// twice gets charged twice.
  Future<PurchaseOrder> placeOrder({
    required String supplierId,
    required List<CartLine> lines,
    String? note,
    String? poolId,
    bool placeImmediately = true,
  }) =>
      withoutFallback(() async {
        final json = await api.post('/orders', body: {
          'supplier_id': supplierId,
          'lines': [for (final l in lines) l.toJson()],
          if (note != null) 'note': note,
          if (poolId != null) 'pool_id': poolId,
          'client_event_id': _eventId(),
          'place_immediately': placeImmediately,
        }) as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  Future<PurchaseOrder> cancelOrder(String id, {String? reason}) =>
      withoutFallback(() async {
        final json = await api.post(
          '/orders/$id/cancel',
          body: {if (reason != null) 'reason': reason},
        ) as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  /// Confirm what actually arrived, which puts it on the shelf.
  ///
  /// `received` maps line id to the case count counted on the doorstep. An
  /// empty map means "everything as confirmed", which is the common case and
  /// one the vendor should not have to type out.
  Future<PurchaseOrder> receiveOrder(
    String id, {
    Map<String, double> received = const {},
    String? note,
  }) =>
      withoutFallback(() async {
        final json = await api.post('/orders/$id/receive', body: {
          if (received.isNotEmpty)
            'lines': [
              for (final e in received.entries)
                {'line_id': e.key, 'packs': e.value},
            ],
          if (note != null) 'note': note,
        }) as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  Future<Ledger> ledger() => withFallback(
        () async => Ledger.fromJson(await api.get('/ledger') as Map<String, dynamic>),
        () => Ledger.empty,
        label: 'ledger',
      );

  // =================================================== vendor: onboarding
  Future<List<MasterSku>> masterCatalog({
    List<String> categories = const [],
    String? category,
    int? limit,
  }) =>
      withFallback(
        () async {
          final json = await api.get('/onboarding/master-catalog', query: {
            if (categories.isNotEmpty) 'categories': categories.join(','),
            if (category != null) 'category': category,
            if (limit != null) 'limit': limit,
          }) as List;
          return <MasterSku>[
            for (final s in json)
              MasterSku.fromJson(Map<String, dynamic>.from(s as Map)),
          ];
        },
        () => const <MasterSku>[],
        label: 'master-catalog',
      );

  Future<int> quickAdd(List<String> keys) => withoutFallback(() async {
        final json = await api.post(
          '/onboarding/quick-add',
          body: {'keys': keys},
        ) as Map<String, dynamic>;
        return (json['created'] as num?)?.toInt() ?? 0;
      });

  // ============================================== distributor: the console
  Future<DistributorSummary> summary() => withFallback(
        () async => DistributorSummary.fromJson(
          await api.get('/dist/summary') as Map<String, dynamic>,
        ),
        () => DistributorSummary.empty,
        label: 'dist-summary',
      );

  Future<List<PurchaseOrder>> inbox({String? status, bool openOnly = false}) =>
      withFallback(
        () async {
          final json = await api.get('/dist/orders', query: {
            if (status != null) 'status': status,
            if (openOnly) 'open_only': true,
          }) as List;
          return <PurchaseOrder>[
            for (final o in json)
              PurchaseOrder.fromJson(Map<String, dynamic>.from(o as Map)),
          ];
        },
        () => const <PurchaseOrder>[],
        label: 'dist-orders',
      );

  Future<PurchaseOrder> inboxOrder(String id) => withoutFallback(() async {
        final json = await api.get('/dist/orders/$id') as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  /// Move an order forward. `amended` carries per-line case counts when the
  /// wholesaler can only part-fill.
  Future<PurchaseOrder> advanceOrder(
    String id,
    String action, {
    Map<String, double> amended = const {},
    String? note,
  }) =>
      withoutFallback(() async {
        final json = await api.post('/dist/orders/$id/$action', body: {
          if (amended.isNotEmpty)
            'lines': [
              for (final e in amended.entries)
                {'line_id': e.key, 'packs': e.value},
            ],
          if (note != null) 'note': note,
        }) as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  Future<PurchaseOrder> rejectOrder(String id, {String? reason}) =>
      withoutFallback(() async {
        final json = await api.post(
          '/dist/orders/$id/reject',
          body: {if (reason != null) 'reason': reason},
        ) as Map<String, dynamic>;
        return PurchaseOrder.fromJson(json);
      });

  // ================================================= distributor: catalog
  Future<List<CatalogEntry>> catalog({bool includeInactive = false}) =>
      withFallback(
        () async {
          final json = await api.get('/dist/catalog', query: {
            if (includeInactive) 'include_inactive': true,
          }) as List;
          return <CatalogEntry>[
            for (final e in json)
              CatalogEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          ];
        },
        () => const <CatalogEntry>[],
        label: 'dist-catalog',
      );

  Future<CatalogEntry> addCatalogEntry({
    required String skuName,
    required String category,
    required String unit,
    required double packSize,
    required double packPrice,
    int moqPacks = 1,
  }) =>
      withoutFallback(() async {
        final json = await api.post('/dist/catalog', body: {
          'sku_name': skuName,
          'category': category,
          'unit': unit,
          'pack_size': packSize,
          'pack_price': packPrice,
          'moq_packs': moqPacks,
        }) as Map<String, dynamic>;
        return CatalogEntry.fromJson(json);
      });

  Future<CatalogEntry> updateCatalogEntry(
    String id, {
    double? packPrice,
    double? packSize,
    int? moqPacks,
    double? availablePacks,
    bool? active,
  }) =>
      withoutFallback(() async {
        final json = await api.patch('/dist/catalog/$id', body: {
          if (packPrice != null) 'pack_price': packPrice,
          if (packSize != null) 'pack_size': packSize,
          if (moqPacks != null) 'moq_packs': moqPacks,
          if (availablePacks != null) 'available_packs': availablePacks,
          if (active != null) 'active': active,
        }) as Map<String, dynamic>;
        return CatalogEntry.fromJson(json);
      });

  Future<void> withdrawCatalogEntry(String id) =>
      withoutFallback(() => api.delete('/dist/catalog/$id'));

  /// Preview a pasted price list, then commit it.
  ///
  /// Two calls with the same text rather than one: the distributor sees every
  /// row and its problems before anything is written, because a half-applied
  /// price list is worse than a rejected one.
  Future<PriceListPreview> importPriceList(String csv, {bool commit = false}) =>
      withoutFallback(() async {
        final json = await api.post('/dist/catalog/import', body: {
          'csv_text': csv,
          'commit': commit,
        }) as Map<String, dynamic>;
        return PriceListPreview.fromJson(json);
      });

  // ================================================== distributor: demand
  Future<Demand> demand({int horizonDays = 7}) => withFallback(
        () async => Demand.fromJson(
          await api.get('/dist/demand', query: {'horizon_days': horizonDays})
              as Map<String, dynamic>,
        ),
        () => const Demand(
          horizonDays: 7,
          consentingShops: 0,
          totalConnected: 0,
          lines: [],
          atRisk: [],
          deadLines: [],
        ),
        label: 'dist-demand',
      );

  Future<List<BookEntry>> book() => withFallback(
        () async {
          final json = await api.get('/dist/vendors') as List;
          return <BookEntry>[
            for (final v in json)
              BookEntry.fromJson(Map<String, dynamic>.from(v as Map)),
          ];
        },
        () => const <BookEntry>[],
        label: 'dist-vendors',
      );

  Future<Ledger> receivables() => withFallback(
        () async =>
            Ledger.fromJson(await api.get('/dist/ledger') as Map<String, dynamic>),
        () => Ledger.empty,
        label: 'dist-ledger',
      );

  Future<void> recordPayment({
    required String vendorId,
    required double amount,
    String? orderId,
    String? note,
  }) =>
      withoutFallback(() => api.post('/dist/payments', body: {
            'vendor_id': vendorId,
            'amount': amount,
            if (orderId != null) 'order_id': orderId,
            if (note != null) 'note': note,
          }));

  // =================================================== distributor: pools
  Future<List<Map<String, dynamic>>> openPools() => withFallback(
        () async {
          final json = await api.get('/dist/pools') as List;
          return <Map<String, dynamic>>[
            for (final p in json) Map<String, dynamic>.from(p as Map),
          ];
        },
        () => const <Map<String, dynamic>>[],
        label: 'dist-pools',
      );

  Future<void> quotePool(String poolId, double bulkUnitPrice) =>
      withoutFallback(() => api.post(
            '/dist/pools/$poolId/quote',
            body: {'bulk_unit_price': bulkUnitPrice},
          ));

  // ======================================================== shared: auth
  /// Verify an OTP for either principal.
  ///
  /// Returns the resolved role alongside the payload, because the server -- not
  /// the sign-in form -- decides what an existing account is. Someone who taps
  /// "I run a shop" on a number already registered as a wholesaler is signed
  /// into their wholesaler account rather than silently given a second one.
  Future<({Principal principal, Map<String, dynamic> payload})> verify({
    required String phone,
    required String code,
    required AppLanguage language,
    Principal intent = Principal.vendor,
    String? name,
    String? storeName,
    String? businessName,
    String? locality,
  }) =>
      withoutFallback(() async {
        final response = await api.post('/auth/otp/verify', body: {
          'phone': phone,
          'code': code,
          'language_pref': language.code,
          'role': intent == Principal.distributor ? 'distributor' : 'vendor',
          if (name != null) 'name': name,
          if (storeName != null) 'store_name': storeName,
          if (businessName != null) 'business_name': businessName,
          if (locality != null) 'locality': locality,
        }) as Map<String, dynamic>;

        final token = response['access_token'] as String;
        api.setToken(token);
        await queue.setToken(token);

        final resolved = response['role'] == 'distributor'
            ? Principal.distributor
            : Principal.vendor;

        return (
          principal: resolved,
          payload: Map<String, dynamic>.from(
            (resolved == Principal.distributor
                ? response['distributor']
                : response['vendor']) as Map,
          ),
        );
      });

  Future<Distributor> distributorMe() => withoutFallback(() async {
        final json = await api.get('/auth/dist/me') as Map<String, dynamic>;
        return Distributor.fromJson(json);
      });
}

final _random = math.Random();

/// A v4-shaped identifier, minted on the device.
///
/// `Random` rather than `Random.secure` deliberately: this is a collision
/// guard for idempotent retries, not a secret, and `secure` is meaningfully
/// slower on web.
String _eventId() {
  String hex(int length) => List.generate(
        length,
        (_) => _random.nextInt(16).toRadixString(16),
      ).join();

  return '${hex(8)}-${hex(4)}-4${hex(3)}-'
      '${(8 + _random.nextInt(4)).toRadixString(16)}${hex(3)}-${hex(12)}';
}
