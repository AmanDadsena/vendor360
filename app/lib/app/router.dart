import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accuracy/accuracy_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/dist/dist_catalog_screen.dart';
import '../features/dist/dist_demand_screen.dart';
import '../features/dist/dist_order_detail_screen.dart';
import '../features/dist/dist_orders_screen.dart';
import '../features/dist/dist_shops_screen.dart';
import '../features/dist/dist_today_screen.dart';
import '../features/distributors/distributors_screen.dart';
import '../features/expiry/expiry_screen.dart';
import '../features/forecast/forecast_screen.dart';
import '../features/health/health_screen.dart';
import '../features/heatmap/heatmap_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/onboarding/setup_flow_screen.dart';
import '../features/orders/cart_screen.dart';
import '../features/orders/order_detail_screen.dart';
import '../features/orders/orders_screen.dart';
import '../features/pools/pools_screen.dart';
import '../features/receipt/receipt_screen.dart';
import '../features/voice/voice_screen.dart';
import 'dist_shell.dart';
import 'providers.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/setup', builder: (_, __) => const SetupFlowScreen()),

      // ------------------------------------------------------- vendor shell
      // The five bottom-nav destinations live inside a shell so the nav bar
      // and the sync badge persist across them rather than rebuilding on every
      // navigation.
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
              path: '/',
              builder: (_, __) => const DashboardScreen(),
              routes: <RouteBase>[
                GoRoute(path: 'receipt', builder: (_, __) => const ReceiptScreen()),
                GoRoute(path: 'expiry', builder: (_, __) => const ExpiryScreen()),
                GoRoute(path: 'heatmap', builder: (_, __) => const HeatmapScreen()),
                GoRoute(path: 'pools', builder: (_, __) => const PoolsScreen()),
                GoRoute(path: 'accuracy', builder: (_, __) => const AccuracyScreen()),
                GoRoute(
                  path: 'distributors',
                  builder: (_, __) => const DistributorsScreen(),
                ),
                GoRoute(
                  path: 'orders',
                  builder: (_, __) => const OrdersScreen(),
                  routes: <RouteBase>[
                    GoRoute(
                      path: ':id',
                      builder: (_, state) =>
                          OrderDetailScreen(orderId: state.pathParameters['id']!),
                    ),
                  ],
                ),
                GoRoute(path: 'cart', builder: (_, __) => const CartScreen()),
              ],
            ),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/inventory', builder: (_, __) => const InventoryScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/voice', builder: (_, __) => const VoiceScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/forecast', builder: (_, __) => const ForecastScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/health', builder: (_, __) => const HealthScreen()),
          ]),
        ],
      ),

      // -------------------------------------------------- distributor shell
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            DistShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/dist', builder: (_, __) => const DistTodayScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
              path: '/dist/orders',
              builder: (_, __) => const DistOrdersScreen(),
              routes: <RouteBase>[
                GoRoute(
                  path: ':id',
                  builder: (_, state) => DistOrderDetailScreen(
                    orderId: state.pathParameters['id']!,
                  ),
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/dist/demand', builder: (_, __) => const DistDemandScreen()),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(
              path: '/dist/catalog',
              builder: (_, __) => const DistCatalogScreen(),
            ),
          ]),
          StatefulShellBranch(routes: <RouteBase>[
            GoRoute(path: '/dist/shops', builder: (_, __) => const DistShopsScreen()),
          ]),
        ],
      ),
    ],

    // Auth gate, now three-state rather than two: signed out, signed in as a
    // shop, signed in as a wholesaler. Returning null when the location is
    // already correct is what stops go_router looping between them.
    redirect: (context, state) {
      final session = ref.read(sessionProvider);
      final location = state.matchedLocation;

      // `/setup` needs an account — it writes inventory — so it is not a
      // signed-out destination even though it is part of getting started.
      if (!session.isSignedIn) {
        return location == '/onboarding' ? null : '/onboarding';
      }

      final inDistArea = location.startsWith('/dist');

      // A wholesaler who lands on a vendor route — from a stale deep link, or
      // by signing in on a screen the other role was last using — is moved to
      // their own console rather than shown an empty shop.
      if (session.isDistributor) return inDistArea ? null : '/dist';
      if (inDistArea) return '/';

      // A signed-in shop stays out of sign-in, but `/setup` is theirs.
      return location == '/onboarding' ? '/' : null;
    },

    refreshListenable: _SessionListenable(ref),
  );
});

/// Re-runs the redirect when sign-in state changes.
///
/// go_router only evaluates `redirect` on navigation, so without this a
/// successful OTP verification would leave the user sitting on the onboarding
/// screen until they happened to navigate. The role is part of the trigger
/// too: switching accounts has to move the shell, not just the data.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (previous, next) {
      final changed = previous?.isSignedIn != next.isSignedIn ||
          previous?.principal != next.principal;
      if (changed) notifyListeners();
    });
  }
}
