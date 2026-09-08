/// Vendor360 domain model and contracts.
///
/// Pure Dart with zero runtime dependencies, following the rule established in
/// `carryo_core`: this is the layer every client agrees on, so anything it
/// imports becomes something every client is forced to accept. No Flutter, no
/// HTTP client, no state management.
///
/// The value objects are why the boundary matters. `Quantity` refuses to add
/// kilograms to packets, `Money` refuses to be a double, and `Confidence`
/// holds the single review threshold that every capture screen consults.
/// Duplicating those rules per client would mean several chances to get the
/// offline merge or the confirm step wrong.
library;

export 'src/values/quantity.dart';
export 'src/values/pack_quantity.dart';
export 'src/values/money.dart';
export 'src/values/confidence.dart';
export 'src/values/shelf_life.dart';
export 'src/values/pool_savings.dart';

export 'src/entities/inventory_item.dart';
export 'src/entities/stock_movement.dart';
export 'src/entities/health_score.dart';
export 'src/entities/forecast.dart';
export 'src/entities/vendor.dart';
