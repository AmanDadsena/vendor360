import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Base URL of the FastAPI backend.
///
/// Overridable at build time so a deployed build can point elsewhere without
/// a code change:
///   flutter run --dart-define=API_BASE=http://10.0.2.2:8010
const String kApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://127.0.0.1:8010',
);

/// How long a read may take before the app gives up and shows seeded data.
///
/// Three seconds, matching the CarryO rule this is borrowed from: a sleeping
/// free-tier backend should degrade to a working app rather than a spinner.
/// A vendor at a counter will not wait, and a demo on stage cannot.
const Duration kFallbackTimeout = Duration(seconds: 3);

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Thin JSON client over the Vendor360 API.
class ApiClient {
  ApiClient({http.Client? client, this.baseUrl = kApiBase})
      : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;

  String? _token;

  bool get isAuthenticated => _token != null;

  void setToken(String? token) => _token = token;

  Map<String, String> get _headers => <String, String>{
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final cleaned = query?.map((k, v) => MapEntry(k, '$v'))
      ?..removeWhere((_, v) => v.isEmpty || v == 'null');
    return Uri.parse('$baseUrl$path').replace(
      queryParameters: (cleaned == null || cleaned.isEmpty) ? null : cleaned,
    );
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final response = await _client.get(_uri(path, query), headers: _headers);
    return _decode(response);
  }

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) async {
    final response = await _client.post(
      _uri(path, query),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  Future<dynamic> patch(String path, {Object? body}) async {
    final response = await _client.patch(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      if (response.body.isEmpty) return null;
      // The API is UTF-8 and carries Devanagari; `response.body` decodes as
      // latin-1 unless the charset is on the header, which would turn every
      // Hindi label into mojibake.
      return jsonDecode(utf8.decode(response.bodyBytes));
    }

    String message = response.reasonPhrase ?? 'Request failed';
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map && decoded['detail'] != null) {
        message = decoded['detail'].toString();
      }
    } catch (_) {
      // Body was not JSON; the reason phrase is the best available message.
    }
    throw ApiException(response.statusCode, message);
  }

  void close() => _client.close();
}

/// Runs a live read, falling back to seeded data on timeout or error.
///
/// Every *read* in the app goes through this. The rule inherited from CarryO
/// is that the client never blocks on the backend: a cold or unreachable API
/// degrades to a working screen rather than a spinner, which matters both for
/// a vendor with no signal and for a demo on unfamiliar wifi.
///
/// Writes deliberately do not use this — see [withoutFallback].
Future<T> withFallback<T>(
  Future<T> Function() live,
  T Function() seeded, {
  Duration timeout = kFallbackTimeout,
  String? label,
}) async {
  try {
    return await live().timeout(timeout);
  } on TimeoutException {
    debugPrint('[fallback] ${label ?? 'read'} timed out, using seeded data');
    return seeded();
  } catch (error) {
    debugPrint('[fallback] ${label ?? 'read'} failed ($error), using seeded data');
    return seeded();
  }
}

/// Marks a write that must not silently fall back.
///
/// A vendor told their sale was recorded, when no row exists, discovers the
/// loss at the end of the day with no way to reconstruct it. Writes either
/// succeed against the server or are queued explicitly for sync — never
/// quietly swallowed. This wrapper exists so that intent is visible at the
/// call site rather than implied by the absence of [withFallback].
Future<T> withoutFallback<T>(Future<T> Function() live) => live();
