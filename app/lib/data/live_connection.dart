import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'api_client.dart';

/// Whether the app is currently hearing about changes as they happen.
///
/// Exposed to the user rather than kept internal, because the difference
/// between "nothing has changed" and "I am not being told what changed" is one
/// a person has to be able to see. A screen that silently stops updating is
/// indistinguishable from a quiet afternoon.
enum LiveStatus {
  /// Connected. Changes arrive within a second of happening.
  live,

  /// Dropped, retrying. Data is as fresh as the last pull.
  reconnecting,

  /// Not connected and not trying — signed out, or the server has no socket.
  offline,
}

/// One decoded event off the wire.
///
/// Deliberately thin. The socket carries a hint, not a payload of record: the
/// client re-reads through its ordinary path when one of these lands, so a
/// dropped connection costs liveness and never correctness. Making this a rich
/// typed model would invite screens to render from it, which is exactly the
/// second-source-of-truth this design avoids.
class LiveEvent {
  const LiveEvent(this.type, this.data);

  final String type;
  final Map<String, dynamic> data;

  String? get itemId => data['item_id'] as String?;
  String? get category => data['category'] as String?;
  String? get locality => data['locality'] as String?;
  String? get title => data['title'] as String?;
  String get severity => data['severity'] as String? ?? 'info';

  /// Housekeeping frames the app never surfaces.
  bool get isPlumbing => type == 'ping' || type == 'ready';

  static LiveEvent? decode(Object? raw) {
    if (raw is! String) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return null;
      final map = Map<String, dynamic>.from(json);
      final type = map['type'];
      if (type is! String) return null;
      return LiveEvent(type, map);
    } catch (_) {
      // A frame we cannot parse is a frame we ignore. Throwing here would kill
      // the connection over one malformed message.
      return null;
    }
  }
}

/// Holds the live channel open, and gives up gracefully when it cannot.
///
/// The reconnect schedule matters more than it looks. A tight retry loop
/// against an unreachable server is indistinguishable from a denial of service
/// once a few hundred shops are running the app, so the backoff is exponential
/// and jittered — jittered specifically so that a server restart does not
/// bring every client back in the same instant.
class LiveConnection {
  LiveConnection({
    required this.baseUrl,
    WebSocketChannel Function(Uri)? connect,
  }) : _connect = connect ?? WebSocketChannel.connect;

  final String baseUrl;
  final WebSocketChannel Function(Uri) _connect;

  static const Duration firstRetry = Duration(seconds: 1);
  static const Duration maxRetry = Duration(seconds: 30);

  final StreamController<LiveEvent> _events =
      StreamController<LiveEvent>.broadcast();
  final StreamController<LiveStatus> _status =
      StreamController<LiveStatus>.broadcast();

  Stream<LiveEvent> get events => _events.stream;
  Stream<LiveStatus> get statusChanges => _status.stream;

  LiveStatus _current = LiveStatus.offline;
  LiveStatus get status => _current;

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _retryTimer;
  String? _token;
  int _attempt = 0;
  bool _closed = false;

  /// The delay before attempt [n], exponential with jitter, capped.
  ///
  /// Exposed and pure so the schedule can be asserted rather than waited out.
  static Duration backoffFor(int attempt, {double jitter = 0}) {
    final base = firstRetry.inMilliseconds * (1 << attempt.clamp(0, 5));
    final capped = base.clamp(0, maxRetry.inMilliseconds);
    return Duration(milliseconds: (capped * (1 + jitter)).round());
  }

  Uri get _uri {
    final http = Uri.parse(baseUrl);
    return http.replace(
      scheme: http.scheme == 'https' ? 'wss' : 'ws',
      path: '${http.path}/live',
    );
  }

  /// Open the channel for a signed-in principal. Safe to call repeatedly.
  void start(String token) {
    if (_token == token && _channel != null) return;
    _token = token;
    _closed = false;
    _attempt = 0;
    _open();
  }

  /// Close and stay closed. Called on sign-out.
  void stop() {
    _closed = true;
    _token = null;
    _retryTimer?.cancel();
    _teardown();
    _emit(LiveStatus.offline);
  }

  void _emit(LiveStatus status) {
    if (_current == status) return;
    _current = status;
    if (!_status.isClosed) _status.add(status);
  }

  void _open() {
    final token = _token;
    if (_closed || token == null) return;

    try {
      final channel = _connect(_uri);
      _channel = channel;

      // The token goes in the first frame rather than the query string. A
      // query parameter is written to every access log the request passes
      // through, and a session token in a log file is a credential with a long
      // and unmanaged life.
      channel.sink.add(jsonEncode(<String, String>{'token': token}));

      _subscription = channel.stream.listen(
        _onFrame,
        onError: (Object error) => _scheduleRetry('error: $error'),
        onDone: () => _scheduleRetry('closed (${channel.closeCode})'),
        cancelOnError: true,
      );
    } catch (error) {
      _scheduleRetry('could not open: $error');
    }
  }

  void _onFrame(Object? raw) {
    final event = LiveEvent.decode(raw);
    if (event == null) return;

    // The server's `ready` is the real handshake: the socket being open only
    // means TCP succeeded, not that the token was accepted.
    if (event.type == 'ready') {
      _attempt = 0;
      _emit(LiveStatus.live);
      return;
    }
    if (event.isPlumbing) return;

    if (!_events.isClosed) _events.add(event);
  }

  void _teardown() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _scheduleRetry(String why) {
    _teardown();
    if (_closed || _token == null) {
      _emit(LiveStatus.offline);
      return;
    }

    _emit(LiveStatus.reconnecting);

    // Jitter spreads the herd. Without it a server restart brings every client
    // back in the same instant, which is the moment it can least afford them.
    final jitter = (DateTime.now().microsecond % 400) / 1000;
    final wait = backoffFor(_attempt, jitter: jitter);
    _attempt++;

    debugPrint('[live] $why — retrying in ${wait.inMilliseconds}ms');
    _retryTimer?.cancel();
    _retryTimer = Timer(wait, _open);
  }

  void dispose() {
    stop();
    _events.close();
    _status.close();
  }
}

/// The socket URL derived from the configured API base.
String liveUrlFor(String base) =>
    LiveConnection(baseUrl: base)._uri.toString();

/// Convenience for the default configured backend.
String get defaultLiveUrl => liveUrlFor(kApiBase);
