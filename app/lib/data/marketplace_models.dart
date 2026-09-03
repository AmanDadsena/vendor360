import 'package:vendor360_core/vendor360_core.dart';

/// Wire mapping for the two-sided marketplace.
///
/// Split from `models.dart` rather than appended to it: that file maps the
/// single-vendor product and had already reached the size where finding
/// anything meant scrolling. These types are only touched by the order and
/// distributor screens, so they travel together.

double _d(Object? v, [double fallback = 0]) =>
    v == null ? fallback : (v as num).toDouble();

int _i(Object? v, [int fallback = 0]) => v == null ? fallback : (v as num).toInt();

DateTime? _dt(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString())?.toLocal();

List<String> _strings(Object? v) =>
    <String>[for (final e in (v as List? ?? const [])) e.toString()];

// --------------------------------------------------------------- principal
/// Who is signed in. The router builds a different shell for each.
enum Principal { vendor, distributor }

/// The signed-in wholesaler, flattened across user and organisation.
class Distributor {
  const Distributor({
    required this.id,
    required this.supplierId,
    required this.name,
    required this.phone,
    required this.businessName,
    required this.kind,
    required this.locality,
    required this.city,
    required this.leadDays,
    required this.minOrderValue,
    required this.rating,
    required this.language,
  });

  final String id;
  final String supplierId;
  final String name;
  final String phone;
  final String businessName;
  final String kind;
  final String locality;
  final String city;
  final int leadDays;
  final double minOrderValue;
  final double rating;
  final AppLanguage language;

  /// Two letters for an avatar, from the business name.
  String get initials {
    final parts = businessName.trim().split(RegExp(r'\s+'))
      ..removeWhere((p) => p.isEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final one = parts.first;
      return (one.length >= 2 ? one.substring(0, 2) : one).toUpperCase();
    }
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  static Distributor fromJson(Map<String, dynamic> j) => Distributor(
        id: j['id'] as String,
        supplierId: j['supplier_id'] as String,
        name: j['name'] as String? ?? 'Distributor',
        phone: j['phone'] as String? ?? '',
        businessName: j['business_name'] as String? ?? 'My Business',
        kind: j['kind'] as String? ?? 'distributor',
        locality: j['locality'] as String? ?? '—',
        city: j['city'] as String? ?? 'Pune',
        leadDays: _i(j['lead_days'], 2),
        minOrderValue: _d(j['min_order_value']),
        rating: _d(j['rating'], 4),
        language: languageFromCode(j['language_pref'] as String? ?? 'hi'),
      );
}

// ------------------------------------------------------------ distributors
class SupplierCard {
  const SupplierCard({
    required this.id,
    required this.name,
    required this.kind,
    required this.locality,
    required this.categories,
    required this.leadDays,
    required this.minOrderValue,
    required this.rating,
    required this.connected,
    this.phone,
    this.distanceKm,
    this.catalogSize = 0,
    this.fillRate,
  });

  final String id;
  final String name;
  final String kind;
  final String locality;
  final List<String> categories;
  final int leadDays;
  final double minOrderValue;
  final double rating;
  final bool connected;
  final String? phone;
  final double? distanceKm;
  final int catalogSize;
  final double? fillRate;

  bool get isMandi => kind == 'mandi';

  static SupplierCard fromJson(Map<String, dynamic> j) => SupplierCard(
        id: j['id'] as String,
        name: j['name'] as String,
        kind: j['kind'] as String? ?? 'distributor',
        locality: j['locality'] as String? ?? '—',
        categories: _strings(j['categories']),
        leadDays: _i(j['lead_days'], 2),
        minOrderValue: _d(j['min_order_value']),
        rating: _d(j['rating'], 4),
        connected: j['connected'] as bool? ?? false,
        phone: j['phone'] as String?,
        distanceKm: j['distance_km'] == null ? null : _d(j['distance_km']),
        catalogSize: _i(j['catalog_size']),
        fillRate: j['fill_rate'] == null ? null : _d(j['fill_rate']),
      );
}

class Connection {
  const Connection({
    required this.supplierId,
    required this.supplierName,
    required this.locality,
    required this.status,
    required this.sharesDemand,
    required this.scopeCategories,
    required this.creditTermsDays,
    required this.outstanding,
    required this.openOrders,
    this.fillRate,
    this.connectedAt,
  });

  final String supplierId;
  final String supplierName;
  final String locality;
  final String status;
  final bool sharesDemand;
  final List<String> scopeCategories;
  final int creditTermsDays;
  final double outstanding;
  final int openOrders;
  final double? fillRate;
  final DateTime? connectedAt;

  bool get isCash => creditTermsDays == 0;

  String get termsLabel => isCash ? 'Cash on delivery' : '$creditTermsDays-day credit';

  static Connection fromJson(Map<String, dynamic> j) => Connection(
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String,
        locality: j['locality'] as String? ?? '—',
        status: j['status'] as String? ?? 'active',
        sharesDemand: j['shares_demand'] as bool? ?? false,
        scopeCategories: _strings(j['scope_categories']),
        creditTermsDays: _i(j['credit_terms_days']),
        outstanding: _d(j['outstanding']),
        openOrders: _i(j['open_orders']),
        fillRate: j['fill_rate'] == null ? null : _d(j['fill_rate']),
        connectedAt: _dt(j['connected_at']),
      );
}

// ---------------------------------------------------------------- sourcing
class SourcingOption {
  const SourcingOption({
    required this.supplierId,
    required this.supplierName,
    required this.catalogEntryId,
    required this.skuName,
    required this.unit,
    required this.packSize,
    required this.packPrice,
    required this.unitPrice,
    required this.moqPacks,
    required this.packsNeeded,
    required this.qtySupplied,
    required this.landedCost,
    required this.leadDays,
    required this.arrivesInTime,
    required this.score,
    required this.reasons,
    this.fillRate,
    this.distanceKm,
  });

  final String supplierId;
  final String supplierName;
  final String catalogEntryId;
  final String skuName;
  final String unit;
  final double packSize;
  final double packPrice;
  final double unitPrice;
  final int moqPacks;
  final double packsNeeded;
  final double qtySupplied;
  final double landedCost;
  final int leadDays;
  final bool arrivesInTime;
  final double score;
  final List<String> reasons;
  final double? fillRate;
  final double? distanceKm;

  Money get cost => Money.rupees(landedCost);

  /// The rounding, as a value object rather than three loose numbers — so the
  /// sheet, the cart and the confirmation all render it identically.
  PackQuantity get plan => PackQuantity(
        packs: packsNeeded.round(),
        packSize: packSize,
        unit: unit,
      );

  static SourcingOption fromJson(Map<String, dynamic> j) => SourcingOption(
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String,
        catalogEntryId: j['catalog_entry_id'] as String,
        skuName: j['sku_name'] as String,
        unit: j['unit'] as String? ?? 'pc',
        packSize: _d(j['pack_size'], 1),
        packPrice: _d(j['pack_price']),
        unitPrice: _d(j['unit_price']),
        moqPacks: _i(j['moq_packs'], 1),
        packsNeeded: _d(j['packs_needed']),
        qtySupplied: _d(j['qty_supplied']),
        landedCost: _d(j['landed_cost']),
        leadDays: _i(j['lead_days'], 2),
        arrivesInTime: j['arrives_in_time'] as bool? ?? true,
        score: _d(j['score']),
        reasons: _strings(j['reasons']),
        fillRate: j['fill_rate'] == null ? null : _d(j['fill_rate']),
        distanceKm: j['distance_km'] == null ? null : _d(j['distance_km']),
      );
}

class Sourcing {
  const Sourcing({
    required this.itemId,
    required this.skuName,
    required this.unit,
    required this.currentQty,
    required this.reorderPoint,
    required this.shortfall,
    required this.options,
    required this.unconnectedCount,
    this.daysOfCover,
  });

  final String itemId;
  final String skuName;
  final String unit;
  final double currentQty;
  final double reorderPoint;
  final double shortfall;
  final List<SourcingOption> options;
  final int unconnectedCount;
  final double? daysOfCover;

  bool get hasOptions => options.isNotEmpty;

  static Sourcing fromJson(Map<String, dynamic> j) => Sourcing(
        itemId: j['item_id'] as String,
        skuName: j['sku_name'] as String,
        unit: j['unit'] as String? ?? 'pc',
        currentQty: _d(j['current_qty']),
        reorderPoint: _d(j['reorder_point']),
        shortfall: _d(j['shortfall']),
        unconnectedCount: _i(j['unconnected_count']),
        daysOfCover: j['days_of_cover'] == null ? null : _d(j['days_of_cover']),
        options: <SourcingOption>[
          for (final o in (j['options'] as List? ?? const []))
            SourcingOption.fromJson(Map<String, dynamic>.from(o as Map)),
        ],
      );
}

// ------------------------------------------------------------------ orders
enum OrderStatus { draft, placed, confirmed, dispatched, delivered, cancelled }

OrderStatus orderStatusFrom(String? raw) => switch (raw) {
      'placed' => OrderStatus.placed,
      'confirmed' => OrderStatus.confirmed,
      'dispatched' => OrderStatus.dispatched,
      'delivered' => OrderStatus.delivered,
      'cancelled' => OrderStatus.cancelled,
      _ => OrderStatus.draft,
    };

extension OrderStatusLabel on OrderStatus {
  String get wire => name;

  /// What the shop calls it. Deliberately different from what the distributor
  /// calls it — "waiting" is a shop's word for the same row the wholesaler
  /// thinks of as "new".
  String get vendorLabel => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.placed => 'Waiting',
        OrderStatus.confirmed => 'Confirmed',
        OrderStatus.dispatched => 'On the way',
        OrderStatus.delivered => 'Received',
        OrderStatus.cancelled => 'Cancelled',
      };

  String get distributorLabel => switch (this) {
        OrderStatus.draft => 'Draft',
        OrderStatus.placed => 'New',
        OrderStatus.confirmed => 'To dispatch',
        OrderStatus.dispatched => 'In transit',
        OrderStatus.delivered => 'Delivered',
        OrderStatus.cancelled => 'Cancelled',
      };

  bool get isOpen =>
      this != OrderStatus.delivered && this != OrderStatus.cancelled;
}

class OrderLine {
  const OrderLine({
    required this.id,
    required this.skuName,
    required this.category,
    required this.unit,
    required this.packSize,
    required this.unitPrice,
    required this.packsOrdered,
    required this.qtyOrdered,
    required this.lineTotal,
    this.itemId,
    this.catalogEntryId,
    this.packsConfirmed,
    this.packsDelivered,
  });

  final String id;
  final String skuName;
  final String category;
  final String unit;
  final double packSize;
  final double unitPrice;
  final double packsOrdered;
  final double qtyOrdered;
  final double lineTotal;
  final String? itemId;
  final String? catalogEntryId;
  final double? packsConfirmed;
  final double? packsDelivered;

  /// Whatever this line currently promises, at whatever stage it has reached.
  double get effectivePacks =>
      packsDelivered ?? packsConfirmed ?? packsOrdered;

  /// True when the wholesaler committed to less than was asked for. The whole
  /// reason the three quantities are stored separately.
  bool get isShort => effectivePacks < packsOrdered - 0.001;

  double get shortBy => packsOrdered - effectivePacks;

  PackQuantity get plan => PackQuantity(
        packs: effectivePacks.round(),
        packSize: packSize,
        unit: unit,
      );

  Money get total => Money.rupees(lineTotal);

  static OrderLine fromJson(Map<String, dynamic> j) => OrderLine(
        id: j['id'] as String,
        skuName: j['sku_name'] as String,
        category: j['category'] as String? ?? 'staples',
        unit: j['unit'] as String? ?? 'pc',
        packSize: _d(j['pack_size'], 1),
        unitPrice: _d(j['unit_price']),
        packsOrdered: _d(j['packs_ordered']),
        qtyOrdered: _d(j['qty_ordered']),
        lineTotal: _d(j['line_total']),
        itemId: j['item_id'] as String?,
        catalogEntryId: j['catalog_entry_id'] as String?,
        packsConfirmed:
            j['packs_confirmed'] == null ? null : _d(j['packs_confirmed']),
        packsDelivered:
            j['packs_delivered'] == null ? null : _d(j['packs_delivered']),
      );
}

class OrderEvent {
  const OrderEvent({
    required this.actorRole,
    required this.toStatus,
    required this.createdAt,
    this.fromStatus,
    this.note,
  });

  final String actorRole;
  final OrderStatus toStatus;
  final DateTime createdAt;
  final OrderStatus? fromStatus;
  final String? note;

  static OrderEvent fromJson(Map<String, dynamic> j) => OrderEvent(
        actorRole: j['actor_role'] as String? ?? 'system',
        toStatus: orderStatusFrom(j['to_status'] as String?),
        createdAt: _dt(j['created_at']) ?? DateTime.now(),
        fromStatus: j['from_status'] == null
            ? null
            : orderStatusFrom(j['from_status'] as String?),
        note: j['note'] as String?,
      );
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.code,
    required this.status,
    required this.vendorId,
    required this.vendorName,
    required this.supplierId,
    required this.supplierName,
    required this.paymentTermsDays,
    required this.amountTotal,
    required this.amountPaid,
    required this.amountDue,
    required this.lineCount,
    required this.lines,
    required this.events,
    this.supplierPhone,
    this.placedAt,
    this.expectedAt,
    this.deliveredAt,
    this.note,
    this.poolId,
  });

  final String id;
  final String code;
  final OrderStatus status;
  final String vendorId;
  final String vendorName;
  final String supplierId;
  final String supplierName;
  final int paymentTermsDays;
  final double amountTotal;
  final double amountPaid;
  final double amountDue;
  final int lineCount;
  final List<OrderLine> lines;
  final List<OrderEvent> events;
  final String? supplierPhone;
  final DateTime? placedAt;
  final DateTime? expectedAt;
  final DateTime? deliveredAt;
  final String? note;
  final String? poolId;

  Money get total => Money.rupees(amountTotal);
  Money get due => Money.rupees(amountDue);

  bool get isPool => poolId != null;

  /// Any line the wholesaler could not fill completely.
  bool get hasShortfall => lines.any((l) => l.isShort);

  /// Days until arrival — negative when the promised date has passed.
  int? get daysUntilExpected {
    if (expectedAt == null) return null;
    final today = DateTime.now();
    return DateTime(expectedAt!.year, expectedAt!.month, expectedAt!.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;
  }

  bool get isLate =>
      status.isOpen &&
      status != OrderStatus.draft &&
      (daysUntilExpected ?? 1) < 0;

  static PurchaseOrder fromJson(Map<String, dynamic> j) => PurchaseOrder(
        id: j['id'] as String,
        code: j['code'] as String,
        status: orderStatusFrom(j['status'] as String?),
        vendorId: j['vendor_id'] as String,
        vendorName: j['vendor_name'] as String? ?? 'Shop',
        supplierId: j['supplier_id'] as String,
        supplierName: j['supplier_name'] as String? ?? 'Distributor',
        supplierPhone: j['supplier_phone'] as String?,
        paymentTermsDays: _i(j['payment_terms_days']),
        amountTotal: _d(j['amount_total']),
        amountPaid: _d(j['amount_paid']),
        amountDue: _d(j['amount_due']),
        lineCount: _i(j['line_count']),
        placedAt: _dt(j['placed_at']),
        expectedAt: _dt(j['expected_at']),
        deliveredAt: _dt(j['delivered_at']),
        note: j['note'] as String?,
        poolId: j['pool_id'] as String?,
        lines: <OrderLine>[
          for (final l in (j['lines'] as List? ?? const []))
            OrderLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
        events: <OrderEvent>[
          for (final e in (j['events'] as List? ?? const []))
            OrderEvent.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

// ------------------------------------------------------------------ ledger
class LedgerLine {
  const LedgerLine({
    required this.id,
    required this.kind,
    required this.amount,
    required this.counterparty,
    required this.overdue,
    required this.createdAt,
    this.orderCode,
    this.dueOn,
    this.note,
  });

  final String id;
  final String kind;
  final double amount;
  final String counterparty;
  final bool overdue;
  final DateTime createdAt;
  final String? orderCode;
  final DateTime? dueOn;
  final String? note;

  bool get isPayment => kind == 'payment';

  Money get money => Money.rupees(amount);

  static LedgerLine fromJson(Map<String, dynamic> j) => LedgerLine(
        id: j['id'] as String,
        kind: j['kind'] as String? ?? 'charge',
        amount: _d(j['amount']),
        counterparty: j['counterparty'] as String? ?? 'Unknown',
        overdue: j['overdue'] as bool? ?? false,
        createdAt: _dt(j['created_at']) ?? DateTime.now(),
        orderCode: j['order_code'] as String?,
        dueOn: _dt(j['due_on']),
        note: j['note'] as String?,
      );
}

class Ledger {
  const Ledger({
    required this.outstanding,
    required this.overdue,
    required this.dueThisWeek,
    required this.entries,
  });

  final double outstanding;
  final double overdue;
  final double dueThisWeek;
  final List<LedgerLine> entries;

  static const Ledger empty =
      Ledger(outstanding: 0, overdue: 0, dueThisWeek: 0, entries: []);

  Money get outstandingMoney => Money.rupees(outstanding);
  Money get overdueMoney => Money.rupees(overdue);

  static Ledger fromJson(Map<String, dynamic> j) => Ledger(
        outstanding: _d(j['outstanding']),
        overdue: _d(j['overdue']),
        dueThisWeek: _d(j['due_this_week']),
        entries: <LedgerLine>[
          for (final e in (j['entries'] as List? ?? const []))
            LedgerLine.fromJson(Map<String, dynamic>.from(e as Map)),
        ],
      );
}

// ----------------------------------------------------------------- catalog
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.skuName,
    required this.category,
    required this.unit,
    required this.packSize,
    required this.packPrice,
    required this.unitPrice,
    required this.moqPacks,
    required this.active,
    this.leadDays,
    this.availablePacks,
  });

  final String id;
  final String skuName;
  final String category;
  final String unit;
  final double packSize;
  final double packPrice;
  final double unitPrice;
  final int moqPacks;
  final bool active;
  final int? leadDays;
  final double? availablePacks;

  Money get packMoney => Money.rupees(packPrice);
  Money get unitMoney => Money.rupees(unitPrice);

  String get packLabel {
    final size = packSize == packSize.roundToDouble()
        ? packSize.toStringAsFixed(0)
        : packSize.toString();
    return '$size $unit / case';
  }

  static CatalogEntry fromJson(Map<String, dynamic> j) => CatalogEntry(
        id: j['id'] as String,
        skuName: j['sku_name'] as String,
        category: j['category'] as String? ?? 'staples',
        unit: j['unit'] as String? ?? 'pc',
        packSize: _d(j['pack_size'], 1),
        packPrice: _d(j['pack_price']),
        unitPrice: _d(j['unit_price']),
        moqPacks: _i(j['moq_packs'], 1),
        active: j['active'] as bool? ?? true,
        leadDays: j['lead_days'] == null ? null : _i(j['lead_days']),
        availablePacks:
            j['available_packs'] == null ? null : _d(j['available_packs']),
      );
}

class PriceListRow {
  const PriceListRow({
    required this.row,
    required this.skuName,
    required this.category,
    required this.unit,
    required this.packSize,
    required this.packPrice,
    required this.moqPacks,
    required this.action,
    required this.errors,
  });

  final int row;
  final String skuName;
  final String category;
  final String unit;
  final double packSize;
  final double packPrice;
  final int moqPacks;
  final String action;
  final List<String> errors;

  bool get ok => errors.isEmpty;

  static PriceListRow fromJson(Map<String, dynamic> j) => PriceListRow(
        row: _i(j['row']),
        skuName: j['sku_name'] as String? ?? '',
        category: j['category'] as String? ?? 'staples',
        unit: j['unit'] as String? ?? 'pc',
        packSize: _d(j['pack_size']),
        packPrice: _d(j['pack_price']),
        moqPacks: _i(j['moq_packs'], 1),
        action: j['action'] as String? ?? 'skip',
        errors: _strings(j['errors']),
      );
}

class PriceListPreview {
  const PriceListPreview({
    required this.rows,
    required this.valid,
    required this.invalid,
    required this.willCreate,
    required this.willUpdate,
  });

  final List<PriceListRow> rows;
  final int valid;
  final int invalid;
  final int willCreate;
  final int willUpdate;

  static PriceListPreview fromJson(Map<String, dynamic> j) => PriceListPreview(
        valid: _i(j['valid']),
        invalid: _i(j['invalid']),
        willCreate: _i(j['will_create']),
        willUpdate: _i(j['will_update']),
        rows: <PriceListRow>[
          for (final r in (j['rows'] as List? ?? const []))
            PriceListRow.fromJson(Map<String, dynamic>.from(r as Map)),
        ],
      );
}

// ------------------------------------------------- distributor intelligence
class DemandLine {
  const DemandLine({
    required this.skuName,
    required this.category,
    required this.unit,
    required this.expectedQty,
    required this.shopCount,
    required this.estRevenue,
    required this.confidence,
    this.catalogEntryId,
    this.packsToStock,
  });

  final String skuName;
  final String category;
  final String unit;
  final double expectedQty;
  final int shopCount;
  final double estRevenue;
  final String confidence;
  final String? catalogEntryId;
  final double? packsToStock;

  Money get revenue => Money.rupees(estRevenue);

  static DemandLine fromJson(Map<String, dynamic> j) => DemandLine(
        skuName: j['sku_name'] as String,
        category: j['category'] as String? ?? 'staples',
        unit: j['unit'] as String? ?? 'pc',
        expectedQty: _d(j['expected_qty']),
        shopCount: _i(j['shop_count']),
        estRevenue: _d(j['est_revenue']),
        confidence: j['confidence'] as String? ?? 'medium',
        catalogEntryId: j['catalog_entry_id'] as String?,
        packsToStock:
            j['packs_to_stock'] == null ? null : _d(j['packs_to_stock']),
      );
}

class AtRiskShop {
  const AtRiskShop({
    required this.vendorId,
    required this.storeName,
    required this.locality,
    required this.skuName,
    required this.unit,
    required this.currentQty,
    required this.dailyRate,
    required this.daysOfCover,
    required this.leadDays,
    required this.shortfallByArrival,
    required this.suggestedPacks,
    required this.estValue,
  });

  final String vendorId;
  final String storeName;
  final String locality;
  final String skuName;
  final String unit;
  final double currentQty;
  final double dailyRate;
  final double daysOfCover;
  final int leadDays;
  final double shortfallByArrival;
  final double suggestedPacks;
  final double estValue;

  Money get value => Money.rupees(estValue);

  /// "1.6d left · 3d to reach them" — the whole argument in one line.
  ///
  /// A shop that has already run out says so. "0.0d left" reads as a
  /// rounding artefact, which is the opposite of the urgency it should carry.
  String get urgency {
    final reach = '${leadDays}d to reach them';
    if (daysOfCover < 0.05) return 'Already out · $reach';

    final cover = daysOfCover < 3
        ? daysOfCover.toStringAsFixed(1)
        : daysOfCover.toStringAsFixed(0);
    return '${cover}d left · $reach';
  }

  static AtRiskShop fromJson(Map<String, dynamic> j) => AtRiskShop(
        vendorId: j['vendor_id'] as String,
        storeName: j['store_name'] as String,
        locality: j['locality'] as String? ?? '—',
        skuName: j['sku_name'] as String,
        unit: j['unit'] as String? ?? 'pc',
        currentQty: _d(j['current_qty']),
        dailyRate: _d(j['daily_rate']),
        daysOfCover: _d(j['days_of_cover']),
        leadDays: _i(j['lead_days'], 2),
        shortfallByArrival: _d(j['shortfall_by_arrival']),
        suggestedPacks: _d(j['suggested_packs']),
        estValue: _d(j['est_value']),
      );
}

class DeadLine {
  const DeadLine({
    required this.catalogEntryId,
    required this.skuName,
    required this.category,
    required this.packPrice,
    this.daysSinceLastOrder,
  });

  final String catalogEntryId;
  final String skuName;
  final String category;
  final double packPrice;
  final int? daysSinceLastOrder;

  static DeadLine fromJson(Map<String, dynamic> j) => DeadLine(
        catalogEntryId: j['catalog_entry_id'] as String,
        skuName: j['sku_name'] as String,
        category: j['category'] as String? ?? 'staples',
        packPrice: _d(j['pack_price']),
        daysSinceLastOrder: j['days_since_last_order'] == null
            ? null
            : _i(j['days_since_last_order']),
      );
}

class Demand {
  const Demand({
    required this.horizonDays,
    required this.consentingShops,
    required this.totalConnected,
    required this.lines,
    required this.atRisk,
    required this.deadLines,
  });

  final int horizonDays;
  final int consentingShops;
  final int totalConnected;
  final List<DemandLine> lines;
  final List<AtRiskShop> atRisk;
  final List<DeadLine> deadLines;

  /// Shops that trade but withhold their numbers. Shown, not hidden: a
  /// distributor should know the picture is partial and why.
  int get withheld => totalConnected - consentingShops;

  static Demand fromJson(Map<String, dynamic> j) => Demand(
        horizonDays: _i(j['horizon_days'], 7),
        consentingShops: _i(j['consenting_shops']),
        totalConnected: _i(j['total_connected']),
        lines: <DemandLine>[
          for (final l in (j['lines'] as List? ?? const []))
            DemandLine.fromJson(Map<String, dynamic>.from(l as Map)),
        ],
        atRisk: <AtRiskShop>[
          for (final a in (j['at_risk'] as List? ?? const []))
            AtRiskShop.fromJson(Map<String, dynamic>.from(a as Map)),
        ],
        deadLines: <DeadLine>[
          for (final d in (j['dead_lines'] as List? ?? const []))
            DeadLine.fromJson(Map<String, dynamic>.from(d as Map)),
        ],
      );
}

class BookEntry {
  const BookEntry({
    required this.vendorId,
    required this.storeName,
    required this.ownerName,
    required this.locality,
    required this.phone,
    required this.orderCount,
    required this.deliveredCount,
    required this.revenue,
    required this.outstanding,
    required this.sharesDemand,
    this.fillRate,
    this.lastOrderAt,
    this.connectedAt,
  });

  final String vendorId;
  final String storeName;
  final String ownerName;
  final String locality;
  final String phone;
  final int orderCount;
  final int deliveredCount;
  final double revenue;
  final double outstanding;
  final bool sharesDemand;
  final double? fillRate;
  final DateTime? lastOrderAt;
  final DateTime? connectedAt;

  Money get revenueMoney => Money.rupees(revenue);
  Money get outstandingMoney => Money.rupees(outstanding);

  int? get daysSinceLastOrder => lastOrderAt == null
      ? null
      : DateTime.now().difference(lastOrderAt!).inDays;

  /// A customer who has stopped ordering. Worth a call before they are gone.
  bool get isLapsing => (daysSinceLastOrder ?? 0) > 30;

  static BookEntry fromJson(Map<String, dynamic> j) => BookEntry(
        vendorId: j['vendor_id'] as String,
        storeName: j['store_name'] as String,
        ownerName: j['owner_name'] as String? ?? '',
        locality: j['locality'] as String? ?? '—',
        phone: j['phone'] as String? ?? '',
        orderCount: _i(j['order_count']),
        deliveredCount: _i(j['delivered_count']),
        revenue: _d(j['revenue']),
        outstanding: _d(j['outstanding']),
        sharesDemand: j['shares_demand'] as bool? ?? false,
        fillRate: j['fill_rate'] == null ? null : _d(j['fill_rate']),
        lastOrderAt: _dt(j['last_order_at']),
        connectedAt: _dt(j['connected_at']),
      );
}

class DistributorSummary {
  const DistributorSummary({
    required this.businessName,
    required this.needsAction,
    required this.toDispatch,
    required this.inTransit,
    required this.deliveredThisWeek,
    required this.revenueThisWeek,
    required this.outstanding,
    required this.overdue,
    required this.connectedShops,
    required this.atRiskCount,
    required this.openPoolCount,
    this.topPrompt,
    this.topPromptDetail,
  });

  final String businessName;
  final int needsAction;
  final int toDispatch;
  final int inTransit;
  final int deliveredThisWeek;
  final double revenueThisWeek;
  final double outstanding;
  final double overdue;
  final int connectedShops;
  final int atRiskCount;
  final int openPoolCount;
  final String? topPrompt;
  final String? topPromptDetail;

  Money get revenue => Money.rupees(revenueThisWeek);
  Money get outstandingMoney => Money.rupees(outstanding);
  Money get overdueMoney => Money.rupees(overdue);

  static const DistributorSummary empty = DistributorSummary(
    businessName: '—',
    needsAction: 0,
    toDispatch: 0,
    inTransit: 0,
    deliveredThisWeek: 0,
    revenueThisWeek: 0,
    outstanding: 0,
    overdue: 0,
    connectedShops: 0,
    atRiskCount: 0,
    openPoolCount: 0,
  );

  static DistributorSummary fromJson(Map<String, dynamic> j) =>
      DistributorSummary(
        businessName: j['business_name'] as String? ?? '—',
        needsAction: _i(j['needs_action']),
        toDispatch: _i(j['to_dispatch']),
        inTransit: _i(j['in_transit']),
        deliveredThisWeek: _i(j['delivered_this_week']),
        revenueThisWeek: _d(j['revenue_this_week']),
        outstanding: _d(j['outstanding']),
        overdue: _d(j['overdue']),
        connectedShops: _i(j['connected_shops']),
        atRiskCount: _i(j['at_risk_count']),
        openPoolCount: _i(j['open_pool_count']),
        topPrompt: j['top_prompt'] as String?,
        topPromptDetail: j['top_prompt_detail'] as String?,
      );
}

// -------------------------------------------------------------- onboarding
class MasterSku {
  const MasterSku({
    required this.key,
    required this.nameEn,
    required this.nameHi,
    required this.nameMr,
    required this.category,
    required this.unit,
    required this.typicalPrice,
    required this.popularity,
  });

  final String key;
  final String nameEn;
  final String nameHi;
  final String nameMr;
  final String category;
  final String unit;
  final double typicalPrice;
  final int popularity;

  String nameFor(AppLanguage language) => switch (language) {
        AppLanguage.hindi => nameHi,
        AppLanguage.marathi => nameMr,
        AppLanguage.english => nameEn,
      };

  static MasterSku fromJson(Map<String, dynamic> j) => MasterSku(
        key: j['key'] as String,
        nameEn: j['name_en'] as String,
        nameHi: j['name_hi'] as String? ?? j['name_en'] as String,
        nameMr: j['name_mr'] as String? ?? j['name_en'] as String,
        category: j['category'] as String? ?? 'staples',
        unit: j['unit'] as String? ?? 'pc',
        typicalPrice: _d(j['typical_price']),
        popularity: _i(j['popularity']),
      );
}

/// One line a vendor is about to order. Held in memory only — a cart that
/// survived a relaunch would quietly re-order yesterday's shortage.
class CartLine {
  CartLine({
    required this.option,
    required this.itemId,
    required this.packs,
  });

  final SourcingOption option;
  final String? itemId;
  int packs;

  double get quantity => packs * option.packSize;
  double get total => packs * option.packPrice;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'catalog_entry_id': option.catalogEntryId,
        if (itemId != null) 'item_id': itemId,
        'packs': packs,
      };
}
