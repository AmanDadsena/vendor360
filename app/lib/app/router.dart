import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/accuracy/accuracy_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/expiry/expiry_screen.dart';
import '../features/forecast/forecast_screen.dart';
import '../features/health/health_screen.dart';
import '../features/heatmap/heatmap_screen.dart';
import '../features/inventory/inventory_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/pools/pools_screen.dart';
import '../features/receipt/receipt_screen.dart';
import '../features/voice/voice_screen.dart';
import 'providers.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),

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
    ],

    // Auth gate. Redirect returns null when the current location is already
    // correct, which is what stops go_router looping between the two states.
    redirect: (context, state) {
      final signedIn = ref.read(sessionProvider).isSignedIn;
      final atOnboarding = state.matchedLocation == '/onboarding';

      if (!signedIn && !atOnboarding) return '/onboarding';
      if (signedIn && atOnboarding) return '/';
      return null;
    },

    refreshListenable: _SessionListenable(ref),
  );
});

/// Re-runs the redirect when sign-in state changes.
///
/// go_router only evaluates `redirect` on navigation, so without this a
/// successful OTP verification would leave the vendor sitting on the
/// onboarding screen until they happened to navigate.
class _SessionListenable extends ChangeNotifier {
  _SessionListenable(Ref ref) {
    ref.listen(sessionProvider, (previous, next) {
      if (previous?.isSignedIn != next.isSignedIn) notifyListeners();
    });
  }
}
