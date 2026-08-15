import 'dart:collection';

/// A validated, case-insensitive HTTP header map.
final class HeaderMap {
  /// Creates an immutable header map.
  factory HeaderMap([Map<String, String> headers = const {}]) {
    final normalized = <String, String>{};
    for (final entry in headers.entries) {
      final name = _normalizeName(entry.key);
      final value = _validateValue(entry.value, entry.key);
      if (normalized.containsKey(name)) {
        throw ArgumentError('Header names must be unique ignoring case.');
      }
      normalized[name] = value;
    }
    return HeaderMap._(UnmodifiableMapView<String, String>(normalized));
  }

  const HeaderMap._(this._headers);

  final Map<String, String> _headers;

  /// Number of headers.
  int get length => _headers.length;

  /// Whether there are no headers.
  bool get isEmpty => _headers.isEmpty;

  /// Returns a header value using a case-insensitive name.
  String? operator [](String name) => _headers[name.toLowerCase()];

  /// Whether a header is present using a case-insensitive name.
  bool contains(String name) => _headers.containsKey(name.toLowerCase());

  /// Returns an immutable normalized representation.
  Map<String, String> toMap() => _headers;

  /// Returns a new map containing this map and [headers].
  ///
  /// New values replace existing values with the same case-insensitive name.
  HeaderMap overlay(Map<String, String> headers) {
    final combined = Map<String, String>.of(_headers);
    for (final entry in headers.entries) {
      combined[_normalizeName(entry.key)] = _validateValue(
        entry.value,
        entry.key,
      );
    }
    return HeaderMap._(UnmodifiableMapView<String, String>(combined));
  }

  static String _normalizeName(String name) {
    final normalized = name.toLowerCase();
    if (!_headerName.hasMatch(normalized)) {
      throw ArgumentError.value(name, 'name', 'Invalid HTTP header name.');
    }
    return normalized;
  }

  static String _validateValue(String value, String _) {
    final hasControlCharacter = value.codeUnits.any(
      (character) =>
          (character < 0x20 && character != 0x09) || character == 0x7f,
    );
    if (hasControlCharacter) {
      throw ArgumentError(
        'HTTP header values cannot contain unsafe control characters.',
      );
    }
    return value.trim();
  }

  static final RegExp _headerName = RegExp(r"^[!#$%&'*+.^_`|~0-9a-z-]+$");
}
