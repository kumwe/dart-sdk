/// A validated opaque bearer token.
final class BearerToken {
  /// Creates a token from application-owned credential material.
  factory BearerToken(String value) {
    if (value.isEmpty ||
        value.trim() != value ||
        value.contains(RegExp(r'\s'))) {
      throw ArgumentError(
        'Bearer tokens cannot be empty or contain whitespace.',
      );
    }
    return BearerToken._(value);
  }

  const BearerToken._(this.value);

  /// Opaque token value placed after the `Bearer` authorization scheme.
  final String value;

  @override
  String toString() => 'BearerToken(<redacted>)';
}

/// Supplies bearer tokens without coupling the SDK to a credential store.
abstract interface class BearerTokenProvider {
  /// Returns the current token, or `null` when no authenticated session exists.
  Future<BearerToken?> token();
}

/// Supplies one fixed bearer token.
final class StaticBearerTokenProvider implements BearerTokenProvider {
  /// Creates a provider for [value].
  StaticBearerTokenProvider(String value) : _token = BearerToken(value);

  final BearerToken _token;

  @override
  Future<BearerToken> token() async => _token;
}

/// Resolves tokens lazily, allowing an application to refresh its own store.
final class CallbackBearerTokenProvider implements BearerTokenProvider {
  /// Creates a provider backed by [callback].
  const CallbackBearerTokenProvider(this.callback);

  /// Application-owned token lookup.
  final Future<String?> Function() callback;

  @override
  Future<BearerToken?> token() async {
    final value = await callback();
    return value == null ? null : BearerToken(value);
  }
}
