import 'dart:convert';

import '../json/kumwe_json.dart';
import 'header_map.dart';

/// A transport-independent HTTP response.
final class KumweResponse {
  /// Creates an immutable response value.
  KumweResponse({required this.statusCode, HeaderMap? headers, List<int>? body})
    : headers = headers ?? HeaderMap(),
      body = _immutableBytes(body) {
    if (statusCode < 100 || statusCode > 599) {
      throw ArgumentError.value(
        statusCode,
        'statusCode',
        'HTTP response status codes must be between 100 and 599.',
      );
    }
  }

  /// HTTP status code.
  final int statusCode;

  /// Immutable case-insensitive headers.
  final HeaderMap headers;

  /// Immutable response bytes.
  final List<int> body;

  /// Whether the response has a 2xx status code.
  bool get isSuccessful => statusCode >= 200 && statusCode < 300;

  /// Media type without parameters, normalized to lowercase.
  String? get mediaType {
    final contentType = headers['content-type'];
    if (contentType == null || contentType.trim().isEmpty) {
      return null;
    }
    return contentType.split(';').first.trim().toLowerCase();
  }

  /// UTF-8 response text.
  String get text => utf8.decode(body);

  /// Parses the body as a validated JSON value.
  KumweJsonValue json() => KumweJsonValue.parse(text);

  /// Parses the body as a validated JSON object.
  KumweJsonObject jsonObject() => KumweJsonObject.parse(text);

  static List<int> _immutableBytes(List<int>? source) {
    final bytes = source ?? const <int>[];
    if (bytes.any((byte) => byte < 0 || byte > 255)) {
      throw ArgumentError(
        'Response bodies must contain byte values from 0 through 255.',
      );
    }
    return List<int>.unmodifiable(bytes);
  }
}
