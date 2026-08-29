import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart' show HeatCell, SupplierPin;

import 'models.dart';

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
    }) =>
        InventoryItem(
          id: id,
          skuName: sku,
          category: category,
          quantity: Quantity(qty, unit),
          reorderPoint: reorder,
          unitCost: Money.rupees(cost),
          unitPrice: Money.rupees(price),
          shelfLifeDays: shelf,
          expiresOn:
              expiresInDays == null ? null : now.add(Duration(days: expiresInDays)),
        );

    return <InventoryItem>[
      make('d1', 'Milk', 'dairy', 62, 'pkt', 78, 24, 28, shelf: 3, expiresInDays: 1),
      make('d2', 'Curd', 'dairy', 34, 'pkt', 28, 20, 25, shelf: 3, expiresInDays: 2),
      make('d3', 'Paneer', 'dairy', 9, 'pc', 12, 70, 85, shelf: 3, expiresInDays: 0),
      make('d4', 'Eggs', 'dairy', 186, 'pc', 92, 6, 8, shelf: 3, expiresInDays: 3),
      make('d5', 'Bread', 'bakery', 22, 'pc', 30, 32, 40, shelf: 3, expiresInDays: 1),
      make('d6', 'Rice', 'staples', 148, 'kg', 62, 52, 62),
      make('d7', 'Wheat Flour', 'staples', 96, 'kg', 48, 38, 46),
      make('d8', 'Sugar', 'staples', 71, 'kg', 32, 42, 48),
      make('d9', 'Tea', 'staples', 28, 'pkt', 16, 130, 150),
      make('d10', 'Toor Dal', 'staples', 44, 'kg', 22, 118, 138),
      make('d11', 'Cooking Oil', 'staples', 51, 'l', 26, 140, 162),
      make('d12', 'Onion', 'produce', 118, 'kg', 74, 28, 36, shelf: 4, expiresInDays: 2),
      make('d13', 'Potato', 'produce', 96, 'kg', 62, 24, 32, shelf: 4, expiresInDays: 3),
      make('d14', 'Tomato', 'produce', 41, 'kg', 52, 30, 40, shelf: 4, expiresInDays: 0),
      make('d15', 'Biscuits', 'snacks', 214, 'pkt', 96, 10, 12, shelf: 120),
      make('d16', 'Namkeen', 'snacks', 63, 'pkt', 32, 38, 45, shelf: 120),
      make('d17', 'Soft Drink', 'beverages', 88, 'btl', 44, 32, 40, shelf: 180),
      make('d18', 'Soap', 'personal_care', 52, 'pc', 26, 34, 42),
      make('d19', 'Detergent', 'household', 31, 'kg', 18, 95, 115),
      make('d20', 'Umbrella', 'monsoon', 4, 'pc', 9, 180, 240),
      make('d21', 'Ladoo', 'sweets', 12, 'kg', 14, 220, 280, shelf: 7, expiresInDays: 4),
    ];
  }

  static DashboardSnapshot get dashboard => DashboardSnapshot(
        vendor: vendor,
        todaySalesValue: Money.rupees(12012),
        todayTransactionCount: 16,
        weekSalesValue: Money.rupees(176205),
        lowStockCount: 3,
        expiringSoonCount: 5,
        valueAtRisk: Money.rupees(9840),
        healthScore: 86.8,
        healthBand: 'strong',
        topSignal: 'Ganesh Chaturthi in 16 days',
        topSignalDetail: 'Expect ~130% more demand for sweets',
        pendingPools: 1,
      );

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

    Forecast build(
      String id,
      String sku,
      String category,
      double base,
      String? driver,
      double effect,
    ) =>
        Forecast(
          itemId: id,
          skuName: sku,
          category: category,
          modelVersion: 'vendor360-hybrid-gbr-v1',
          usedFallback: false,
          historyDays: 90,
          headline: driver == null
              ? 'Steady demand: about ${base.round()} units a day.'
              : 'Stock ${(effect * 100).round()}% more ${sku.toLowerCase()} '
                  'by ${_weekday(now.add(const Duration(days: 4)))} — $driver.',
          days: <ForecastDay>[
            for (var i = 1; i <= 7; i++)
              ForecastDay(
                on: now.add(Duration(days: i)),
                // Ramp the driver in over the horizon, the way the real
                // festival window does.
                predicted: base * (1 + effect * (i / 7)),
                lower: base * (1 + effect * (i / 7)) * 0.82,
                upper: base * (1 + effect * (i / 7)) * 1.18,
                driver: i >= 3 ? driver : null,
                driverEffect: i >= 3 ? effect * (i / 7) : 0,
              ),
          ],
        );

    return <Forecast>[
      build('d21', 'Ladoo', 'sweets', 4, 'Ganesh Chaturthi', 1.30),
      build('d20', 'Umbrella', 'monsoon', 2, 'Heavy rain forecast', 0.75),
      build('d1', 'Milk', 'dairy', 42, 'Ganesh Chaturthi', 0.62),
      build('d4', 'Eggs', 'dairy', 38, 'Ganesh Chaturthi', 0.38),
      build('d12', 'Onion', 'produce', 26, null, 0),
      build('d6', 'Rice', 'staples', 22, null, 0),
    ];
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
    ) =>
        ExpiryEntry(
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
        HeatCell(lat: 18.5075, lon: 73.8075, intensity: 1.00, demandQty: 74933, vendorCount: 5, topSku: 'Eggs', shortageCount: 2),
        HeatCell(lat: 18.4555, lon: 73.8655, intensity: 0.85, demandQty: 63788, vendorCount: 5, topSku: 'Milk', shortageCount: 3),
        HeatCell(lat: 18.5155, lon: 73.8455, intensity: 0.77, demandQty: 57793, vendorCount: 5, topSku: 'Eggs'),
        HeatCell(lat: 18.5655, lon: 73.9155, intensity: 0.71, demandQty: 52988, vendorCount: 4, topSku: 'Milk'),
        HeatCell(lat: 18.5305, lon: 73.8475, intensity: 0.66, demandQty: 49102, vendorCount: 5, topSku: 'Biscuits', shortageCount: 4),
        HeatCell(lat: 18.5115, lon: 73.8775, intensity: 0.58, demandQty: 43219, vendorCount: 4, topSku: 'Rice'),
        HeatCell(lat: 18.5085, lon: 73.9255, intensity: 0.52, demandQty: 39004, vendorCount: 5, topSku: 'Onion', shortageCount: 2),
        HeatCell(lat: 18.5595, lon: 73.8075, intensity: 0.44, demandQty: 33110, vendorCount: 4, topSku: 'Eggs'),
      ];

  static List<SupplierPin> get suppliers => const <SupplierPin>[
        SupplierPin(name: 'Market Yard', lat: 18.4890, lon: 73.8710, kind: 'mandi', leadDays: 1),
        SupplierPin(name: 'Gultekdi Mandi', lat: 18.4936, lon: 73.8656, kind: 'mandi', leadDays: 1),
        SupplierPin(name: 'Balaji Distributors', lat: 18.5121, lon: 73.8290, kind: 'distributor', leadDays: 2),
        SupplierPin(name: 'Shree FMCG', lat: 18.5325, lon: 73.8501, kind: 'distributor', leadDays: 2),
        SupplierPin(name: 'Pune Dairy', lat: 18.5602, lon: 73.8110, kind: 'distributor', leadDays: 1),
        SupplierPin(name: 'Ganesh Trading', lat: 18.5098, lon: 73.9240, kind: 'distributor', leadDays: 3),
      ];

  static String _weekday(DateTime d) => const <String>[
        'Monday', 'Tuesday', 'Wednesday', 'Thursday',
        'Friday', 'Saturday', 'Sunday',
      ][d.weekday - 1];
}
