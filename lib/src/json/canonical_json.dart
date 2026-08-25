import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'kumwe_json.dart';

/// Deterministic canonical encoding for mutation byte-identity.
///
/// A mutation is canonicalized exactly once, its bytes are bound to the
/// idempotency key, and an identical retry replays those bytes. Two
/// applications encoding the same JSON value therefore need identical output:
/// object members are ordered by their UTF-16 code units, no insignificant
/// whitespace is emitted, strings use one fixed escaping, and integers keep
/// their decimal form.
///
/// Non-integer numbers are refused rather than canonicalized. Kumwe's exact
/// values — decimals, money, quantities — travel as strings by contract, so a
/// binary floating-point number inside a mutation body is already a defect;
/// refusing it here keeps the canonical form independent of any platform's
/// float formatting.
final class KumweCanonicalJson {
  const KumweCanonicalJson._();

  /// Encodes [value] into canonical UTF-8 bytes.
  ///
  /// Throws [FormatException] when the value contains a non-integer number.
  static List<int> encode(KumweJsonValue value) {
    final buffer = StringBuffer();
    _write(value.value, buffer);
    return List<int>.unmodifiable(utf8.encode(buffer.toString()));
  }

  /// Encodes [value] and returns the lowercase hexadecimal SHA-256 digest
  /// of its canonical bytes.
  static String sha256Hex(KumweJsonValue value) {
    return sha256.convert(encode(value)).toString();
  }

  static void _write(Object? value, StringBuffer buffer) {
    if (value == null) {
      buffer.write('null');
      return;
    }
    if (value is bool) {
      buffer.write(value ? 'true' : 'false');
      return;
    }
    if (value is int) {
      buffer.write(value.toString());
      return;
    }
    if (value is double) {
      throw const FormatException(
        'Canonical mutation bodies carry exact values as strings; '
        'a binary floating-point number cannot be canonicalized.',
      );
    }
    if (value is String) {
      _writeString(value, buffer);
      return;
    }
    if (value is List<Object?>) {
      buffer.write('[');
      for (var index = 0; index < value.length; index++) {
        if (index > 0) {
          buffer.write(',');
        }
        _write(value[index], buffer);
      }
      buffer.write(']');
      return;
    }
    if (value is Map<String, Object?>) {
      final keys = value.keys.toList()..sort(_compareCodeUnits);
      buffer.write('{');
      for (var index = 0; index < keys.length; index++) {
        if (index > 0) {
          buffer.write(',');
        }
        _writeString(keys[index], buffer);
        buffer.write(':');
        _write(value[keys[index]], buffer);
      }
      buffer.write('}');
      return;
    }
    throw FormatException(
      'The value of type ${value.runtimeType} is not canonical JSON.',
    );
  }

  static void _writeString(String value, StringBuffer buffer) {
    _requireWellFormed(value);
    buffer.write('"');
    for (final unit in value.codeUnits) {
      switch (unit) {
        case 0x22:
          buffer.write(r'\"');
        case 0x5c:
          buffer.write(r'\\');
        case 0x08:
          buffer.write(r'\b');
        case 0x09:
          buffer.write(r'\t');
        case 0x0a:
          buffer.write(r'\n');
        case 0x0c:
          buffer.write(r'\f');
        case 0x0d:
          buffer.write(r'\r');
        default:
          if (unit < 0x20) {
            buffer.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
          } else {
            buffer.writeCharCode(unit);
          }
      }
    }
    buffer.write('"');
  }

  /// Refuses unpaired surrogate code units.
  ///
  /// UTF-8 encoding replaces every lone surrogate with U+FFFD, which
  /// would map two *different* strings onto identical canonical bytes and
  /// one shared digest — breaking the injectivity the idempotency binding
  /// depends on. A well-formed pair passes; a lone half never does.
  static void _requireWellFormed(String value) {
    final units = value.codeUnits;
    for (var index = 0; index < units.length; index++) {
      final unit = units[index];
      if (unit >= 0xd800 && unit <= 0xdbff) {
        final next = index + 1 < units.length ? units[index + 1] : 0;
        if (next < 0xdc00 || next > 0xdfff) {
          throw const FormatException(
            'Canonical JSON refuses unpaired surrogate code units.',
          );
        }
        index++;
      } else if (unit >= 0xdc00 && unit <= 0xdfff) {
        throw const FormatException(
          'Canonical JSON refuses unpaired surrogate code units.',
        );
      }
    }
  }

  static int _compareCodeUnits(String left, String right) {
    final length = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < length; index++) {
      final difference = left.codeUnitAt(index) - right.codeUnitAt(index);
      if (difference != 0) {
        return difference;
      }
    }
    return left.length - right.length;
  }
}
