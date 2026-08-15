import '../context/execution_context.dart';
import 'credential_reference.dart';

/// Identity of one stored secret: the exact origin plus the credential it
/// belongs to.
///
/// Stores are keyed by origin and credential reference — never by username
/// alone — so material can never be returned for the wrong deployment.
final class KumweCredentialStoreKey {
  /// Creates a validated store key.
  factory KumweCredentialStoreKey({
    required Uri origin,
    required KumweCredentialReference credential,
  }) {
    return KumweCredentialStoreKey._(
      origin: KumweContextIdentifiers.normalizeOrigin(origin, 'origin'),
      credential: credential,
    );
  }

  const KumweCredentialStoreKey._({
    required this.origin,
    required this.credential,
  });

  /// Exact HTTPS origin the credential belongs to.
  final Uri origin;

  /// Non-secret reference naming the credential.
  final KumweCredentialReference credential;

  /// Canonical identity used by store implementations.
  String get identity =>
      '${origin.scheme}://${origin.authority}'
      '|${credential.value}';

  @override
  bool operator ==(Object other) =>
      other is KumweCredentialStoreKey && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;

  @override
  String toString() => 'KumweCredentialStoreKey($identity)';
}

/// The platform seam that persists credential material securely.
///
/// Applications select an adapter backed by the operating system facility —
/// Keychain, Credential Manager, Secret Service or an equivalent. Stored
/// values are opaque secret strings; they never enter ordinary preferences,
/// logs, crash reports or analytics, and removal after logout or revocation
/// must succeed even when the server outcome was uncertain.
abstract interface class KumweCredentialStore {
  /// Returns the stored secret for [key], or `null` when absent.
  Future<String?> read(KumweCredentialStoreKey key);

  /// Stores [secret] for [key], replacing any previous value atomically.
  Future<void> write(KumweCredentialStoreKey key, String secret);

  /// Removes the secret for [key]; removing an absent entry is not an error.
  Future<void> remove(KumweCredentialStoreKey key);
}

/// A volatile in-memory store for tests and development hosts.
///
/// Nothing is persisted and nothing is protected by an operating system
/// facility, so production applications must not select this adapter.
final class InMemoryCredentialStore implements KumweCredentialStore {
  /// Creates an empty volatile store.
  InMemoryCredentialStore();

  final Map<String, String> _secrets = {};

  @override
  Future<String?> read(KumweCredentialStoreKey key) async =>
      _secrets[key.identity];

  @override
  Future<void> write(KumweCredentialStoreKey key, String secret) async {
    if (secret.isEmpty) {
      throw ArgumentError.value(
        secret,
        'secret',
        'Stored credential material cannot be empty.',
      );
    }
    _secrets[key.identity] = secret;
  }

  @override
  Future<void> remove(KumweCredentialStoreKey key) async {
    _secrets.remove(key.identity);
  }

  /// Removes every stored secret.
  void clear() => _secrets.clear();

  @override
  String toString() => 'InMemoryCredentialStore(${_secrets.length} entries)';
}
