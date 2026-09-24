import 'dart:math' as math;

import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart' show HeatCell, SupplierPin;

import 'models.dart';
import 'report_models.dart';
import 'udhaar_models.dart';

/// The seeded world every read falls back to.
///
/// Deliberately mirrors `backend/seed.py` — same store, same locality, same
/// SKUs — so a fallback is not visibly a different product. A demo that
/// degrades into obviously fake data announces the failure it was meant to
/// hide.
///
/// This is the CarryO demo-safety rule: reads may degrade, writes may not.
class DemoData {
  static DateTime get _today => DateTime.now();

  static const Vendor vendor = Vendor(
    id: 'demo-vendor',
    name: 'Rakesh Kumar',
    storeName: 'Kumar General Stores',
    phone: '9876510000',
    language: AppLanguage.hindi,
    locality: 'Kothrud',
    city: 'Pune',
    lat: 18.5074,
    lon: 73.8077,
    healthScore: 86.8,
    supplierLeadDays: 2,
  );

  /// The codes the seeder prints on the same packs, so a barcode scanned
  /// against the demo world resolves exactly as it does against the server.
  /// Loose goods are absent on purpose: rice out of a sack has no code, and
  /// the scan screen has to meet that case in the demo too.
  static const Map<String, String> barcodes = <String, String>{
    'Milk': '8909000000008',
    'Curd': '8909001370179',
    'Paneer': '8909002740346',
    'Butter': '8909004110512',
    'Bread': '8909005480683',
    'Tea': '8909006850850',
    'Cooking Oil': '8909008221023',
    'Salt': '8909009591194',
    'Biscuits': '8909010961368',
    'Namkeen': '8909012331534',
    'Soft Drink': '8909013701701',
    'Soap': '8909015071871',
    'Shampoo': '8909016442045',
    'Detergent': '8909017812212',
  };

  static List<InventoryItem> get items {
    final now = _today;
    InventoryItem make(
      String id,
      String sku,
      String category,
      double qty,
      String unit,
      double reorder,
      double cost,
      double price, {
      int? shelf,
      int? expiresInDays,
    }) => InventoryItem(
      id: id,
      skuName: sku,
      category: category,
      quantity: Quantity(qty, unit),
      reorderPoint: reorder,
      unitCost: Money.rupees(cost),
      unitPrice: Money.rupees(price),
      barcode: barcodes[sku],
      shelfLifeDays: shelf,
      expiresOn: expiresInDays == null
          ? null
          : now.add(Duration(days: expiresInDays)),
    );

    return <InventoryItem>[
      make(
        'd1',
        'Milk',
        'dairy',
        62,
        'pkt',
        78,
        24,
        28,
        shelf: 3,
        expiresInDays: 1,
      ),
      make(
        'd2',
        'Curd',
        'dairy',
        34,
        'pkt',
        28,
        20,
        25,
        shelf: 3,
        expiresInDays: 2,
      ),
      make(
        'd3',
        'Paneer',
        'dairy',
        9,
        'pc',
        12,
        70,
        85,
        shelf: 3,
        expiresInDays: 0,
      ),
      make(
        'd4',
        'Eggs',
        'dairy',
        186,
        'pc',
        92,
        6,
        8,
        shelf: 3,
        expiresInDays: 3,
      ),
      make(
        'd5',
        'Bread',
        'bakery',
        22,
        'pc',
        30,
        32,
        40,
        shelf: 3,
        expiresInDays: 1,
      ),
      make('d6', 'Rice', 'staples', 148, 'kg', 62, 52, 62),
      make('d7', 'Wheat Flour', 'staples', 96, 'kg', 48, 38, 46),
      make('d8', 'Sugar', 'staples', 71, 'kg', 32, 42, 48),
      make('d9', 'Tea', 'staples', 28, 'pkt', 16, 130, 150),
      make('d10', 'Toor Dal', 'staples', 44, 'kg', 22, 118, 138),
      make('d11', 'Cooking Oil', 'staples', 51, 'l', 26, 140, 162),
      make(
        'd12',
        'Onion',
        'produce',
        118,
        'kg',
        74,
        28,
        36,
        shelf: 4,
        expiresInDays: 2,
      ),
      make(
        'd13',
        'Potato',
        'produce',
        96,
        'kg',
        62,
        24,
        32,
        shelf: 4,
        expiresInDays: 3,
      ),
      make(
        'd14',
        'Tomato',
        'produce',
        41,
        'kg',
        52,
        30,
        40,
        shelf: 4,
        expiresInDays: 0,
      ),
      make('d15', 'Biscuits', 'snacks', 214, 'pkt', 96, 10, 12, shelf: 120),
      make('d16', 'Namkeen', 'snacks', 63, 'pkt', 32, 38, 45, shelf: 120),
      make('d17', 'Soft Drink', 'beverages', 88, 'btl', 44, 32, 40, shelf: 180),
      make('d18', 'Soap', 'personal_care', 52, 'pc', 26, 34, 42),
      make('d19', 'Detergent', 'household', 31, 'kg', 18, 95, 115),
      make('d20', 'Umbrella', 'monsoon', 4, 'pc', 9, 180, 240),
      make(
        'd21',
        'Ladoo',
        'sweets',
        12,
        'kg',
        14,
        220,
        280,
        shelf: 7,
        expiresInDays: 4,
      ),
    ];
  }

  /// Counted from the same seeded lists the other screens show, so the
  /// offline Home can never disagree with the offline Stock and Expiry
  /// screens. Expiring means within three days, as the server counts it.
  static DashboardSnapshot get dashboard {
    final soon = expiring.where((e) => e.daysLeft <= 3).toList();
    return DashboardSnapshot(
    vendor: vendor,
    todaySalesValue: Money.rupees(12012),
    todayTransactionCount: 16,
    weekSalesValue: Money.rupees(176205),
    lowStockCount: items.where((i) => i.isLow).length,
    expiringSoonCount: soon.length,
    valueAtRisk: Money.rupees(
      soon.fold<double>(0, (sum, e) => sum + e.valueAtRisk.rupees),
    ),
    healthScore: 86.8,
    healthBand: 'strong',
    topSignal: 'Ganesh Chaturthi in 16 days',
    topSignalDetail: 'Expect ~130% more demand for sweets',
    pendingPools: 1,
  );
  }

  static HealthScore get healthScore => const HealthScore(
    score: 86.8,
    band: ScoreBand.strong,
    provisional: false,
    daysOfHistory: 90,
    explanation:
        'Strongest: sales consistency (100/100). '
        'Most room to improve: inventory turnover (67/100).',
    components: <ScoreComponent>[
      ScoreComponent(
        key: 'consistency',
        label: 'Sales consistency',
        value: 100,
        weight: 0.40,
        contribution: 40,
        detail: 'active 90/90 days, avg gap 1.0d',
      ),
      ScoreComponent(
        key: 'turnover',
        label: 'Inventory turnover',
        value: 67,
        weight: 0.40,
        contribution: 26.8,
        detail: '21.5 inventory turns/year',
      ),
      ScoreComponent(
        key: 'waste',
        label: 'Waste control',
        value: 100,
        weight: 0.20,
        contribution: 20,
        detail: '4.3% of purchase value wasted',
      ),
    ],
  );

  static List<Forecast> get forecasts {
    final now = DateTime(_today.year, _today.month, _today.day);

    // Each item gets its own shape — a weekend rhythm, a little day-to-day
    // wobble, and a lift that swells towards its event and eases after it —
    // so the offline cards do not all draw the same straight ramp. The
    // headline names the day the series actually peaks, so "by Friday" and
    // "busiest day" can never disagree.
    Forecast build(
      String id,
      String sku,
      String category,
      double base,
      String? driver,
      double effect, {
      int peakDay = 5,
      double weekend = 0.12,
      int seed = 1,
    }) {
      final days = <ForecastDay>[
        for (var i = 1; i <= 7; i++)
          () {
            final on = now.add(Duration(days: i));
            final rhythm =
                1 +
                (on.weekday >= DateTime.saturday ? weekend : 0) +
                (((seed * 37 + i * 13) % 9) - 4) / 100;
            final lift = driver == null
                ? 0.0
                : effect * math.exp(-math.pow(i - peakDay, 2) / 5);
            final predicted = base * rhythm * (1 + lift);
            return ForecastDay(
              on: on,
              predicted: predicted,
              lower: predicted * 0.82,
              upper: predicted * 1.18,
              driver: lift > effect * 0.25 ? driver : null,
              driverEffect: lift > effect * 0.25 ? lift : 0,
            );
          }(),
      ];
      final peak = days.reduce((a, b) => a.predicted >= b.predicted ? a : b);

      return Forecast(
        itemId: id,
        skuName: sku,
        category: category,
        modelVersion: 'vendor360-hybrid-gbr-v1',
        usedFallback: false,
        historyDays: 90,
        headline: driver == null
            ? 'Steady demand: about ${base.round()} a day, busiest '
                  '${_weekday(peak.on)}.'
            : 'Stock ${(effect * 100).round()}% more ${sku.toLowerCase()} '
                  'by ${_weekday(peak.on)} — $driver.',
        days: days,
      );
    }

    return <Forecast>[
      build(
        'd21',
        'Ladoo',
        'sweets',
        4,
        'Ganesh Chaturthi',
        1.30,
        peakDay: 6,
        seed: 3,
      ),
      build(
        'd20',
        'Umbrella',
        'monsoon',
        2,
        'Heavy rain forecast',
        0.75,
        peakDay: 3,
        weekend: 0.02,
        seed: 5,
      ),
      build(
        'd1',
        'Milk',
        'dairy',
        42,
        'Ganesh Chaturthi',
        0.62,
        peakDay: 7,
        weekend: 0.08,
        seed: 2,
      ),
      build(
        'd4',
        'Eggs',
        'dairy',
        38,
        'Ganesh Chaturthi',
        0.38,
        peakDay: 5,
        weekend: 0.18,
        seed: 7,
      ),
      build('d12', 'Onion', 'produce', 26, null, 0, seed: 4),
      build('d6', 'Rice', 'staples', 22, null, 0, weekend: 0.2, seed: 6),
    ];
  }

  // ------------------------------------------------------------ reports
  /// The day as the seeded world has it, so the screen works with no signal.
  static DayClose get dayClose {
    final sold = <({String name, double qty, String unit, double value})>[
      (name: 'Milk', qty: 46, unit: 'pkt', value: 1288),
      (name: 'Rice', qty: 22, unit: 'kg', value: 1364),
      (name: 'Eggs', qty: 60, unit: 'pc', value: 480),
      (name: 'Bread', qty: 18, unit: 'pc', value: 630),
      (name: 'Onion', qty: 24, unit: 'kg', value: 672),
    ];

    return DayClose(
      on: _today,
      salesValue: Money.rupees(12012),
      transactionCount: 16,
      // Sales less what went out on the book, plus what came back.
      cashIn: Money.rupees(12012 - 300 + 200),
      wastageValue: Money.rupees(210),
      restockValue: Money.rupees(4820),
      udhaarGiven: Money.rupees(300),
      udhaarCollected: Money.rupees(200),
      lowStockCount: 6,
      topItems: <SoldItem>[
        for (final i in sold)
          SoldItem(
            skuName: i.name,
            quantity: Quantity(i.qty, i.unit),
            value: Money.rupees(i.value),
          ),
      ],
    );
  }

  /// Fourteen days with a weekend rhythm and one quiet day, so the chart has
  /// a shape to read rather than a straight line.
  static List<SalesPoint> get salesSeries {
    final today = DateTime(_today.year, _today.month, _today.day);
    return <SalesPoint>[
      for (var step = 13; step >= 0; step--)
        () {
          final on = today.subtract(Duration(days: step));
          final weekend = on.weekday >= DateTime.saturday;
          final quiet = step == 9;
          final base = quiet ? 0.0 : 9200 + (weekend ? 3400 : 0);
          final wobble = ((step * 37) % 11 - 5) * 90.0;
          return SalesPoint(
            on: on,
            value: Money.rupees(base == 0 ? 0 : base + wobble),
            count: quiet ? 0 : 11 + (step % 7),
          );
        }(),
    ];
  }

  // ------------------------------------------------------------- udhaar
  /// The seeded credit book, matching what `seed.py` writes, so the offline
  /// screen and the served one tell the same story.
  static const List<({String id, String name, String? phone, double owed,
      int days})> _debtors = <({String id, String name, String? phone,
      double owed, int days})>[
    (id: 'c1', name: 'Ramesh Kale', phone: null, owed: 240, days: 76),
    (id: 'c2', name: 'Anita Joshi', phone: '9822011002', owed: 480, days: 34),
    (id: 'c3', name: 'Deepak More', phone: '9822011005', owed: 180, days: 3),
    (id: 'c4', name: 'Suresh Patil', phone: '9822011001', owed: 350, days: 2),
    (id: 'c5', name: 'Farida Shaikh', phone: '9822011004', owed: 120, days: 1),
  ];

  static UdhaarBook get udhaarBook => UdhaarBook(
        outstanding: Money.rupees(
          _debtors.fold<double>(0, (sum, d) => sum + d.owed),
        ),
        customers: _debtors.length,
        oldestDays: _debtors.map((d) => d.days).reduce((a, b) => a > b ? a : b),
        rows: <UdhaarRow>[
          for (final d in _debtors)
            UdhaarRow(
              customer: Customer(id: d.id, name: d.name, phone: d.phone),
              owed: Money.rupees(d.owed),
              daysOutstanding: d.days,
              stale: d.days >= 30,
            ),
        ],
      );

  static UdhaarStatement udhaarStatement(String customerId) {
    final row = udhaarBook.rows.firstWhere(
      (r) => r.customer.id == customerId,
      orElse: () => udhaarBook.rows.first,
    );
    final now = _today;
    return UdhaarStatement(
      customer: row.customer,
      owed: row.owed,
      daysOutstanding: row.daysOutstanding,
      entries: <UdhaarEntry>[
        UdhaarEntry(
          id: '${row.customer.id}-e2',
          kind: 'credit',
          amount: row.owed,
          occurredAt: now.subtract(Duration(days: row.daysOutstanding)),
          note: 'atta, oil, biscuits',
        ),
        UdhaarEntry(
          id: '${row.customer.id}-e1',
          kind: 'payment',
          amount: Money.rupees(200),
          occurredAt: now.subtract(Duration(days: row.daysOutstanding + 6)),
        ),
      ],
    );
  }

  static List<ExpiryEntry> get expiring {
    final now = DateTime(_today.year, _today.month, _today.day);
    ExpiryEntry make(
      String id,
      String sku,
      String category,
      double qty,
      String unit,
      int days,
      double value,
    ) => ExpiryEntry(
      itemId: id,
      skuName: sku,
      category: category,
      quantity: Quantity(qty, unit),
      expiresOn: now.add(Duration(days: days)),
      daysLeft: days,
      valueAtRisk: Money.rupees(value),
      suggestedDiscountPct: switch (days) {
        <= 0 => 50,
        1 => 40,
        2 => 30,
        3 => 20,
        _ => 10,
      },
      urgency: switch (days) {
        < 0 => 'expired',
        <= 1 => 'critical',
        <= 3 => 'warning',
        _ => 'watch',
      },
    );

    return <ExpiryEntry>[
      make('d14', 'Tomato', 'produce', 41, 'kg', 0, 1230),
      make('d3', 'Paneer', 'dairy', 9, 'pc', 0, 630),
      make('d1', 'Milk', 'dairy', 62, 'pkt', 1, 1488),
      make('d5', 'Bread', 'bakery', 22, 'pc', 1, 704),
      make('d12', 'Onion', 'produce', 118, 'kg', 2, 3304),
      make('d2', 'Curd', 'dairy', 34, 'pkt', 2, 680),
      make('d13', 'Potato', 'produce', 96, 'kg', 3, 2304),
      make('d21', 'Ladoo', 'sweets', 12, 'kg', 4, 2640),
    ];
  }

  static List<BargainPool> get pools => <BargainPool>[
    BargainPool(
      id: 'p1',
      skuName: 'Umbrella',
      unit: 'pc',
      locality: 'Kothrud',
      targetQty: 72,
      committedQty: 46,
      baseUnitPrice: Money.rupees(183),
      bulkUnitPrice: Money.rupees(176),
      progress: 0.64,
      savingsPerUnit: Money.rupees(7.33),
      memberCount: 3,
      joined: false,
      closesAt: _today.add(const Duration(hours: 31)),
    ),
  ];

  /// Demand cells around Pune. Coordinates match the localities in the
  /// backend seed, so the fallback map is the same map.
  static List<HeatCell> get heatCells => const <HeatCell>[
    HeatCell(
      lat: 18.5075,
      lon: 73.8075,
      intensity: 1.00,
      demandQty: 74933,
      vendorCount: 5,
      topSku: 'Eggs',
      shortageCount: 2,
    ),
    HeatCell(
      lat: 18.4555,
      lon: 73.8655,
      intensity: 0.85,
      demandQty: 63788,
      vendorCount: 5,
      topSku: 'Milk',
      shortageCount: 3,
    ),
    HeatCell(
      lat: 18.5155,
      lon: 73.8455,
      intensity: 0.77,
      demandQty: 57793,
      vendorCount: 5,
      topSku: 'Eggs',
    ),
    HeatCell(
      lat: 18.5655,
      lon: 73.9155,
      intensity: 0.71,
      demandQty: 52988,
      vendorCount: 4,
      topSku: 'Milk',
    ),
    HeatCell(
      lat: 18.5305,
      lon: 73.8475,
      intensity: 0.66,
      demandQty: 49102,
      vendorCount: 5,
      topSku: 'Biscuits',
      shortageCount: 4,
    ),
    HeatCell(
      lat: 18.5115,
      lon: 73.8775,
      intensity: 0.58,
      demandQty: 43219,
      vendorCount: 4,
      topSku: 'Rice',
    ),
    HeatCell(
      lat: 18.5085,
      lon: 73.9255,
      intensity: 0.52,
      demandQty: 39004,
      vendorCount: 5,
      topSku: 'Onion',
      shortageCount: 2,
    ),
    HeatCell(
      lat: 18.5595,
      lon: 73.8075,
      intensity: 0.44,
      demandQty: 33110,
      vendorCount: 4,
      topSku: 'Eggs',
    ),
  ];

  static List<SupplierPin> get suppliers => const <SupplierPin>[
    SupplierPin(
      name: 'Market Yard',
      lat: 18.4890,
      lon: 73.8710,
      kind: 'mandi',
      leadDays: 1,
    ),
    SupplierPin(
      name: 'Gultekdi Mandi',
      lat: 18.4936,
      lon: 73.8656,
      kind: 'mandi',
      leadDays: 1,
    ),
    SupplierPin(
      name: 'Balaji Distributors',
      lat: 18.5121,
      lon: 73.8290,
      kind: 'distributor',
      leadDays: 2,
    ),
    SupplierPin(
      name: 'Shree FMCG',
      lat: 18.5325,
      lon: 73.8501,
      kind: 'distributor',
      leadDays: 2,
    ),
    SupplierPin(
      name: 'Pune Dairy',
      lat: 18.5602,
      lon: 73.8110,
      kind: 'distributor',
      leadDays: 1,
    ),
    SupplierPin(
      name: 'Ganesh Trading',
      lat: 18.5098,
      lon: 73.9240,
      kind: 'distributor',
      leadDays: 3,
    ),
  ];

  static String _weekday(DateTime d) => const <String>[
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][d.weekday - 1];
}
