import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart' show HeatCell, SupplierPin;

import 'api_client.dart';
import 'demo_data.dart';
import 'models.dart';
import 'offline_queue.dart';

/// The app's single door to data.
///
/// Reads go through [withFallback] and degrade to seeded data; writes go
/// through the offline queue and are never silently dropped. Screens see one
/// interface and do not have to know which path a given call took — which is
/// what keeps "offline-first" from leaking into every widget.
class VendorRepository {
  VendorRepository({required this.api, required this.queue});

  final ApiClient api;
  final OfflineQueue queue;

  // ------------------------------------------------------------------ auth
  /// Request an OTP. Returns the dev code while the backend exposes it.
  Future<String?> requestOtp(String phone) async {
    final response = await api.post('/auth/otp/request', body: {'phone': phone});
    return (response as Map)['dev_code'] as String?;
  }

  Future<Vendor> verifyOtp({
    required String phone,
    required String code,
    String language = 'hi',
  }) async {
    final response = await api.post('/auth/otp/verify', body: {
      'phone': phone,
      'code': code,
      'language_pref': language,
    }) as Map<String, dynamic>;

    final token = response['access_token'] as String;
    api.setToken(token);
    await queue.setToken(token);

    return vendorFromJson(Map<String, dynamic>.from(response['vendor'] as Map));
  }

  Future<void> signOut() async {
    api.setToken(null);
    await queue.setToken(null);
    await queue.clear();
  }

  /// Restore a session from disk so a relaunch does not ask for an OTP again.
  Future<bool> restoreSession() async {
    final token = queue.token;
    if (token == null) return false;
    api.setToken(token);
    try {
      await api.get('/auth/me');
      return true;
    } catch (_) {
      // The token is stale or the server rejected it. Clearing it here means
      // the app asks for a fresh OTP rather than looping on 401s.
      api.setToken(null);
      await queue.setToken(null);
      return false;
    }
  }

  // ------------------------------------------------------------- dashboard
  Future<DashboardSnapshot> dashboard() => withFallback(
        () async {
          final json = await api.get('/dashboard') as Map<String, dynamic>;
          await queue.cacheSnapshot('dashboard', json);
          return DashboardSnapshot.fromJson(json);
        },
        () {
          final cached = queue.readSnapshot('dashboard');
          // Prefer the vendor's own last-known figures over the demo world;
          // stale real data beats correct fictional data.
          if (cached is Map) {
            return DashboardSnapshot.fromJson(Map<String, dynamic>.from(cached));
          }
          return DemoData.dashboard;
        },
        label: 'dashboard',
      );

  // ------------------------------------------------------------- inventory
  Future<List<InventoryItem>> inventory({String? category, bool lowOnly = false}) =>
      withFallback(
        () async {
          final json = await api.get('/inventory', query: {
            'category': ?category,
            if (lowOnly) 'low_only': 'true',
          }) as List;
          await queue.cacheSnapshot('inventory', json);
          return <InventoryItem>[
            for (final i in json) itemFromJson(Map<String, dynamic>.from(i as Map)),
          ];
        },
        () {
          final cached = queue.readSnapshot('inventory');
          final items = cached is List
              ? <InventoryItem>[
                  for (final i in cached) itemFromJson(Map<String, dynamic>.from(i as Map)),
                ]
              : DemoData.items;

          return items.where((item) {
            if (category != null && item.category != category) return false;
            if (lowOnly && !item.isLow) return false;
            return true;
          }).toList();
        },
        label: 'inventory',
      );

  /// Record a stock movement.
  ///
  /// Always queued locally first, then flushed. That ordering is what makes
  /// the write survive a connection that drops between the tap and the
  /// response — the alternative is a sale that exists only in the UI.
  Future<void> recordMovement({
    required String itemId,
    required double qty,
    required String movement,
    String source = 'manual',
    double confidence = 1.0,
    String? rawText,
  }) async {
    await queue.enqueueMovement(
      itemId: itemId,
      qty: qty,
      movement: movement,
      source: source,
      confidence: confidence,
      rawText: rawText,
    );
    await flushQueue();
  }

  // ------------------------------------------------------------------ sync
  /// Push every queued event and reconcile against the server's state.
  ///
  /// Returns null when there was nothing to send or the push failed; the queue
  /// is left intact in both cases so nothing is lost.
  Future<SyncOutcome?> flushQueue() async {
    final pending = queue.pending;
    if (pending.isEmpty) return null;

    try {
      final json = await api.post('/sync/batch', body: {
        'device_id': queue.deviceId,
        'events': pending.map((e) => e.toWire()).toList(),
      }) as Map<String, dynamic>;

      final outcome = SyncOutcome.fromJson(json);
      await queue.settle(outcome.statusByEventId);
      await queue.cacheSnapshot(
        'inventory',
        (json['items'] as List),
      );
      return outcome;
    } catch (_) {
      // Still offline. The queue is untouched and will be retried on the next
      // action or the next foreground.
      return null;
    }
  }

  int get queueDepth => queue.depth;

  Future<List<Map<String, dynamic>>> conflicts() => withFallback(
        () async {
          final json = await api.get('/sync/conflicts') as List;
          return <Map<String, dynamic>>[
            for (final c in json) Map<String, dynamic>.from(c as Map),
          ];
        },
        () => const <Map<String, dynamic>>[],
        label: 'conflicts',
      );

  // ----------------------------------------------------------------- voice
  /// Parse an utterance without committing it.
  ///
  /// The confirm step is mandatory, so this never commits — applying happens
  /// through [confirmVoiceLines] after the vendor has seen the parse.
  Future<VoiceParseResult> parseUtterance({
    required String transcript,
    required String language,
    double asrConfidence = 1.0,
  }) async {
    final json = await api.post('/inventory/voice-entry', body: {
      'transcript': transcript,
      'language': language,
      'asr_confidence': asrConfidence,
      'commit': false,
    }) as Map<String, dynamic>;
    return VoiceParseResult.fromJson(json);
  }

  Future<void> confirmVoiceLines(List<ParsedLine> lines) async {
    for (final line in lines) {
      if (line.itemId != null) {
        await queue.enqueueMovement(
          itemId: line.itemId!,
          qty: line.qty,
          movement: line.movement,
          source: 'voice',
          confidence: line.confidence,
          rawText: line.matchedText,
        );
      } else {
        // A SKU the catalogue has never seen. Creating it server-side keeps the
        // id authoritative; a vendor naming a new product is adding it, not
        // making a mistake.
        final created = await api.post('/inventory', body: {
          'sku_name': line.skuName,
          'category': line.category ?? 'staples',
          'unit': line.unit ?? 'pc',
        }) as Map<String, dynamic>;

        await queue.enqueueMovement(
          itemId: created['id'] as String,
          qty: line.qty,
          movement: line.movement,
          source: 'voice',
          confidence: line.confidence,
          rawText: line.matchedText,
        );
      }
    }
    await flushQueue();
  }

  // ------------------------------------------------------------------- ocr
  Future<ReceiptResult> parseReceipt({
    required String rawText,
    double ocrConfidence = 1.0,
  }) async {
    final json = await api.post('/inventory/ocr-entry', body: {
      'raw_text': rawText,
      'ocr_confidence': ocrConfidence,
      'commit': false,
    }) as Map<String, dynamic>;
    return ReceiptResult.fromJson(json);
  }

  Future<void> commitReceipt({
    required String rawText,
    double ocrConfidence = 1.0,
  }) async {
    await api.post('/inventory/ocr-entry', body: {
      'raw_text': rawText,
      'ocr_confidence': ocrConfidence,
      'commit': true,
    });
  }

  // -------------------------------------------------------------- forecast
  Future<List<Forecast>> forecasts({int days = 7}) => withFallback(
        () async {
          final json = await api.get('/forecast', query: {'days': days}) as List;
          return <Forecast>[
            for (final f in json) forecastFromJson(Map<String, dynamic>.from(f as Map)),
          ];
        },
        () => DemoData.forecasts,
        label: 'forecasts',
      );

  Future<Forecast> forecastFor(String itemId, {int days = 7}) => withFallback(
        () async {
          final json =
              await api.get('/forecast/$itemId', query: {'days': days}) as Map<String, dynamic>;
          return forecastFromJson(json);
        },
        () => DemoData.forecasts.firstWhere(
          (f) => f.itemId == itemId,
          orElse: () => DemoData.forecasts.first,
        ),
        label: 'forecast/$itemId',
      );

  Future<Map<String, dynamic>> forecastAccuracy({int lookback = 14}) => withFallback(
        () async => Map<String, dynamic>.from(
          await api.get('/forecast-accuracy', query: {'lookback': lookback}) as Map,
        ),
        () => <String, dynamic>{
          'overall_mape': 14.6,
          'items_scored': 0,
          'lookback_days': lookback,
          'items': const <dynamic>[],
        },
        label: 'accuracy',
      );

  // ---------------------------------------------------------- health score
  Future<HealthScore> healthScore() => withFallback(
        () async {
          final json = await api.get('/health-score') as Map<String, dynamic>;
          await queue.cacheSnapshot('health', json);
          return healthScoreFromJson(json);
        },
        () {
          final cached = queue.readSnapshot('health');
          if (cached is Map) {
            return healthScoreFromJson(Map<String, dynamic>.from(cached));
          }
          return DemoData.healthScore;
        },
        label: 'health-score',
      );

  Future<List<ScoreConsent>> consents() => withFallback(
        () async {
          final json = await api.get('/health-score/consents') as List;
          return <ScoreConsent>[
            for (final c in json)
              ScoreConsent(
                lenderId: c['lender_id'] as String,
                lenderName: c['name'] as String,
                lenderKind: c['kind'] as String? ?? 'nbfc',
                granted: c['granted'] as bool? ?? false,
                grantedAt: c['granted_at'] == null
                    ? null
                    : DateTime.tryParse(c['granted_at'].toString()),
              ),
          ];
        },
        () => const <ScoreConsent>[
          ScoreConsent(
            lenderId: 'l1',
            lenderName: 'Bharat Micro Finance',
            lenderKind: 'mfi',
            granted: false,
          ),
          ScoreConsent(
            lenderId: 'l2',
            lenderName: 'Sahyadri NBFC',
            lenderKind: 'nbfc',
            granted: false,
          ),
          ScoreConsent(
            lenderId: 'l3',
            lenderName: 'Pune Urban Co-op Bank',
            lenderKind: 'bank',
            granted: false,
          ),
        ],
        label: 'consents',
      );

  Future<void> setConsent(String lenderId, bool granted) => api.post(
        '/health-score/consents/$lenderId',
        query: {'granted': granted},
      );

  // ---------------------------------------------------------------- expiry
  Future<List<ExpiryEntry>> expiring({int withinDays = 7}) => withFallback(
        () async {
          final json =
              await api.get('/expiry', query: {'within_days': withinDays}) as List;
          return <ExpiryEntry>[
            for (final e in json) ExpiryEntry.fromJson(Map<String, dynamic>.from(e as Map)),
          ];
        },
        () => DemoData.expiring.where((e) => e.daysLeft <= withinDays).toList(),
        label: 'expiry',
      );

  // ----------------------------------------------------------------- pools
  Future<List<BargainPool>> pools() => withFallback(
        () async {
          final json = await api.get('/vendor-network/pool-offers') as List;
          return <BargainPool>[
            for (final p in json) BargainPool.fromJson(Map<String, dynamic>.from(p as Map)),
          ];
        },
        () => DemoData.pools,
        label: 'pools',
      );

  Future<void> joinPool(String poolId, double qty) =>
      api.post('/vendor-network/pool-offers/$poolId/join', body: {'qty': qty});

  Future<void> leavePool(String poolId) =>
      api.post('/vendor-network/pool-offers/$poolId/leave');

  // --------------------------------------------------------------- heatmap
  Future<({List<HeatCell> cells, List<SupplierPin> suppliers, int suppressed})>
      heatmap({String? category, int days = 30}) => withFallback(
            () async {
              final json = await api.get('/heatmap', query: {
                'category': ?category,
                'days': days,
              }) as Map<String, dynamic>;

              return (
                cells: <HeatCell>[
                  for (final c in (json['cells'] as List))
                    HeatCell(
                      lat: (c['lat'] as num).toDouble(),
                      lon: (c['lon'] as num).toDouble(),
                      intensity: (c['intensity'] as num).toDouble(),
                      demandQty: (c['demand_qty'] as num).toDouble(),
                      vendorCount: (c['vendor_count'] as num).toInt(),
                      topSku: c['top_sku'] as String?,
                      shortageCount: (c['shortage_count'] as num?)?.toInt() ?? 0,
                    ),
                ],
                suppliers: <SupplierPin>[
                  for (final s in (json['suppliers'] as List))
                    SupplierPin(
                      name: s['name'] as String,
                      lat: (s['lat'] as num).toDouble(),
                      lon: (s['lon'] as num).toDouble(),
                      kind: s['kind'] as String? ?? 'distributor',
                      leadDays: (s['lead_days'] as num?)?.toInt() ?? 2,
                    ),
                ],
                suppressed: (json['suppressed_cells'] as num?)?.toInt() ?? 0,
              );
            },
            () => (
              cells: DemoData.heatCells,
              suppliers: DemoData.suppliers,
              suppressed: 5,
            ),
            label: 'heatmap',
          );

  // --------------------------------------------------------------- signals
  Future<Map<String, dynamic>> signals({int days = 14}) => withFallback(
        () async => Map<String, dynamic>.from(
          await api.get('/signals', query: {'days': days}) as Map,
        ),
        () => <String, dynamic>{'weather': const [], 'festivals': const []},
        label: 'signals',
      );
}
