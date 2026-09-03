import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One queued vendor action awaiting sync.
///
/// `clientEventId` is minted on the device and is the whole idempotency story:
/// a batch interrupted mid-flight is retried whole, and the server recognises
/// events it has already applied instead of applying them twice (TC-S03).
///
/// `localSeq` is monotonic per device, so the server can replay a batch in the
/// order the vendor actually performed the actions rather than the order the
/// network happened to deliver them.
class QueuedEvent {
  QueuedEvent({
    required this.clientEventId,
    required this.localSeq,
    required this.kind,
    required this.payload,
    required this.clientTs,
    this.attempts = 0,
    this.lastError,
  });

  final String clientEventId;
  final int localSeq;
  final String kind;
  final Map<String, dynamic> payload;
  final DateTime clientTs;

  int attempts;
  String? lastError;

  Map<String, dynamic> toWire() => <String, dynamic>{
        'client_event_id': clientEventId,
        'local_seq': localSeq,
        'kind': kind,
        'client_ts': clientTs.toUtc().toIso8601String(),
        'payload': payload,
      };

  Map<String, dynamic> toJson() => <String, dynamic>{
        ...toWire(),
        'attempts': attempts,
        'last_error': lastError,
      };

  factory QueuedEvent.fromJson(Map<String, dynamic> json) => QueuedEvent(
        clientEventId: json['client_event_id'] as String,
        localSeq: json['local_seq'] as int,
        kind: json['kind'] as String,
        payload: Map<String, dynamic>.from(json['payload'] as Map),
        clientTs: DateTime.parse(json['client_ts'] as String),
        attempts: (json['attempts'] as int?) ?? 0,
        lastError: json['last_error'] as String?,
      );
}

/// The small slice of key-value storage the queue actually needs.
///
/// Extracted as an interface for two reasons: it lets the app fall back to an
/// in-memory store when the platform's storage is unavailable rather than
/// failing to start, and it lets the queue be tested without mocking a plugin.
abstract interface class KeyValueStore {
  String? getString(String key);
  int? getInt(String key);
  List<String>? getStringList(String key);

  Future<void> setString(String key, String value);
  Future<void> setInt(String key, int value);
  Future<void> setStringList(String key, List<String> value);
  Future<void> remove(String key);

  /// False when writes will not survive a restart, so the UI can say so
  /// instead of implying work is safely stored.
  bool get isDurable;
}

class _PrefsStore implements KeyValueStore {
  _PrefsStore(this._prefs);

  final SharedPreferences _prefs;

  @override
  bool get isDurable => true;

  @override
  String? getString(String key) => _prefs.getString(key);
  @override
  int? getInt(String key) => _prefs.getInt(key);
  @override
  List<String>? getStringList(String key) => _prefs.getStringList(key);

  @override
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  @override
  Future<void> setInt(String key, int value) => _prefs.setInt(key, value);
  @override
  Future<void> setStringList(String key, List<String> value) =>
      _prefs.setStringList(key, value);
  @override
  Future<void> remove(String key) => _prefs.remove(key);
}

/// Last-resort store used when platform storage cannot be opened.
///
/// Every flow keeps working and the queue depth is still shown; only
/// durability across a restart is lost.
class _MemoryStore implements KeyValueStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  bool get isDurable => false;

  @override
  String? getString(String key) => _values[key] as String?;
  @override
  int? getInt(String key) => _values[key] as int?;
  @override
  List<String>? getStringList(String key) => _values[key] as List<String>?;

  @override
  Future<void> setString(String key, String value) async => _values[key] = value;
  @override
  Future<void> setInt(String key, int value) async => _values[key] = value;
  @override
  Future<void> setStringList(String key, List<String> value) async =>
      _values[key] = value;
  @override
  Future<void> remove(String key) async => _values.remove(key);
}

/// A durable local queue of pending writes.
///
/// The device is the source of truth for in-progress actions (TRD 7). Every
/// voice entry, receipt line, and manual edit is written here first and the UI
/// updates optimistically, so the vendor's workflow never depends on a live
/// connection.
///
/// Backed by `shared_preferences` rather than the SQLite the TRD names: it is
/// the one durable store that behaves identically on Android and on Flutter
/// web, and the queue holds tens of events rather than a dataset. Persistence
/// across a kill-and-relaunch — the actual requirement in TC-S04 — is
/// unaffected by that choice.
class OfflineQueue {
  OfflineQueue._(this._store);

  static const String _queueKey = 'v360.sync.queue';
  static const String _seqKey = 'v360.sync.seq';
  static const String _deviceKey = 'v360.device.id';

  /// Retries beyond this are almost certainly a rejection the server will
  /// repeat forever; the event is parked so a poison entry cannot block the
  /// queue behind it.
  static const int maxAttempts = 5;

  final KeyValueStore _store;

  /// True when queued work survives a restart. False after a fall back to the
  /// in-memory store, which the app surfaces rather than hides.
  bool get isDurable => _store.isDurable;

  static Future<OfflineQueue> open() async =>
      OfflineQueue._(_PrefsStore(await SharedPreferences.getInstance()));

  /// Non-durable queue, used when platform storage cannot be opened and in
  /// tests that do not care about persistence.
  static OfflineQueue inMemory() => OfflineQueue._(_MemoryStore());

  /// Stable per-install identifier, used to order events per device on the
  /// server and to attribute a conflict to the device that lost.
  String get deviceId {
    var id = _store.getString(_deviceKey);
    if (id == null) {
      final rng = Random.secure();
      id = 'dev-${List<int>.generate(8, (_) => rng.nextInt(16)).map((n) => n.toRadixString(16)).join()}';
      _store.setString(_deviceKey, id);
    }
    return id;
  }

  List<QueuedEvent> get pending {
    final raw = _store.getStringList(_queueKey) ?? const <String>[];
    final events = <QueuedEvent>[];
    for (final entry in raw) {
      try {
        events.add(QueuedEvent.fromJson(jsonDecode(entry) as Map<String, dynamic>));
      } catch (error) {
        // A single corrupt entry must not make the whole queue unreadable and
        // silently discard a day's work.
        debugPrint('[queue] dropping unreadable entry: $error');
      }
    }
    events.sort((a, b) => a.localSeq.compareTo(b.localSeq));
    return events;
  }

  int get depth => pending.length;

  Future<void> _write(List<QueuedEvent> events) async {
    await _store.setStringList(
      _queueKey,
      events.map((e) => jsonEncode(e.toJson())).toList(),
    );
  }

  int _nextSeq() {
    final next = (_store.getInt(_seqKey) ?? 0) + 1;
    _store.setInt(_seqKey, next);
    return next;
  }

  /// Enqueue a stock movement as a signed delta.
  ///
  /// A movement and a magnitude, never a resulting quantity — two deltas from
  /// two offline devices merge additively, two absolute values overwrite each
  /// other (TRD 7.2).
  Future<QueuedEvent> enqueueMovement({
    required String itemId,
    required double qty,
    required String movement,
    String source = 'manual',
    double confidence = 1.0,
    String? rawText,
    double? unitValue,
  }) async {
    final event = QueuedEvent(
      clientEventId: _uuidV4(),
      localSeq: _nextSeq(),
      kind: 'inventory_delta',
      clientTs: DateTime.now().toUtc(),
      payload: <String, dynamic>{
        'item_id': itemId,
        'qty': qty,
        'movement': movement,
        'source': source,
        'confidence': confidence,
        'raw_text': ?rawText,
        'unit_value': ?unitValue,
        'device_id': deviceId,
      },
    );

    await _write(<QueuedEvent>[...pending, event]);
    return event;
  }

  Future<QueuedEvent> enqueueUpsert({
    required String itemId,
    required Map<String, dynamic> fields,
  }) async {
    final event = QueuedEvent(
      clientEventId: _uuidV4(),
      localSeq: _nextSeq(),
      kind: 'item_upsert',
      clientTs: DateTime.now().toUtc(),
      payload: <String, dynamic>{'item_id': itemId, ...fields},
    );
    await _write(<QueuedEvent>[...pending, event]);
    return event;
  }

  /// Remove events the server confirmed, and park ones it keeps rejecting.
  ///
  /// `duplicate` counts as settled: the server has it, and retrying forever
  /// would keep a permanent badge on the vendor's screen for work that is
  /// already safe.
  Future<void> settle(Map<String, String> statusByEventId) async {
    final remaining = <QueuedEvent>[];

    for (final event in pending) {
      final status = statusByEventId[event.clientEventId];

      if (status == null) {
        remaining.add(event);
        continue;
      }
      if (status == 'applied' ||
          status == 'applied_with_conflict' ||
          status == 'duplicate') {
        continue;
      }

      event.attempts += 1;
      event.lastError = status;
      if (event.attempts < maxAttempts) {
        remaining.add(event);
      } else {
        debugPrint('[queue] parking ${event.clientEventId} after $status');
      }
    }

    await _write(remaining);
  }

  Future<void> clear() => _store.remove(_queueKey);

  /// Cached authoritative state, so a cold launch with no signal still shows
  /// the vendor's real inventory rather than an empty screen.
  Future<void> cacheSnapshot(String key, Object value) =>
      _store.setString('v360.cache.$key', jsonEncode(value));

  dynamic readSnapshot(String key) {
    final raw = _store.getString('v360.cache.$key');
    if (raw == null) return null;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  String? get token => _store.getString('v360.auth.token');
  Future<void> setToken(String? value) async {
    if (value == null) {
      await _store.remove('v360.auth.token');
    } else {
      await _store.setString('v360.auth.token', value);
    }
  }
}

/// RFC 4122 version 4 UUID from a cryptographically secure source.
///
/// Offline devices mint their own ids, so collisions across devices must be
/// vanishingly unlikely; `Random()` is seeded predictably and two phones
/// launched together could generate the same sequence.
String _uuidV4() {
  final rng = Random.secure();
  final bytes = List<int>.generate(16, (_) => rng.nextInt(256));

  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10

  String hex(int start, int end) =>
      bytes.sublist(start, end).map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
