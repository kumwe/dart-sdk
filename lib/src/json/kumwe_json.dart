import 'dart:collection';
import 'dart:convert';

/// An immutable, JSON-compatible value at Kumwe's dynamic contract boundary.
///
/// Extension-defined content and business records cannot be represented by a
/// fixed set of generated Dart classes. This type keeps that boundary explicit
/// while rejecting values that `jsonEncode` would otherwise coerce or inspect
/// dynamically.
final class KumweJsonValue {
  /// Creates a validated, deeply immutable JSON value.
  factory KumweJsonValue.from(Object? value) {
    return KumweJsonValue._(
      _freeze(value, r'$', HashSet<Object>.identity(), 0),
    );
  }

  const KumweJsonValue._(this.value);

  /// Parses and validates one JSON document.
  factory KumweJsonValue.parse(String source) {
    try {
      return KumweJsonValue.from(jsonDecode(source));
    } on JsonUnsupportedObjectError catch (error) {
      throw FormatException('The document contains a non-JSON value.', error);
    }
  }

  /// The deeply immutable JSON-compatible representation.
  final Object? value;

  /// Whether this value is a JSON object.
  bool get isObject => value is Map<String, Object?>;

  /// Whether this value is a JSON array.
  bool get isArray => value is List<Object?>;

  /// Returns this value as a JSON object.
  ///
  /// Throws [StateError] when the wrapped document is not an object.
  Map<String, Object?> get object {
    final current = value;
    if (current is! Map<String, Object?>) {
      throw StateError('The JSON value is not an object.');
    }
    return current;
  }

  /// Returns this value as a JSON array.
  ///
  /// Throws [StateError] when the wrapped document is not an array.
  List<Object?> get array {
    final current = value;
    if (current is! List<Object?>) {
      throw StateError('The JSON value is not an array.');
    }
    return current;
  }

  /// Encodes the value without invoking custom `toJson` methods.
  String encode() => jsonEncode(value);

  static Object? _freeze(
    Object? value,
    String path,
    Set<Object> ancestors,
    int depth,
  ) {
    if (depth > 128) {
      throw FormatException('The JSON value at $path exceeds 128 levels.');
    }
    if (value == null || value is bool || value is String) {
      return value;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw FormatException('The JSON number at $path must be finite.');
      }
      return value;
    }
    if (value is num) {
      final converted = value.toDouble();
      if (!converted.isFinite) {
        throw FormatException('The JSON number at $path must be finite.');
      }
      return converted;
    }
    if (value is List<Object?>) {
      _enterContainer(value, path, ancestors);
      try {
        return List<Object?>.unmodifiable(
          value.indexed.map(
            (entry) =>
                _freeze(entry.$2, '$path[${entry.$1}]', ancestors, depth + 1),
          ),
        );
      } finally {
        ancestors.remove(value);
      }
    }
    if (value is Map<Object?, Object?>) {
      _enterContainer(value, path, ancestors);
      final frozen = <String, Object?>{};
      try {
        for (final MapEntry<Object?, Object?> entry in value.entries) {
          final key = entry.key;
          if (key is! String) {
            throw FormatException(
              'The JSON object at $path has a non-string key.',
            );
          }
          frozen[key] = _freeze(
            entry.value,
            '$path.$key',
            ancestors,
            depth + 1,
          );
        }
        return UnmodifiableMapView<String, Object?>(frozen);
      } finally {
        ancestors.remove(value);
      }
    }
    throw FormatException(
      'The value at $path has unsupported type ${value.runtimeType}.',
    );
  }

  static void _enterContainer(
    Object value,
    String path,
    Set<Object> ancestors,
  ) {
    if (!ancestors.add(value)) {
      throw FormatException('The JSON value at $path contains a cycle.');
    }
  }
}

/// An immutable JSON object used for dynamic Kumwe records and contracts.
final class KumweJsonObject {
  /// Creates a validated JSON object.
  factory KumweJsonObject.from(Map<String, Object?> value) {
    return KumweJsonObject._(KumweJsonValue.from(value).object);
  }

  const KumweJsonObject._(this.value);

  /// Parses a document and requires its root to be an object.
  factory KumweJsonObject.parse(String source) {
    final parsed = KumweJsonValue.parse(source);
    if (!parsed.isObject) {
      throw const FormatException('The JSON document must contain an object.');
    }
    return KumweJsonObject._(parsed.object);
  }

  /// The deeply immutable object members.
  final Map<String, Object?> value;

  /// Looks up an object member without coercion.
  Object? operator [](String key) => value[key];

  /// Encodes this object as JSON.
  String encode() => jsonEncode(value);
}
