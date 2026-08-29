import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

import 'app/providers.dart';
import 'app/router.dart';
import 'data/offline_queue.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Opened before `runApp` so every provider below can read the queue
  // synchronously — an offline-first app should not render a loading screen
  // while it works out whether it has local data.
  final queue = await OfflineQueue.open();

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
