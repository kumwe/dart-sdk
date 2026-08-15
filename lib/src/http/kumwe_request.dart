import 'dart:convert';

import '../json/kumwe_json.dart';
import 'header_map.dart';

/// HTTP methods used by Kumwe's REST API.
enum KumweHttpMethod {
  /// GET.
  get('GET'),

  /// POST.
  post('POST'),

  /// PUT.
  put('PUT'),

  /// PATCH.
  patch('PATCH'),

  /// DELETE.
  delete('DELETE'),

  /// HEAD.
  head('HEAD');

  const KumweHttpMethod(this.wireName);

  /// Uppercase method spelling used on the wire.
  final String wireName;
}

/// A transport-independent HTTP request.
final class KumweRequest {
  /// Creates a request with an optional binary body.
  KumweRequest({
    required this.method,
    required this.uri,
    HeaderMap? headers,
    List<int>? body,
  }) : headers = headers ?? HeaderMap(),
       body = _immutableBytes(body) {
    if (!uri.hasScheme || uri.host.isEmpty) {
      throw ArgumentError.value(
        uri,
        'uri',
        'The request URI must be absolute.',
      );
    }
  }

  /// Creates an `application/json` request.
  factory KumweRequest.json({
    required KumweHttpMethod method,
    required Uri uri,
    required KumweJsonValue body,
    HeaderMap? headers,
  }) {
    final withContentType = (headers ?? HeaderMap()).overlay(const {
      'Content-Type': 'application/json',
    });
    return KumweRequest(
      method: method,
      uri: uri,
      headers: withContentType,
      body: utf8.encode(body.encode()),
    );
  }

  /// HTTP method.
  final KumweHttpMethod method;

  /// Absolute target URI.
  final Uri uri;

  /// Immutable case-insensitive headers.
  final HeaderMap headers;

  /// Immutable request bytes.
  final List<int> body;

  static List<int> _immutableBytes(List<int>? source) {
    final bytes = source ?? const <int>[];
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'Request bodies must contain byte values from 0 through 255.',
      );
    }
    return List<int>.unmodifiable(bytes);
  }
}
