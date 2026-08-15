import 'contract_metadata.dart';

/// Non-secret dimensions that isolate one caller-specific contract cache.
final class KumweContractCacheKey {
  /// Creates a cache key.
  factory KumweContractCacheKey({
    required Uri baseUri,
    required String site,
    required String authorizationPartition,
  }) {
    final partition = authorizationPartition.trim();
    if (partition.isEmpty || partition.length > 256) {
      throw ArgumentError.value(
        authorizationPartition,
        'authorizationPartition',
        'The authorization partition must contain 1 to 256 characters.',
      );
    }
    if (partition.contains('\r') || partition.contains('\n')) {
      throw ArgumentError.value(
        authorizationPartition,
        'authorizationPartition',
        'The authorization partition cannot contain newlines.',
      );
    }
    return KumweContractCacheKey._(
      baseUri: baseUri,
      site: site,
      authorizationPartition: partition,
    );
  }

  const KumweContractCacheKey._({
    required this.baseUri,
    required this.site,
    required this.authorizationPartition,
  });

  /// Deployment URI, including any reverse-proxy base path.
  final Uri baseUri;

  /// Normalized Kumwe site identifier.
  final String site;

  /// Application-owned, non-secret actor/credential-family partition.
  final String authorizationPartition;

  @override
  bool operator ==(Object other) {
    return other is KumweContractCacheKey &&
        other.baseUri == baseUri &&
        other.site == site &&
        other.authorizationPartition == authorizationPartition;
  }

  @override
  int get hashCode => Object.hash(baseUri, site, authorizationPartition);
}

/// Stores policy-filtered OpenAPI contracts without prescribing persistence.
abstract interface class KumweContractCache {
  /// Returns a cached representation for [key], when present.
  Future<KumweOpenApiContract?> read(KumweContractCacheKey key);

  /// Replaces the cached representation for [key].
  Future<void> write(KumweContractCacheKey key, KumweOpenApiContract contract);

  /// Removes the representation for [key].
  Future<void> remove(KumweContractCacheKey key);
}

/// Process-local contract cache suitable for short-lived clients and tests.
final class InMemoryKumweContractCache implements KumweContractCache {
  final Map<KumweContractCacheKey, KumweOpenApiContract> _contracts = {};

  @override
  Future<KumweOpenApiContract?> read(KumweContractCacheKey key) async {
    return _contracts[key];
  }

  @override
  Future<void> remove(KumweContractCacheKey key) async {
    _contracts.remove(key);
  }

  @override
  Future<void> write(
    KumweContractCacheKey key,
    KumweOpenApiContract contract,
  ) async {
    _contracts[key] = contract;
  }
}
