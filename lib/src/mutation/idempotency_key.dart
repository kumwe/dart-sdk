import 'dart:math';

/// A caller-generated retry key for exactly one mutation intent.
///
/// Kumwe replays the stored response when the identical request is retried
/// with the same key and rejects reuse with different request data, so the
/// application creates one key per user intent and retains it until the
/// terminal result is known. A key is never replaced merely because a request
/// timed out. The audited header contract accepts 8 to 128 characters matching
/// `^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$`.
final class IdempotencyKey {
  /// Validates an application-supplied key against the header contract.
  factory IdempotencyKey(String value) {
    if (!_pattern.hasMatch(value)) {
      throw ArgumentError.value(
        value,
        'value',
        'Idempotency keys need 8 to 128 characters from the supported set, '
            'starting with a letter or digit.',
      );
    }
    return IdempotencyKey._(value);
  }

  /// Generates a fresh 256-bit key from a cryptographic random source.
  factory IdempotencyKey.generate() {
    final values = List<int>.generate(32, (_) => _random.nextInt(256));
    return IdempotencyKey._(
      values.map((value) => value.toRadixString(16).padLeft(2, '0')).join(),
    );
  }

  const IdempotencyKey._(this.value);

  /// Header name that carries the key on a mutation request.
  static const String headerName = 'Idempotency-Key';

  /// Response header marking a stored response replay.
  static const String replayedHeaderName = 'Idempotency-Replayed';

  /// Validated key value sent as the `Idempotency-Key` header.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is IdempotencyKey && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => 'IdempotencyKey($value)';

  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$');

  static final Random _random = Random.secure();
}
