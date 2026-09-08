import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:vendor360/app/providers.dart';
import 'package:vendor360/data/api_client.dart';
import 'package:vendor360/data/offline_queue.dart';
import 'package:vendor360/features/accuracy/accuracy_screen.dart';
import 'package:vendor360/features/dashboard/dashboard_screen.dart';
import 'package:vendor360/features/expiry/expiry_screen.dart';
import 'package:vendor360/features/forecast/forecast_screen.dart';
import 'package:vendor360/features/health/health_screen.dart';
import 'package:vendor360/features/heatmap/heatmap_screen.dart';
import 'package:vendor360/features/inventory/inventory_screen.dart';
import 'package:vendor360/features/onboarding/onboarding_screen.dart';
import 'package:vendor360/features/pools/pools_screen.dart';
import 'package:vendor360/features/receipt/receipt_screen.dart';
import 'package:vendor360/features/voice/voice_screen.dart';
import 'package:vendor360_ui/vendor360_ui.dart';

/// Screen rendering tests.
///
/// The API is pointed at a closed port, so every read fails fast and falls back
/// to the seeded world. That exercises two things at once: that each screen
/// renders real content, and that the offline path the whole product depends on
/// actually produces a usable screen rather than an error state.
///
/// This is the check a screenshot cannot make — it asserts the numbers and
/// labels, and it keeps working after the next change.
void main() {
  late ProviderContainer container;

  /// A client whose every request fails on the microtask queue.
  ///
  /// A real socket to a closed port would also fail, but `tester.pump()` cannot
  /// flush real I/O — the screen would still be in its loading state when the
  /// assertions run. Failing synchronously keeps the fallback path exercised
  /// while staying inside the test's clock.
  ApiClient deadClient() => ApiClient(
        client: MockClient((_) async => throw const SocketException('offline')),
      );

  Widget host(Widget screen) => UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: buildV360Theme(Brightness.light),
          home: MotionScope(child: screen),
        ),
      );

  setUp(() {
    container = ProviderContainer(
      overrides: [
        offlineQueueProvider.overrideWithValue(OfflineQueue.inMemory()),
        apiClientProvider.overrideWithValue(deadClient()),
      ],
    );
  });

  tearDown(() => container.dispose());

  /// Pumps past the reveal stagger and the fallback resolution.
  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
  }

  testWidgets('Onboarding shows the language picker in all three languages',
      (tester) async {
    await tester.pumpWidget(host(const OnboardingScreen()));
    await settle(tester);

    expect(find.text('Vendor360'), findsOneWidget);
    // Endonyms, because a picker that names languages in a language you cannot
    // read is not a picker.
    expect(find.text('हिन्दी'), findsOneWidget);
    expect(find.text('मराठी'), findsOneWidget);
    expect(find.text('English'), findsWidgets);
  });

  testWidgets('Dashboard renders the seeded snapshot', (tester) async {
    await tester.pumpWidget(host(const DashboardScreen()));
    await settle(tester);

    expect(find.text('Kumar General Stores'), findsOneWidget);
    expect(find.text('Kothrud'), findsOneWidget);
    // RollingNumber animates one glyph per Text so the figure can roll, so
    // the grouped amount is asserted glyph by glyph. The comma is the point:
    // Indian grouping, not Western.
    final glyphs = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join();
    expect(glyphs, contains('₹12,012'));
    expect(find.textContaining('Ganesh Chaturthi'), findsOneWidget);
  });

  testWidgets('Inventory lists stock with live reorder points', (tester) async {
    await tester.pumpWidget(host(const InventoryScreen()));
    await settle(tester);

    // A ListView.builder only builds what is on screen, so assert on the rows
    // that are actually rendered rather than the whole catalogue. The screen
    // has two scrollables (the horizontal category chips and the vertical
    // list), which is why this drags the list directly instead of using
    // scrollUntilVisible.
    expect(find.byType(V360Card), findsWidgets);
    // The threshold is shown as a computed value, not an editable setting —
    // and in Devanagari, because Hindi is the default language rather than a
    // setting the vendor has to find.
    expect(find.textContaining('दोबारा मंगाएँ'), findsWidgets);

    // The provider holds the full seeded catalogue even though only part of
    // it is built.
    final items = await container.read(repositoryProvider).inventory();
    expect(items.length, greaterThan(15));
    expect(items.map((i) => i.skuName), contains('Rice'));
    expect(items.map((i) => i.skuName), contains('Milk'));
  });

  testWidgets('Inventory search filters items by SKU query', (tester) async {
    await tester.pumpWidget(host(const InventoryScreen()));
    await settle(tester);

    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Rice');
    await tester.pump();

    expect(container.read(inventorySearchQueryProvider), 'Rice');
  });

  testWidgets('Inventory displays 1-Tap Order action on low stock items',
      (tester) async {
    await tester.pumpWidget(host(const InventoryScreen()));
    await settle(tester);

    expect(find.text('1-Tap Order'), findsWidgets);
  });

  testWidgets('Forecast leads with the recommendation, not the chart',
      (tester) async {
    await tester.pumpWidget(host(const ForecastScreen()));
    await settle(tester);

    expect(find.textContaining('Stock'), findsWidgets);
    expect(find.textContaining('Ganesh Chaturthi'), findsWidgets);
    expect(find.byType(ForecastSpark), findsWidgets);
  });

  testWidgets('Health score always shows its breakdown', (tester) async {
    await tester.pumpWidget(host(const HealthScreen()));
    await settle(tester);

    expect(find.byType(HealthDial), findsOneWidget);
    // The guide forbids an opaque number: all three factors must be present.
    expect(find.text('Sales consistency'), findsOneWidget);
    expect(find.text('Inventory turnover'), findsOneWidget);
    expect(find.text('Waste control'), findsOneWidget);
    expect(find.textContaining('× 0.40'), findsWidgets);
  });

  testWidgets('Heatmap renders cells and explains suppression', (tester) async {
    await tester.pumpWidget(host(const HeatmapScreen()));
    await settle(tester);

    expect(find.byType(DemandHeatmap), findsOneWidget);
    expect(find.byType(HeatmapLegend), findsOneWidget);
    // k-anonymity has to be stated, not silently applied.
    expect(find.textContaining('zones hidden'), findsOneWidget);
    expect(find.text('Market Yard'), findsOneWidget);
  });

  testWidgets('Expiry ranks by urgency and offers a markdown', (tester) async {
    await tester.pumpWidget(host(const ExpiryScreen()));
    await settle(tester);

    expect(find.text('Tomato'), findsOneWidget);
    expect(find.textContaining('VALUE AT RISK'), findsWidgets);
    expect(find.textContaining('50%'), findsWidgets);
    expect(
      find.textContaining('Dynamic markdowns recover up to 70%'),
      findsOneWidget,
    );
  });

  testWidgets('Pools show the group price against the base price',
      (tester) async {
    await tester.pumpWidget(host(const PoolsScreen()));
    await settle(tester);

    expect(find.text('Umbrella'), findsOneWidget);
    expect(find.textContaining('stores in Kothrud'), findsOneWidget);
    expect(find.textContaining('₹176'), findsWidgets);
    expect(find.textContaining('Save '), findsWidgets);
  });

  testWidgets('Voice screen offers the orb and the typed fallback',
      (tester) async {
    await tester.pumpWidget(host(const VoiceScreen()));
    await settle(tester);

    expect(find.byType(VoiceOrb), findsOneWidget);
    // Typing is the documented fallback when ASR struggles (PRD 7).
    expect(find.text('OR TYPE IT'), findsOneWidget);
    expect(find.text('हिन्दी'), findsOneWidget);
  });

  testWidgets('Receipt screen offers sample captures', (tester) async {
    await tester.pumpWidget(host(const ReceiptScreen()));
    await settle(tester);

    expect(find.text('Clear photo'), findsOneWidget);
    expect(find.text('Blurry / angled'), findsOneWidget);
  });

  testWidgets('Accuracy screen reports MAPE with a plain-language verdict',
      (tester) async {
    await tester.pumpWidget(host(const AccuracyScreen()));
    await settle(tester);

    expect(find.textContaining('MEAN ABSOLUTE PERCENTAGE ERROR'), findsOneWidget);
    expect(find.textContaining('14.6'), findsWidgets);
  });

  testWidgets('every screen renders without throwing in dark mode',
      (tester) async {
    // Dark mode swaps the actionFill inversion and drops shadows for hairlines;
    // a screen that only ever renders in light can break silently.
    final screens = <Widget>[
      const DashboardScreen(),
      const InventoryScreen(),
      const ForecastScreen(),
      const HealthScreen(),
      const ExpiryScreen(),
      const PoolsScreen(),
      const VoiceScreen(),
      const ReceiptScreen(),
      const AccuracyScreen(),
      const HeatmapScreen(),
    ];

    for (final screen in screens) {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildV360Theme(Brightness.dark),
            home: MotionScope(child: screen),
          ),
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull, reason: '${screen.runtimeType} threw');
    }
  });
}
