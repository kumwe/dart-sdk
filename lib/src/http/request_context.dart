/// Per-request protocol headers understood by Kumwe.
final class KumweRequestContext {
  /// Creates and validates request-scoped protocol values.
  factory KumweRequestContext({
    String? requestId,
    String? idempotencyKey,
    String? ifMatch,
    String? ifNoneMatch,
  }) {
    return KumweRequestContext._(
      requestId: requestId == null ? null : _requestId(requestId),
      idempotencyKey: idempotencyKey == null
          ? null
          : _idempotencyKey(idempotencyKey),
      ifMatch: ifMatch == null ? null : _entityTagCondition(ifMatch, 'ifMatch'),
      ifNoneMatch: ifNoneMatch == null
          ? null
          : _entityTagCondition(ifNoneMatch, 'ifNoneMatch'),
    );
  }

  const KumweRequestContext._({
    required this.requestId,
    required this.idempotencyKey,
    required this.ifMatch,
    required this.ifNoneMatch,
  });

  /// Caller-selected correlation identity.
  final String? requestId;

  /// Caller-selected retry identity for one logical mutation.
  final String? idempotencyKey;

  /// Strong entity tag precondition for a mutation.
  final String? ifMatch;

  /// Conditional-read entity tag.
  final String? ifNoneMatch;

  /// Serializes the present protocol values as request headers.
  Map<String, String> toHeaders() => {
    'X-Request-ID': ?requestId,
    'Idempotency-Key': ?idempotencyKey,
    'If-Match': ?ifMatch,
    'If-None-Match': ?ifNoneMatch,
  };

  static String _requestId(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{8,64}$').hasMatch(normalized)) {
      throw ArgumentError(
        'Request IDs must contain 8 to 64 transport-safe characters.',
      );
    }
    return normalized;
  }

  static String _idempotencyKey(String value) {
    final normalized = value.trim();
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9._:-]{7,127}$').hasMatch(normalized)) {
      throw ArgumentError(
        'Idempotency keys must contain 8 to 128 transport-safe characters.',
      );
    }
    return normalized;
  }

  static String _entityTagCondition(String value, String _) {
    final normalized = value.trim();
    final opaque = normalized.length >= 2
        ? normalized.substring(1, normalized.length - 1)
        : '';
    final quoted =
        normalized.length >= 2 &&
        normalized.startsWith('"') &&
        normalized.endsWith('"') &&
        opaque.codeUnits.every(
          (character) =>
              character == 0x21 ||
              (character >= 0x23 && character <= 0x7e) ||
              (character >= 0x80 && character <= 0xff),
        );
    if (normalized != '*' && !quoted) {
      throw ArgumentError(
        'Entity-tag conditions must be * or one quoted entity tag.',
      );
    }
    if (normalized.startsWith('W/')) {
      throw ArgumentError('Kumwe requires strong entity tags.');
    }
    return normalized;
  }
}
