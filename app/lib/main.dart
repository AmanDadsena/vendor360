import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'data/offline_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before `runApp` so every provider can read the queue synchronously —
  // an offline-first app should not render a loading screen while it works out
  // whether it has local data.
  //
  // But it must not *block* on storage either. `getInstance()` can hang or
  // throw when a browser blocks site data, when the web plugin fails to
  // register, or on a device with a corrupt preferences store — and awaiting
  // it unguarded means `runApp` never runs and the vendor sees a blank screen
  // with no error. Storage being unavailable should cost durability, not the
  // whole app: the same rule `withFallback` applies to reads, applied to the
  // one thing that runs before anything else can.
  final queue = await OfflineQueue.open()
      .timeout(const Duration(seconds: 5))
      .catchError((Object error, StackTrace _) {
    debugPrint('[startup] local storage unavailable ($error) — running with '
        'an in-memory queue; writes will not survive a restart');
    // Keeps every flow working; only durability is lost, and the queue reports
    // `isDurable == false` so the app can say so rather than implying work is
    // safely stored.
    return OfflineQueue.inMemory();
  });

  runApp(
    ProviderScope(
      overrides: [offlineQueueProvider.overrideWithValue(queue)],
      child: const Vendor360App(),
    ),
  );
}

class Vendor360App extends ConsumerWidget {
  const Vendor360App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'Vendor360',
      debugShowCheckedModeBanner: false,
      theme: buildV360Theme(Brightness.light),
      darkTheme: buildV360Theme(Brightness.dark),
      themeMode: ref.watch(themeModeProvider),
      routerConfig: router,
      builder: (context, child) {
        // MotionScope sits above everything, so honouring the platform's
        // reduce-motion setting is one switch rather than a per-widget
        // obligation.
        return MotionScope(child: child ?? const SizedBox.shrink());
      },
    );
  }
}
