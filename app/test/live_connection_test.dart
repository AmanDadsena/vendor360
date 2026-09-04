import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vendor360/data/live_connection.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// The live channel's lifecycle.
///
/// Reconnect logic is the part of a socket client that rots silently: it works
/// on a good network, and the day it matters nobody has exercised it. These
/// drive the state machine directly with a fake channel, so the backoff
/// schedule and the status transitions are asserted rather than hoped for.
void main() {
  group('backoff', () {
    test('grows exponentially from the first retry', () {
      expect(LiveConnection.backoffFor(0), LiveConnection.firstRetry);
      expect(LiveConnection.backoffFor(1), LiveConnection.firstRetry * 2);
      expect(LiveConnection.backoffFor(2), LiveConnection.firstRetry * 4);
      expect(LiveConnection.backoffFor(3), LiveConnection.firstRetry * 8);
    });

    test('is capped, so a long outage does not become an hour of silence', () {
      for (final attempt in <int>[6, 10, 50]) {
        expect(
          LiveConnection.backoffFor(attempt),
          lessThanOrEqualTo(LiveConnection.maxRetry),
        );
      }
    });

    test('jitter spreads the herd', () {
      // Without it, a server restart brings every client back in the same
      // instant — the moment it can least afford them.
      final plain = LiveConnection.backoffFor(2);
      final jittered = LiveConnection.backoffFor(2, jitter: 0.4);

      expect(jittered, greaterThan(plain));
      expect(jittered.inMilliseconds, (plain.inMilliseconds * 1.4).round());
    });
  });

  group('url', () {
    test('upgrades http to ws and https to wss', () {
      expect(liveUrlFor('http://127.0.0.1:8010'), 'ws://127.0.0.1:8010/live');
      expect(liveUrlFor('https://api.example.com'), 'wss://api.example.com/live');
    });
  });

  group('LiveEvent', () {
    test('decodes a typed frame', () {
      final event = LiveEvent.decode(
        jsonEncode(<String, Object>{'type': 'stockout', 'sku_name': 'Milk'}),
      );

      expect(event, isNotNull);
      expect(event!.type, 'stockout');
      expect(event.data['sku_name'], 'Milk');
    });

    test('ignores anything unparseable rather than throwing', () {
      // A frame we cannot read is a frame we skip. Throwing here would kill
      // the connection over one malformed message.
      expect(LiveEvent.decode('not json'), isNull);
      expect(LiveEvent.decode('[1,2,3]'), isNull);
      expect(LiveEvent.decode(jsonEncode(<String, Object>{'no': 'type'})), isNull);
      expect(LiveEvent.decode(null), isNull);
    });

    test('knows which frames are plumbing', () {
      expect(const LiveEvent('ping', {}).isPlumbing, isTrue);
      expect(const LiveEvent('ready', {}).isPlumbing, isTrue);
      expect(const LiveEvent('stockout', {}).isPlumbing, isFalse);
    });
  });

  group('connection', () {
    late _FakeChannel channel;
    late LiveConnection connection;

    setUp(() {
      channel = _FakeChannel();
      connection = LiveConnection(
        baseUrl: 'http://localhost:8010',
        connect: (_) => channel,
      );
    });

    tearDown(() => connection.dispose());

    test('starts offline', () {
      expect(connection.status, LiveStatus.offline);
    });

    test('sends the token in the first frame, not the query string', () async {
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);

      // A query parameter would be written to every access log the request
      // passes through, and a session token in a log file is a credential
      // with a long and unmanaged life.
      expect(channel.sent, hasLength(1));
      expect(jsonDecode(channel.sent.single), <String, String>{'token': 'a-token'});
    });

    test('only reports live once the server accepts the token', () async {
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);

      // The socket being open only means TCP succeeded.
      expect(connection.status, isNot(LiveStatus.live));

      channel.emit(<String, Object>{'type': 'ready', 'role': 'vendor'});
      await Future<void>.delayed(Duration.zero);

      expect(connection.status, LiveStatus.live);
    });

    test('surfaces events but never plumbing', () async {
      final seen = <String>[];
      connection.events.listen((e) => seen.add(e.type));

      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);

      channel.emit(<String, Object>{'type': 'ready'});
      channel.emit(<String, Object>{'type': 'ping'});
      channel.emit(<String, Object>{'type': 'stockout', 'sku_name': 'Milk'});
      await Future<void>.delayed(Duration.zero);

      expect(seen, <String>['stockout']);
    });

    test('goes to reconnecting when the socket drops', () async {
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);
      channel.emit(<String, Object>{'type': 'ready'});
      await Future<void>.delayed(Duration.zero);
      expect(connection.status, LiveStatus.live);

      channel.drop();
      await Future<void>.delayed(Duration.zero);

      expect(connection.status, LiveStatus.reconnecting);
    });

    test('stop means stop — no retry after sign-out', () async {
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);

      connection.stop();
      channel.drop();
      await Future<void>.delayed(Duration.zero);

      expect(connection.status, LiveStatus.offline);
    });

    test('starting twice with the same token does not reconnect', () async {
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);
      connection.start('a-token');
      await Future<void>.delayed(Duration.zero);

      expect(channel.sent, hasLength(1));
    });
  });
}

/// A WebSocketChannel that never touches a network.
class _FakeChannel extends StreamChannelMixin implements WebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final List<String> sent = <String>[];

  void emit(Map<String, Object?> frame) => _incoming.add(jsonEncode(frame));

  void drop() {
    if (!_incoming.isClosed) _incoming.close();
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _FakeSink(this);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._channel);

  final _FakeChannel _channel;

  @override
  void add(Object? data) {
    if (data is String) _channel.sent.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async =>
      _channel.drop();

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future<void> addStream(Stream<dynamic> stream) async {}

  @override
  Future<void> get done => Future<void>.value();
}
