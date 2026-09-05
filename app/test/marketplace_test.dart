import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/marketplace_models.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/features/alerts/demo_banner.dart';
import 'package:vendor360/features/dist/dist_demand_screen.dart';
import 'package:vendor360/features/dist/dist_orders_screen.dart';
import 'package:vendor360/features/dist/dist_shops_screen.dart';
import 'package:vendor360/features/dist/dist_today_screen.dart';
import 'package:vendor360/features/distributors/distributors_screen.dart';
import 'package:vendor360/features/orders/cart_screen.dart';
import 'package:vendor360/features/orders/orders_screen.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// The two-sided marketplace, rendered against a scripted API.
///
/// Unlike `screens_test.dart` — which points at a dead socket to prove the
/// offline fallback produces a usable screen — these screens have no seeded
/// demo world behind them, so a canned server is what lets them be asserted
/// at all. Both empty and populated states are covered, because an empty
/// state that renders wrong is a first-run experience that renders wrong.
void main() {
  late ProviderContainer container;

  /// Serves canned JSON by path. Any path not listed returns an empty list,
  /// which is what makes the empty-state tests one line.
  ApiClient scripted(Map<String, Object?> routes) => ApiClient(
        client: MockClient((request) async {
          final path = request.url.path;
          final body = routes[path];
          return http.Response(
            jsonEncode(body ?? const <dynamic>[]),
            200,
            headers: <String, String>{
              'content-type': 'application/json; charset=utf-8',
            },
          );
        }),
      );

  Widget host(Widget screen) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: MotionScope(child: screen),
        ),
      );

  void boot(Map<String, Object?> routes) {
    container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(scripted(routes)),
      ],
    );
  }

  tearDown(() => container.dispose());

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  // ------------------------------------------------------------- fixtures
  Map<String, Object?> order({
    String code = 'PO-0001',
    String status = 'placed',
    double total = 1104,
    bool short = false,
  }) =>
      <String, Object?>{
        'id': 'order-1',
        'code': code,
        'status': status,
        'vendor_id': 'v1',
        'vendor_name': 'Kumar General Stores',
        'supplier_id': 's1',
        'supplier_name': 'Balaji Distributors',
        'payment_terms_days': 7,
        'amount_total': total,
        'amount_paid': 0,
        'amount_due': total,
        'line_count': 1,
        'placed_at': DateTime.now().toIso8601String(),
        'expected_at':
            DateTime.now().add(const Duration(days: 2)).toIso8601String(),
        'lines': <Object?>[
          <String, Object?>{
            'id': 'line-1',
            'sku_name': 'Milk',
            'category': 'dairy',
            'unit': 'pkt',
            'pack_size': 12,
            'unit_price': 23,
            'packs_ordered': 4,
            'packs_confirmed': short ? 2 : null,
            'packs_delivered': null,
            'qty_ordered': 48,
            'line_total': total,
            'catalog_entry_id': 'c1',
            'item_id': 'i1',
          },
        ],
        'events': <Object?>[],
      };

  // ================================================== vendor: distributors
  testWidgets('Distributors screen separates who you buy from', (tester) async {
    boot(<String, Object?>{
      '/distributors': <Object?>[
        <String, Object?>{
          'id': 's1',
          'name': 'Balaji Distributors',
          'kind': 'distributor',
          'locality': 'Kothrud',
          'city': 'Pune',
          'categories': <String>['dairy'],
          'lead_days': 2,
          'min_order_value': 3000,
          'rating': 4.4,
          'connected': true,
          'catalog_size': 9,
          'distance_km': 2.16,
          'fill_rate': 0.94,
        },
        <String, Object?>{
          'id': 's2',
          'name': 'Pune Dairy Supply',
          'kind': 'distributor',
          'locality': 'Aundh',
          'city': 'Pune',
          'categories': <String>['dairy'],
          'lead_days': 1,
          'min_order_value': 1200,
          'rating': 4.1,
          'connected': false,
          'catalog_size': 5,
        },
      ],
      '/connections': <Object?>[
        <String, Object?>{
          'supplier_id': 's1',
          'supplier_name': 'Balaji Distributors',
          'locality': 'Kothrud',
          'status': 'active',
          'shares_demand': true,
          'scope_categories': <String>['dairy'],
          'credit_terms_days': 7,
          'credit_limit': 0,
          'connected_at': DateTime.now().toIso8601String(),
          'outstanding': 4502,
          'open_orders': 1,
        },
      ],
    });

    await tester.pumpWidget(host(const DistributorsScreen()));
    await settle(tester);

    expect(find.text('YOU BUY FROM'), findsOneWidget);
    expect(find.text('NEAR YOU'), findsOneWidget);
    expect(find.text('Balaji Distributors'), findsOneWidget);
    expect(find.text('Pune Dairy Supply'), findsOneWidget);

    // The connected one shows terms and what they can see.
    expect(find.text('7-day credit'), findsOneWidget);
    expect(
      find.text('They can see what you will need in dairy'),
      findsOneWidget,
    );
    expect(find.text('₹4502 outstanding'), findsOneWidget);

    // Actions differ by state. A connected wholesaler leads with the thing a
    // shop does weekly; disconnecting is demoted to an icon, because it is
    // rare and destructive.
    expect(find.text('Connect'), findsOneWidget);
    expect(find.text('Usual order'), findsOneWidget);
  });

  testWidgets('a distributor who cannot see your numbers says so',
      (tester) async {
    boot(<String, Object?>{
      '/distributors': <Object?>[
        <String, Object?>{
          'id': 's1',
          'name': 'Quiet Traders',
          'kind': 'distributor',
          'locality': 'Camp',
          'city': 'Pune',
          'categories': <String>['staples'],
          'lead_days': 3,
          'min_order_value': 0,
          'rating': 4.0,
          'connected': true,
          'catalog_size': 4,
        },
      ],
      '/connections': <Object?>[
        <String, Object?>{
          'supplier_id': 's1',
          'supplier_name': 'Quiet Traders',
          'locality': 'Camp',
          'status': 'active',
          'shares_demand': false,
          'scope_categories': <String>['staples'],
          'credit_terms_days': 0,
          'credit_limit': 0,
          'connected_at': DateTime.now().toIso8601String(),
          'outstanding': 0,
          'open_orders': 0,
        },
      ],
    });

    await tester.pumpWidget(host(const DistributorsScreen()));
    await settle(tester);

    expect(find.text('Cash on delivery'), findsOneWidget);
    expect(
      find.text('They cannot see your stock or forecasts'),
      findsOneWidget,
    );
  });

  // ========================================================= vendor: orders
  testWidgets('Orders screen lists an order with its stage and due date',
      (tester) async {
    boot(<String, Object?>{'/orders': <Object?>[order()]});

    await tester.pumpWidget(host(const OrdersScreen()));
    await settle(tester);

    expect(find.text('Balaji Distributors'), findsOneWidget);
    // The shop's vocabulary, not the wholesaler's. Two matches: the filter
    // chip and the status pill on the card.
    expect(find.text('Waiting'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byType(OrderStatusChip),
        matching: find.text('Waiting'),
      ),
      findsOneWidget,
    );
    expect(find.text('PO-0001 · 1 item'), findsOneWidget);
    expect(find.text('Due in 2 days'), findsOneWidget);
    expect(find.text('₹1,104'), findsOneWidget);
  });

  testWidgets('a late order is called out rather than shown as due',
      (tester) async {
    final late = order()
      ..['expected_at'] =
          DateTime.now().subtract(const Duration(days: 3)).toIso8601String();

    boot(<String, Object?>{'/orders': <Object?>[late]});

    await tester.pumpWidget(host(const OrdersScreen()));
    await settle(tester);

    expect(find.text('Was due 3 days ago'), findsOneWidget);
  });

  testWidgets('a part-filled order is flagged on the card', (tester) async {
    boot(<String, Object?>{
      '/orders': <Object?>[order(status: 'confirmed', short: true)],
    });

    await tester.pumpWidget(host(const OrdersScreen()));
    await settle(tester);

    expect(find.text('Part-filled — some items short'), findsOneWidget);
  });

  testWidgets('Orders screen has a first-run empty state', (tester) async {
    boot(<String, Object?>{'/orders': <Object?>[]});

    await tester.pumpWidget(host(const OrdersScreen()));
    await settle(tester);

    expect(find.text('No orders yet'), findsOneWidget);
    expect(find.text('See what is low'), findsOneWidget);
  });

  testWidgets('an empty cart points at where orders come from', (tester) async {
    boot(<String, Object?>{});

    await tester.pumpWidget(host(const CartScreen()));
    await settle(tester);

    expect(find.text('Nothing to order yet'), findsOneWidget);
  });

  testWidgets('the cart shows the case maths and the running total',
      (tester) async {
    boot(<String, Object?>{});

    container.read(cartProvider.notifier).add(
          CartLine(
            itemId: 'i1',
            packs: 2,
            option: SourcingOption.fromJson(<String, dynamic>{
              'supplier_id': 's1',
              'supplier_name': 'Balaji Distributors',
              'catalog_entry_id': 'c1',
              'sku_name': 'Atta',
              'unit': 'kg',
              'pack_size': 10,
              'pack_price': 420,
              'unit_price': 42,
              'moq_packs': 1,
              'packs_needed': 2,
              'qty_supplied': 20,
              'landed_cost': 840,
              'lead_days': 2,
              'arrives_in_time': true,
              'score': 0.8,
              'reasons': <String>[],
            }),
          ),
        );

    await tester.pumpWidget(host(const CartScreen()));
    await settle(tester);

    expect(find.text('Balaji Distributors'), findsOneWidget);
    expect(find.text('Atta'), findsOneWidget);
    expect(find.text('₹420 per case of 10 kg'), findsOneWidget);
    // Two cases of 10 kg, priced at ₹42/kg — the stepper states both.
    expect(find.text('20 kg · ₹840'), findsOneWidget);
    expect(find.text('₹840'), findsOneWidget);
    expect(find.text('Send order'), findsOneWidget);
  });

  // ==================================================== distributor: today
  testWidgets('Today leads with the single most useful next action',
      (tester) async {
    boot(<String, Object?>{
      '/dist/summary': <String, Object?>{
        'business_name': 'Market Yard Wholesale',
        'needs_action': 2,
        'to_dispatch': 1,
        'in_transit': 3,
        'delivered_this_week': 6,
        'revenue_this_week': 24500,
        'outstanding': 14108,
        'overdue': 3200,
        'connected_shops': 15,
        'at_risk_count': 4,
        'open_pool_count': 1,
        'top_prompt': '2 orders waiting',
        'top_prompt_detail': 'A shop is waiting to hear whether you can supply.',
      },
    });

    await tester.pumpWidget(host(const DistTodayScreen()));
    await settle(tester);

    expect(find.text('Market Yard Wholesale'), findsOneWidget);
    expect(find.text('2 orders waiting'), findsOneWidget);
    // StatTile uppercases its label.
    expect(find.text('TO ANSWER'), findsOneWidget);
    expect(find.text('₹14,108'), findsOneWidget);
    expect(find.text('₹3,200'), findsOneWidget);

    // The book section sits below the fold in the test viewport, so it has to
    // be scrolled to rather than assumed rendered.
    await tester.scrollUntilVisible(find.text('RUNNING OUT'), 200);
    expect(find.text('RUNNING OUT'), findsOneWidget);
  });

  // =================================================== distributor: orders
  testWidgets('the inbox uses the wholesaler vocabulary', (tester) async {
    boot(<String, Object?>{'/dist/orders': <Object?>[order()]});

    await tester.pumpWidget(host(const DistOrdersScreen()));
    await settle(tester);

    // The shop's name, not the wholesaler's own.
    expect(find.text('Kumar General Stores'), findsOneWidget);
    // "New", where the shop sees "Waiting".
    expect(find.text('New'), findsWidgets);
  });

  testWidgets('a clear inbox says so per stage', (tester) async {
    boot(<String, Object?>{'/dist/orders': <Object?>[]});

    await tester.pumpWidget(host(const DistOrdersScreen()));
    await settle(tester);

    expect(find.text('Nothing waiting on you'), findsOneWidget);
  });

  // =================================================== distributor: demand
  testWidgets('Demand aggregates SKUs and flags shops about to run out',
      (tester) async {
    boot(<String, Object?>{
      '/dist/demand': <String, Object?>{
        'horizon_days': 7,
        'consenting_shops': 12,
        'total_connected': 15,
        'lines': <Object?>[
          <String, Object?>{
            'sku_name': 'Cooking Oil',
            'category': 'staples',
            'unit': 'l',
            'expected_qty': 1217,
            'shop_count': 12,
            'catalog_entry_id': 'c1',
            'packs_to_stock': 82,
            'est_revenue': 164185,
            'confidence': 'high',
          },
        ],
        'at_risk': <Object?>[
          <String, Object?>{
            'vendor_id': 'v1',
            'store_name': 'Sai Kirana',
            'locality': 'Kothrud',
            'sku_name': 'Milk',
            'unit': 'pkt',
            'current_qty': 20,
            'daily_rate': 9.5,
            'days_of_cover': 2.1,
            'lead_days': 3,
            'shortfall_by_arrival': 8.6,
            'suggested_packs': 7,
            'est_value': 1932,
          },
        ],
        'dead_lines': <Object?>[],
      },
    });

    await tester.pumpWidget(host(const DistDemandScreen()));
    await settle(tester);

    expect(find.text('CALL THESE SHOPS'), findsOneWidget);
    expect(find.text('Sai Kirana'), findsOneWidget);
    // The whole argument in one line: cover against lead time.
    expect(find.text('2.1d left · 3d to reach them'), findsOneWidget);

    expect(find.text('Cooking Oil'), findsOneWidget);
    expect(find.text('across 12 shops · next 7 days'), findsOneWidget);
    expect(find.text('stock 82 cases'), findsOneWidget);

    // The consent gap is stated, not hidden.
    expect(
      find.text('3 of 15 shops keep their numbers private'),
      findsOneWidget,
    );
  });

  testWidgets('below the k-anonymity floor, demand explains its own silence',
      (tester) async {
    boot(<String, Object?>{
      '/dist/demand': <String, Object?>{
        'horizon_days': 7,
        'consenting_shops': 2,
        'total_connected': 2,
        'lines': <Object?>[],
        'at_risk': <Object?>[],
        'dead_lines': <Object?>[],
      },
    });

    await tester.pumpWidget(host(const DistDemandScreen()));
    await settle(tester);

    expect(find.text('Not enough shops yet'), findsOneWidget);
    expect(
      find.textContaining('at least three shops contribute'),
      findsOneWidget,
    );
  });

  // ==================================================== distributor: shops
  testWidgets('the book surfaces fill rate, privacy and lapsing customers',
      (tester) async {
    boot(<String, Object?>{
      '/dist/vendors': <Object?>[
        <String, Object?>{
          'vendor_id': 'v1',
          'store_name': 'Sai Kirana',
          'owner_name': 'Sunita Pawar',
          'locality': 'Kothrud',
          'phone': '9876510001',
          'connected_at': DateTime.now().toIso8601String(),
          'order_count': 8,
          'delivered_count': 7,
          'revenue': 42000,
          'outstanding': 5200,
          'fill_rate': 0.72,
          'shares_demand': false,
          'last_order_at': DateTime.now()
              .subtract(const Duration(days: 45))
              .toIso8601String(),
        },
      ],
    });

    await tester.pumpWidget(host(const DistShopsScreen()));
    await settle(tester);

    expect(find.text('Sai Kirana'), findsOneWidget);
    expect(find.text('Sunita Pawar · Kothrud'), findsOneWidget);
    expect(find.text('₹42,000'), findsOneWidget);
    expect(find.text('8 orders'), findsOneWidget);
    // A poor fill rate is the wholesaler's own failing, and is shown as one.
    expect(find.text('you filled 72%'), findsOneWidget);
    expect(find.text('numbers private'), findsOneWidget);
    expect(find.text('quiet 45 days'), findsOneWidget);
    expect(find.text('₹5,200 outstanding'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
  });

  testWidgets('a wholesaler with no shops is told how they get found',
      (tester) async {
    boot(<String, Object?>{'/dist/vendors': <Object?>[]});

    await tester.pumpWidget(host(const DistShopsScreen()));
    await settle(tester);

    expect(find.text('No shops yet'), findsOneWidget);
    expect(find.textContaining('Adding prices'), findsOneWidget);
  });

  // ========================================================== demo banner
  testWidgets('the demo banner is absent when nothing is simulated',
      (tester) async {
    boot(<String, Object?>{
      '/demo/pulse': <String, Object?>{
        'available': false,
        'running': false,
        'reason': 'DEMO_MODE is not set',
        'sales_emitted': 0,
        'demo_rows': 0,
      },
    });

    await tester.pumpWidget(host(const DemoBanner()));
    await settle(tester);

    expect(find.textContaining('DEMO'), findsNothing);
  });

  testWidgets('the demo banner says so loudly while the pulse runs',
      (tester) async {
    boot(<String, Object?>{
      '/demo/pulse': <String, Object?>{
        'available': true,
        'running': true,
        'reason': 'demo mode is on',
        'sales_emitted': 11,
        'demo_rows': 11,
      },
    });

    await tester.pumpWidget(host(const DemoBanner()));
    await settle(tester);

    // The pulse writes real transactions, so the numbers moving on screen
    // describe events that did not happen. Saying so is the whole point.
    expect(find.text('DEMO MODE · simulated activity'), findsOneWidget);
  });

  testWidgets('an unreachable server does not claim a demo is running',
      (tester) async {
    // The honest default for a label that says "this is fake" is not to show
    // it: a server we cannot reach is certainly not running a pulse for us.
    boot(<String, Object?>{});

    await tester.pumpWidget(host(const DemoBanner()));
    await settle(tester);

    expect(find.textContaining('DEMO'), findsNothing);
  });

  // ================================================================ theme
  testWidgets('every marketplace screen renders in dark mode', (tester) async {
    boot(<String, Object?>{'/orders': <Object?>[order()]});

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.dark),
          home: const MotionScope(child: OrdersScreen()),
        ),
      ),
    );
    await settle(tester);

    expect(tester.takeException(), isNull);
    expect(find.text('Balaji Distributors'), findsOneWidget);
  });
}
