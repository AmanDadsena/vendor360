import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart' show HeatCell, SupplierPin;

import '../data/api_client.dart';
import '../data/marketplace_models.dart';
import '../data/live_connection.dart';
import '../data/marketplace_repository.dart';
import '../data/models.dart';
import '../data/offline_queue.dart';
import '../data/repository.dart';

/// Wired once at startup in `main.dart`, so every provider below can be
/// synchronous and no screen has to await an initialiser.
final offlineQueueProvider = Provider<OfflineQueue>(
  (ref) => throw UnimplementedError('OfflineQueue must be overridden in main()'),
);

final apiClientProvider = Provider<ApiClient>((ref) {
  final client = ApiClient();
  ref.onDispose(client.close);
  return client;
});

final repositoryProvider = Provider<VendorRepository>(
  (ref) => VendorRepository(
    api: ref.watch(apiClientProvider),
    queue: ref.watch(offlineQueueProvider),
  ),
);

final marketplaceProvider = Provider<MarketplaceRepository>(
  (ref) => MarketplaceRepository(
    api: ref.watch(apiClientProvider),
    queue: ref.watch(offlineQueueProvider),
  ),
);

// ------------------------------------------------------------------- theme
class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;

  void toggle() => state = switch (state) {
        ThemeMode.light => ThemeMode.dark,
        ThemeMode.dark => ThemeMode.light,
        // From "follow the system", the first tap should visibly change
        // something, so it commits to the opposite of what is on screen.
        ThemeMode.system => ThemeMode.dark,
      };
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

// -------------------------------------------------------------------- auth
class SessionState {
  const SessionState({
    this.vendor,
    this.distributor,
    this.loading = false,
    this.error,
  });

  final Vendor? vendor;
  final Distributor? distributor;
  final bool loading;
  final String? error;

  bool get isSignedIn => vendor != null || distributor != null;

  /// Which shell to build. Null while signed out.
  Principal? get principal => switch ((vendor, distributor)) {
        (_, final Distributor _) => Principal.distributor,
        (final Vendor _, _) => Principal.vendor,
        _ => null,
      };

  bool get isDistributor => distributor != null;

  /// What to greet them by, whichever side they are on.
  String get displayName =>
      distributor?.businessName ?? vendor?.storeName ?? '';

  SessionState copyWith({
    Vendor? vendor,
    Distributor? distributor,
    bool? loading,
    String? error,
  }) =>
      SessionState(
        vendor: vendor ?? this.vendor,
        distributor: distributor ?? this.distributor,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  VendorRepository get _repo => ref.read(repositoryProvider);
  MarketplaceRepository get _market => ref.read(marketplaceProvider);

  /// Restore a saved session on launch. Returns false if they must sign in
  /// again.
  ///
  /// The stored token does not say which role it carries, so this tries the
  /// vendor route first and falls back to the distributor one. Two requests
  /// in the worst case, on a path that runs once per launch — cheaper than
  /// persisting a role that could drift out of step with the token.
  Future<bool> restore() async {
    if (!await _repo.restoreSession()) {
      return _restoreDistributor();
    }
    try {
      final snapshot = await _repo.dashboard();
      state = SessionState(vendor: snapshot.vendor);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _restoreDistributor() async {
    final token = ref.read(offlineQueueProvider).token;
    if (token == null) return false;

    ref.read(apiClientProvider).setToken(token);
    try {
      state = SessionState(distributor: await _market.distributorMe());
      return true;
    } catch (_) {
      ref.read(apiClientProvider).setToken(null);
      await ref.read(offlineQueueProvider).setToken(null);
      return false;
    }
  }

  Future<String?> requestOtp(String phone) async {
    state = state.copyWith(loading: true);
    try {
      final code = await _repo.requestOtp(phone);
      state = state.copyWith(loading: false);
      return code;
    } catch (error) {
      state = SessionState(loading: false, error: _friendly(error));
      return null;
    }
  }

  /// Verify an OTP and adopt whichever role the server resolved.
  ///
  /// `intent` only matters for a number the server has never seen. An
  /// existing account's role belongs to the account, not to what the sign-in
  /// form happened to say — so someone tapping the wrong tile is signed into
  /// the account they already have rather than given a confusing second one.
  Future<bool> verify({
    required String phone,
    required String code,
    required AppLanguage language,
    Principal intent = Principal.vendor,
    String? name,
    String? storeName,
    String? businessName,
    String? locality,
  }) async {
    state = state.copyWith(loading: true);
    try {
      final result = await _market.verify(
        phone: phone,
        code: code,
        language: language,
        intent: intent,
        name: name,
        storeName: storeName,
        businessName: businessName,
        locality: locality,
      );

      state = switch (result.principal) {
        Principal.distributor =>
          SessionState(distributor: Distributor.fromJson(result.payload)),
        Principal.vendor => SessionState(vendor: vendorFromJson(result.payload)),
      };
      return true;
    } catch (error) {
      state = SessionState(loading: false, error: _friendly(error));
      return false;
    }
  }

  Future<void> signOut() async {
    await _repo.signOut();
    state = const SessionState();
  }

  /// Turns transport failures into something a vendor can act on. "Connection
  /// refused" tells them nothing; "cannot reach the server" tells them to
  /// check their signal.
  String _friendly(Object error) {
    if (error is ApiException) return error.message;
    return 'Cannot reach the server. Check your connection and try again.';
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

// --------------------------------------------------------------- sync state
/// Pending-write count, so the sync badge can be driven from anywhere.
class SyncNotifier extends Notifier<({int queued, bool syncing})> {
  @override
  ({int queued, bool syncing}) build() =>
      (queued: ref.read(offlineQueueProvider).depth, syncing: false);

  void refresh() => state =
      (queued: ref.read(offlineQueueProvider).depth, syncing: false);

  Future<SyncOutcome?> flush() async {
    final queue = ref.read(offlineQueueProvider);
    if (queue.depth == 0) return null;

    state = (queued: queue.depth, syncing: true);
    final outcome = await ref.read(repositoryProvider).flushQueue();
    state = (queued: queue.depth, syncing: false);
    return outcome;
  }
}

final syncProvider =
    NotifierProvider<SyncNotifier, ({int queued, bool syncing})>(SyncNotifier.new);

// ------------------------------------------------------------------- data
final dashboardProvider = FutureProvider.autoDispose<DashboardSnapshot>(
  (ref) => ref.watch(repositoryProvider).dashboard(),
);

/// Riverpod 3 removed StateProvider, so simple mutable UI state is a Notifier.
class _NullableString extends Notifier<String?> {
  @override
  String? build() => null;
  set value(String? v) => state = v;
}

class _Flag extends Notifier<bool> {
  @override
  bool build() => false;
  set value(bool v) => state = v;
}

final inventoryFilterProvider =
    NotifierProvider<_NullableString, String?>(_NullableString.new);
final inventorySearchQueryProvider =
    NotifierProvider<_NullableString, String?>(_NullableString.new);
final lowOnlyProvider = NotifierProvider<_Flag, bool>(_Flag.new);

final inventoryProvider = FutureProvider.autoDispose<List<InventoryItem>>(
  (ref) => ref.watch(repositoryProvider).inventory(
        category: ref.watch(inventoryFilterProvider),
        lowOnly: ref.watch(lowOnlyProvider),
      ),
);

final filteredInventoryProvider =
    Provider.autoDispose<AsyncValue<List<InventoryItem>>>((ref) {
  final asyncItems = ref.watch(inventoryProvider);
  final query = ref.watch(inventorySearchQueryProvider)?.trim().toLowerCase();
  if (query == null || query.isEmpty) return asyncItems;
  return asyncItems.whenData(
    (items) => items.where((item) {
      return item.skuName.toLowerCase().contains(query) ||
          item.category.toLowerCase().contains(query);
    }).toList(),
  );
});

final forecastsProvider = FutureProvider.autoDispose<List<Forecast>>(
  (ref) => ref.watch(repositoryProvider).forecasts(),
);

final healthScoreProvider = FutureProvider.autoDispose<HealthScore>(
  (ref) => ref.watch(repositoryProvider).healthScore(),
);

final consentsProvider = FutureProvider.autoDispose<List<ScoreConsent>>(
  (ref) => ref.watch(repositoryProvider).consents(),
);

final expiryProvider = FutureProvider.autoDispose<List<ExpiryEntry>>(
  (ref) => ref.watch(repositoryProvider).expiring(withinDays: 7),
);

final poolsProvider = FutureProvider.autoDispose<List<BargainPool>>(
  (ref) => ref.watch(repositoryProvider).pools(),
);

final heatmapCategoryProvider =
    NotifierProvider<_NullableString, String?>(_NullableString.new);

final heatmapProvider = FutureProvider.autoDispose<
    ({List<HeatCell> cells, List<SupplierPin> suppliers, int suppressed})>(
  (ref) => ref
      .watch(repositoryProvider)
      .heatmap(category: ref.watch(heatmapCategoryProvider)),
);

final accuracyProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(repositoryProvider).forecastAccuracy(),
);

final signalsProvider = FutureProvider.autoDispose<Map<String, dynamic>>(
  (ref) => ref.watch(repositoryProvider).signals(),
);

/// The language that governs both speech recognition and on-screen strings.
///
/// Seeded from the signed-in vendor but independently settable, because
/// TC-V05 requires switching mid-session to take effect on the next capture
/// without waiting for a round trip to update the profile.
class LanguageNotifier extends Notifier<AppLanguage> {
  @override
  AppLanguage build() =>
      ref.watch(sessionProvider).vendor?.language ?? AppLanguage.hindi;

  set value(AppLanguage language) => state = language;
}

final languageProvider =
    NotifierProvider<LanguageNotifier, AppLanguage>(LanguageNotifier.new);

// ========================================================== marketplace
// ----------------------------------------------------------- vendor side
final distributorsProvider = FutureProvider.autoDispose<List<SupplierCard>>(
  (ref) => ref.watch(marketplaceProvider).distributors(),
);

final connectionsProvider = FutureProvider.autoDispose<List<Connection>>(
  (ref) => ref.watch(marketplaceProvider).connections(),
);

/// Sourcing for one item. Family-keyed so opening the sheet for a second item
/// does not serve the first one's ranking from cache.
final sourcingProvider =
    FutureProvider.autoDispose.family<Sourcing, String>(
  (ref, itemId) => ref.watch(marketplaceProvider).sourcing(itemId),
);

class OrderFilter extends Notifier<String?> {
  @override
  String? build() => null;
  set value(String? v) => state = v;
}

final orderFilterProvider =
    NotifierProvider<OrderFilter, String?>(OrderFilter.new);

final ordersProvider = FutureProvider.autoDispose<List<PurchaseOrder>>(
  (ref) => ref
      .watch(marketplaceProvider)
      .orders(status: ref.watch(orderFilterProvider)),
);

final orderDetailProvider =
    FutureProvider.autoDispose.family<PurchaseOrder, String>(
  (ref, id) => ref.watch(marketplaceProvider).order(id),
);

final ledgerProvider = FutureProvider.autoDispose<Ledger>(
  (ref) => ref.watch(marketplaceProvider).ledger(),
);

/// The order being assembled. In memory only — a cart that survived a
/// relaunch would quietly re-order yesterday's shortage.
class CartNotifier extends Notifier<List<CartLine>> {
  @override
  List<CartLine> build() => <CartLine>[];

  /// The cart holds one supplier at a time. Adding from a second wholesaler
  /// replaces it rather than silently splitting into two orders — one basket
  /// that turns into two deliveries is a worse surprise than being told.
  bool wouldReplace(String supplierId) =>
      state.isNotEmpty && state.first.option.supplierId != supplierId;

  void add(CartLine line) {
    if (wouldReplace(line.option.supplierId)) {
      state = <CartLine>[line];
      return;
    }

    final existing = state.indexWhere(
      (l) => l.option.catalogEntryId == line.option.catalogEntryId,
    );
    if (existing >= 0) {
      final merged = <CartLine>[...state];
      merged[existing].packs += line.packs;
      state = merged;
    } else {
      state = <CartLine>[...state, line];
    }
  }

  void setPacks(String catalogEntryId, int packs) {
    if (packs <= 0) return remove(catalogEntryId);
    state = <CartLine>[
      for (final l in state)
        if (l.option.catalogEntryId == catalogEntryId)
          (l..packs = packs)
        else
          l,
    ];
  }

  void remove(String catalogEntryId) => state = <CartLine>[
        for (final l in state)
          if (l.option.catalogEntryId != catalogEntryId) l,
      ];

  void clear() => state = <CartLine>[];

  double get total => state.fold(0, (sum, l) => sum + l.total);
  String? get supplierId => state.isEmpty ? null : state.first.option.supplierId;
  String? get supplierName =>
      state.isEmpty ? null : state.first.option.supplierName;
}

final cartProvider =
    NotifierProvider<CartNotifier, List<CartLine>>(CartNotifier.new);

final masterCatalogProvider = FutureProvider.autoDispose
    .family<List<MasterSku>, String>(
  (ref, categories) => ref.watch(marketplaceProvider).masterCatalog(
        categories: categories.isEmpty ? const [] : categories.split(','),
      ),
);

// ------------------------------------------------------ distributor side
final distSummaryProvider = FutureProvider.autoDispose<DistributorSummary>(
  (ref) => ref.watch(marketplaceProvider).summary(),
);

/// The wholesaler's inbox opens on what needs answering, not on everything.
/// An inbox that opens on history is one nobody clears.
class DistInboxFilter extends Notifier<String?> {
  @override
  String? build() => 'placed';
  set value(String? v) => state = v;
}

final distInboxFilterProvider =
    NotifierProvider<DistInboxFilter, String?>(DistInboxFilter.new);

final distInboxProvider = FutureProvider.autoDispose<List<PurchaseOrder>>(
  (ref) => ref
      .watch(marketplaceProvider)
      .inbox(status: ref.watch(distInboxFilterProvider)),
);

final distOrderProvider =
    FutureProvider.autoDispose.family<PurchaseOrder, String>(
  (ref, id) => ref.watch(marketplaceProvider).inboxOrder(id),
);

final distCatalogProvider = FutureProvider.autoDispose<List<CatalogEntry>>(
  (ref) => ref.watch(marketplaceProvider).catalog(),
);

class HorizonNotifier extends Notifier<int> {
  @override
  int build() => 7;
  set value(int v) => state = v;
}

final demandHorizonProvider =
    NotifierProvider<HorizonNotifier, int>(HorizonNotifier.new);

final distDemandProvider = FutureProvider.autoDispose<Demand>(
  (ref) => ref
      .watch(marketplaceProvider)
      .demand(horizonDays: ref.watch(demandHorizonProvider)),
);

final distBookProvider = FutureProvider.autoDispose<List<BookEntry>>(
  (ref) => ref.watch(marketplaceProvider).book(),
);

final distLedgerProvider = FutureProvider.autoDispose<Ledger>(
  (ref) => ref.watch(marketplaceProvider).receivables(),
);

final distPoolsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>(
  (ref) => ref.watch(marketplaceProvider).openPools(),
);

final distDispatchProvider = FutureProvider.autoDispose<Dispatch>(
  (ref) => ref.watch(marketplaceProvider).dispatch(),
);

/// Whether the server is manufacturing activity.
///
/// Polled rather than pushed: it changes when someone starts or stops the
/// pulse, which is a human action at a keyboard and not something worth a
/// socket message. Re-read on every live event so the banner appears within
/// one tick of the pulse starting.
final demoPulseProvider = FutureProvider<DemoStatus>(
  (ref) => ref.watch(marketplaceProvider).demoStatus(),
);

// ============================================================ live channel
final liveConnectionProvider = Provider<LiveConnection>((ref) {
  final connection = LiveConnection(baseUrl: kApiBase);
  ref.onDispose(connection.dispose);
  return connection;
});

/// Opens the socket while signed in, closes it on sign-out.
///
/// Driven off the session rather than started by a screen, so liveness does
/// not depend on which tab happens to be mounted — and so a sign-out cannot
/// leave a socket open under the previous principal's token.
final liveLifecycleProvider = Provider<void>((ref) {
  final connection = ref.watch(liveConnectionProvider);
  final signedIn = ref.watch(sessionProvider).isSignedIn;
  final token = ref.watch(offlineQueueProvider).token;

  if (signedIn && token != null) {
    connection.start(token);
  } else {
    connection.stop();
  }
});

final liveStatusProvider = StreamProvider<LiveStatus>((ref) {
  ref.watch(liveLifecycleProvider);
  final connection = ref.watch(liveConnectionProvider);
  return connection.statusChanges.distinct();
});

final liveEventsProvider = StreamProvider<LiveEvent>((ref) {
  ref.watch(liveLifecycleProvider);
  return ref.watch(liveConnectionProvider).events;
});

// ------------------------------------------------------------------ alerts
final alertsProvider = FutureProvider.autoDispose<AlertFeed>(
  (ref) => ref.watch(marketplaceProvider).alerts(
        distributor: ref.watch(sessionProvider).isDistributor,
      ),
);

/// Re-reads whatever an event touched.
///
/// The single place the socket connects to the rest of the app. An event says
/// "something changed"; this decides what to re-read; the screen then loads
/// through its ordinary path. That indirection is what stops the socket
/// becoming a second source of truth — there is exactly one way data arrives,
/// and a dead socket only means nobody is prompting it.
final liveRefreshProvider = Provider<void>((ref) {
  ref.listen(liveEventsProvider, (_, next) {
    final event = next.value;
    if (event == null) return;

    // An alert accompanies every detection, so the feed is always stale after
    // one — and the unread badge is what the user notices first.
    ref.invalidate(alertsProvider);

    // Cheap, and it means the DEMO label appears within a tick of the pulse
    // being started rather than on the next cold load.
    ref.invalidate(demoPulseProvider);

    switch (event.type) {
      case 'heatmap':
        ref.invalidate(heatmapProvider);
      case 'stockout':
      case 'anomaly':
        ref
          ..invalidate(inventoryProvider)
          ..invalidate(dashboardProvider)
          ..invalidate(distDemandProvider)
          ..invalidate(distSummaryProvider);
      case 'surge':
        ref
          ..invalidate(poolsProvider)
          ..invalidate(distPoolsProvider);
      case 'order':
        ref
          ..invalidate(ordersProvider)
          ..invalidate(distInboxProvider)
          ..invalidate(distSummaryProvider);
    }
  });
});
