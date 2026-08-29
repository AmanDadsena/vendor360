import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:vendor360_core/vendor360_core.dart';
import 'package:vendor360_ui/vendor360_ui.dart' show HeatCell, SupplierPin;

import '../data/api_client.dart';
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
  const SessionState({this.vendor, this.loading = false, this.error});

  final Vendor? vendor;
  final bool loading;
  final String? error;

  bool get isSignedIn => vendor != null;

  SessionState copyWith({Vendor? vendor, bool? loading, String? error}) =>
      SessionState(
        vendor: vendor ?? this.vendor,
        loading: loading ?? this.loading,
        error: error,
      );
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() => const SessionState();

  VendorRepository get _repo => ref.read(repositoryProvider);

  /// Restore a saved session on launch. Returns false if the vendor must
  /// sign in again.
  Future<bool> restore() async {
    if (!await _repo.restoreSession()) return false;
    try {
      final snapshot = await _repo.dashboard();
      state = SessionState(vendor: snapshot.vendor);
      return true;
    } catch (_) {
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

  Future<bool> verify({
    required String phone,
    required String code,
    required AppLanguage language,
  }) async {
    state = state.copyWith(loading: true);
    try {
      final vendor = await _repo.verifyOtp(
        phone: phone,
        code: code,
        language: language.code,
      );
      state = SessionState(vendor: vendor);
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
final lowOnlyProvider = NotifierProvider<_Flag, bool>(_Flag.new);

final inventoryProvider = FutureProvider.autoDispose<List<InventoryItem>>(
  (ref) => ref.watch(repositoryProvider).inventory(
        category: ref.watch(inventoryFilterProvider),
        lowOnly: ref.watch(lowOnlyProvider),
      ),
);

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
