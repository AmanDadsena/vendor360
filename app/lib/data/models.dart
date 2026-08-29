import 'package:vendor360_core/vendor360_core.dart';

/// Wire-format mapping.
///
/// Kept out of `vendor360_core` on purpose: the domain package knows nothing
/// about JSON or about this particular backend, so a change to the API shape
/// lands here and nowhere else.

double _d(Object? v, [double fallback = 0]) =>
    v == null ? fallback : (v as num).toDouble();

int _i(Object? v, [int fallback = 0]) => v == null ? fallback : (v as num).toInt();

DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

Vendor vendorFromJson(Map<String, dynamic> j) => Vendor(
      id: j['id'] as String,
      name: j['name'] as String? ?? 'Vendor',
      storeName: j['store_name'] as String? ?? 'My Store',
      phone: j['phone'] as String? ?? '',
      language: languageFromCode(j['language_pref'] as String? ?? 'hi'),
      locality: j['locality'] as String?,
      city: j['city'] as String? ?? 'Pune',
      lat: j['lat'] == null ? null : _d(j['lat']),
      lon: j['lon'] == null ? null : _d(j['lon']),
      healthScore: j['health_score'] == null ? null : _d(j['health_score']),
      supplierLeadDays: _i(j['supplier_lead_days'], 2),
    );

InventoryItem itemFromJson(Map<String, dynamic> j) => InventoryItem(
      id: j['id'] as String,
      skuName: j['sku_name'] as String,
      category: j['category'] as String? ?? 'staples',
      quantity: Quantity(_d(j['current_qty']), j['unit'] as String? ?? 'pc'),
      reorderPoint: _d(j['reorder_point']),
      unitCost: Money.rupees(_d(j['unit_cost'])),
      unitPrice: Money.rupees(_d(j['unit_price'])),
      shelfLifeDays: j['shelf_life_days'] == null ? null : _i(j['shelf_life_days']),
      expiresOn: _dt(j['expires_on']),
      syncStatus: switch (j['sync_status']) {
        'pending' => SyncStatus.pending,
        'conflict' => SyncStatus.conflict,
        _ => SyncStatus.synced,
      },
      lastUpdated: _dt(j['last_updated']),
    );

HealthScore healthScoreFromJson(Map<String, dynamic> j) => HealthScore(
      score: _d(j['score']),
      band: scoreBandFrom(j['band'] as String? ?? 'provisional'),
      provisional: j['provisional'] as bool? ?? true,
      daysOfHistory: _i(j['days_of_history']),
      explanation: j['explanation'] as String? ?? '',
      components: <ScoreComponent>[
        for (final c in (j['components'] as List? ?? const []))
          ScoreComponent(
            key: c['key'] as String,
            label: c['label'] as String,
            value: _d(c['value']),
            weight: _d(c['weight']),
            contribution: _d(c['contribution']),
            detail: c['detail'] as String? ?? '',
          ),
      ],
    );

Forecast forecastFromJson(Map<String, dynamic> j) => Forecast(
      itemId: j['item_id'] as String,
      skuName: j['sku_name'] as String,
      category: j['category'] as String? ?? 'staples',
      headline: j['headline'] as String? ?? '',
      modelVersion: j['model_version'] as String? ?? '',
      usedFallback: j['used_fallback'] as bool? ?? false,
      historyDays: _i(j['history_days']),
      days: <ForecastDay>[
        for (final d in (j['days'] as List? ?? const []))
          ForecastDay(
            on: DateTime.parse(d['on'] as String),
            predicted: _d(d['predicted']),
            lower: _d(d['lower']),
            upper: _d(d['upper']),
            driver: d['driver'] as String?,
            driverEffect: _d(d['driver_effect']),
          ),
      ],
    );

/// The dashboard's precomputed snapshot.
class DashboardSnapshot {
  const DashboardSnapshot({
    required this.vendor,
    required this.todaySalesValue,
    required this.todayTransactionCount,
    required this.weekSalesValue,
    required this.lowStockCount,
    required this.expiringSoonCount,
    required this.valueAtRisk,
    this.healthScore,
    this.healthBand,
    this.topSignal,
    this.topSignalDetail,
    this.pendingPools = 0,
  });

  final Vendor vendor;
  final Money todaySalesValue;
  final int todayTransactionCount;
  final Money weekSalesValue;
  final int lowStockCount;
  final int expiringSoonCount;
  final Money valueAtRisk;
  final double? healthScore;
  final String? healthBand;
  final String? topSignal;
  final String? topSignalDetail;
  final int pendingPools;

  factory DashboardSnapshot.fromJson(Map<String, dynamic> j) => DashboardSnapshot(
        vendor: vendorFromJson(Map<String, dynamic>.from(j['vendor'] as Map)),
        todaySalesValue: Money.rupees(_d(j['today_sales_value'])),
        todayTransactionCount: _i(j['today_transaction_count']),
        weekSalesValue: Money.rupees(_d(j['week_sales_value'])),
        lowStockCount: _i(j['low_stock_count']),
        expiringSoonCount: _i(j['expiring_soon_count']),
        valueAtRisk: Money.rupees(_d(j['value_at_risk'])),
        healthScore: j['health_score'] == null ? null : _d(j['health_score']),
        healthBand: j['health_band'] as String?,
        topSignal: j['top_signal'] as String?,
        topSignalDetail: j['top_signal_detail'] as String?,
        pendingPools: _i(j['pending_pools']),
      );
}

/// A line parsed from speech, awaiting the vendor's confirmation.
class ParsedLine {
  ParsedLine({
    required this.skuName,
    required this.qty,
    required this.unit,
    required this.movement,
    required this.confidence,
    required this.needsReview,
    required this.matchedText,
    this.category,
    this.itemId,
    this.knownItem = false,
  });

  final String skuName;
  double qty;
  final String? unit;
  final String movement;
  final double confidence;
  final bool needsReview;
  final String matchedText;
  final String? category;
  final String? itemId;
  final bool knownItem;

  factory ParsedLine.fromJson(Map<String, dynamic> j) => ParsedLine(
        skuName: j['sku_name'] as String,
        qty: _d(j['qty']),
        unit: j['unit'] as String?,
        movement: j['movement'] as String? ?? 'sale',
        confidence: _d(j['confidence']),
        needsReview: j['needs_review'] as bool? ?? false,
        matchedText: j['matched_text'] as String? ?? '',
        category: j['category'] as String?,
        itemId: j['item_id'] as String?,
        knownItem: j['known_item'] as bool? ?? false,
      );
}

class VoiceParseResult {
  const VoiceParseResult({
    required this.transcript,
    required this.movement,
    required this.overallConfidence,
    required this.needsReview,
    required this.lines,
    required this.unmatched,
  });

  final String transcript;
  final String movement;
  final double overallConfidence;
  final bool needsReview;
  final List<ParsedLine> lines;
  final List<String> unmatched;

  factory VoiceParseResult.fromJson(Map<String, dynamic> j) => VoiceParseResult(
        transcript: j['transcript'] as String? ?? '',
        movement: j['movement'] as String? ?? 'sale',
        overallConfidence: _d(j['overall_confidence']),
        needsReview: j['needs_review'] as bool? ?? true,
        lines: <ParsedLine>[
          for (final l in (j['lines'] as List? ?? const []))
            ParsedLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
        unmatched: <String>[
          for (final u in (j['unmatched_tokens'] as List? ?? const [])) u.toString(),
        ],
      );
}

/// One line read off a photographed receipt.
class ReceiptLine {
  ReceiptLine({
    required this.raw,
    required this.skuName,
    required this.qty,
    required this.unit,
    required this.rate,
    required this.amount,
    required this.expiresOn,
    required this.confidence,
    required this.needsReview,
    required this.issues,
    this.category,
    this.shelfLifeDays,
  });

  final String raw;
  final String? skuName;
  final double? qty;
  final String? unit;
  final double? rate;
  final double? amount;
  final DateTime? expiresOn;
  final double confidence;
  final bool needsReview;
  final List<String> issues;
  final String? category;
  final int? shelfLifeDays;

  factory ReceiptLine.fromJson(Map<String, dynamic> j) => ReceiptLine(
        raw: j['raw'] as String? ?? '',
        skuName: j['sku_name'] as String?,
        qty: j['qty'] == null ? null : _d(j['qty']),
        unit: j['unit'] as String?,
        rate: j['rate'] == null ? null : _d(j['rate']),
        amount: j['amount'] == null ? null : _d(j['amount']),
        expiresOn: _dt(j['expires_on']),
        confidence: _d(j['confidence']),
        needsReview: j['needs_review'] as bool? ?? false,
        issues: <String>[for (final i in (j['issues'] as List? ?? const [])) i.toString()],
        category: j['category'] as String?,
        shelfLifeDays: j['shelf_life_days'] == null ? null : _i(j['shelf_life_days']),
      );
}

class ReceiptResult {
  const ReceiptResult({
    required this.supplier,
    required this.statedTotal,
    required this.computedTotal,
    required this.totalMatches,
    required this.overallConfidence,
    required this.reviewCount,
    required this.lines,
  });

  final String? supplier;
  final double? statedTotal;
  final double computedTotal;

  /// False when the receipt's own total disagrees with the sum of the lines —
  /// the one failure per-row confidence cannot detect, because a line OCR
  /// never saw has no row to be unconfident about.
  final bool totalMatches;

  final double overallConfidence;
  final int reviewCount;
  final List<ReceiptLine> lines;

  factory ReceiptResult.fromJson(Map<String, dynamic> j) => ReceiptResult(
        supplier: j['supplier'] as String?,
        statedTotal: j['stated_total'] == null ? null : _d(j['stated_total']),
        computedTotal: _d(j['computed_total']),
        totalMatches: j['total_matches'] as bool? ?? true,
        overallConfidence: _d(j['overall_confidence']),
        reviewCount: _i(j['review_count']),
        lines: <ReceiptLine>[
          for (final l in (j['lines'] as List? ?? const []))
            ReceiptLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
      );
}

/// A SKU approaching or past its shelf life.
class ExpiryEntry {
  const ExpiryEntry({
    required this.itemId,
    required this.skuName,
    required this.category,
    required this.quantity,
    required this.expiresOn,
    required this.daysLeft,
    required this.valueAtRisk,
    required this.suggestedDiscountPct,
    required this.urgency,
  });

  final String itemId;
  final String skuName;
  final String category;
  final Quantity quantity;
  final DateTime expiresOn;
  final int daysLeft;
  final Money valueAtRisk;
  final int suggestedDiscountPct;
  final String urgency;

  factory ExpiryEntry.fromJson(Map<String, dynamic> j) => ExpiryEntry(
        itemId: j['item_id'] as String,
        skuName: j['sku_name'] as String,
        category: j['category'] as String? ?? 'staples',
        quantity: Quantity(_d(j['qty']), j['unit'] as String? ?? 'pc'),
        expiresOn: DateTime.parse(j['expires_on'] as String),
        daysLeft: _i(j['days_left']),
        valueAtRisk: Money.rupees(_d(j['value_at_risk'])),
        suggestedDiscountPct: _i(j['suggested_discount_pct']),
        urgency: j['urgency'] as String? ?? 'watch',
      );
}

/// A collective-bargaining pool.
class BargainPool {
  const BargainPool({
    required this.id,
    required this.skuName,
    required this.unit,
    required this.locality,
    required this.targetQty,
    required this.committedQty,
    required this.baseUnitPrice,
    required this.bulkUnitPrice,
    required this.progress,
    required this.savingsPerUnit,
    required this.memberCount,
    required this.joined,
    this.closesAt,
  });

  final String id;
  final String skuName;
  final String unit;
  final String locality;
  final double targetQty;
  final double committedQty;
  final Money baseUnitPrice;
  final Money bulkUnitPrice;
  final double progress;
  final Money savingsPerUnit;
  final int memberCount;
  final bool joined;
  final DateTime? closesAt;

  int get discountPct => baseUnitPrice.paise == 0
      ? 0
      : ((savingsPerUnit.paise / baseUnitPrice.paise) * 100).round();

  factory BargainPool.fromJson(Map<String, dynamic> j) => BargainPool(
        id: j['id'] as String,
        skuName: j['sku_name'] as String,
        unit: j['unit'] as String? ?? 'pc',
        locality: j['locality'] as String? ?? '',
        targetQty: _d(j['target_qty']),
        committedQty: _d(j['committed_qty']),
        baseUnitPrice: Money.rupees(_d(j['base_unit_price'])),
        bulkUnitPrice: Money.rupees(_d(j['bulk_unit_price'])),
        progress: _d(j['progress']),
        savingsPerUnit: Money.rupees(_d(j['savings_per_unit'])),
        memberCount: _i(j['member_count']),
        joined: j['joined'] as bool? ?? false,
        closesAt: _dt(j['closes_at']),
      );
}

/// Result of pushing the offline queue.
class SyncOutcome {
  const SyncOutcome({
    required this.applied,
    required this.duplicates,
    required this.conflicts,
    required this.rejected,
    required this.statusByEventId,
    required this.items,
  });

  final int applied;
  final int duplicates;
  final int conflicts;
  final int rejected;
  final Map<String, String> statusByEventId;

  /// The server's authoritative state, which the client reconciles against
  /// rather than assuming its optimistic view was right (TRD 7.1).
  final List<InventoryItem> items;

  factory SyncOutcome.fromJson(Map<String, dynamic> j) => SyncOutcome(
        applied: _i(j['applied']),
        duplicates: _i(j['duplicates']),
        conflicts: _i(j['conflicts']),
        rejected: _i(j['rejected']),
        statusByEventId: <String, String>{
          for (final r in (j['results'] as List? ?? const []))
            r['client_event_id'] as String: r['status'] as String,
        },
        items: <InventoryItem>[
          for (final i in (j['items'] as List? ?? const []))
            itemFromJson(Map<String, dynamic>.from(i as Map)),
        ],
      );
}
