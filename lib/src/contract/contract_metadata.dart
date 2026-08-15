import '../json/kumwe_json.dart';

/// Server evidence attached to one caller-specific OpenAPI representation.
final class KumweContractMetadata {
  /// Creates validated contract metadata.
  factory KumweContractMetadata({
    required String generation,
    required String etag,
    required DateTime fetchedAt,
  }) {
    if (!_digest.hasMatch(generation)) {
      throw ArgumentError.value(
        generation,
        'generation',
        'Contract generations must be lowercase SHA-256 values.',
      );
    }
    if (!_strongEtag.hasMatch(etag)) {
      throw ArgumentError.value(
        etag,
        'etag',
        'Contract entity tags must be quoted lowercase SHA-256 values.',
      );
    }
    return KumweContractMetadata._(
      generation: generation,
      etag: etag,
      fetchedAt: fetchedAt.toUtc(),
    );
  }

  const KumweContractMetadata._({
    required this.generation,
    required this.etag,
    required this.fetchedAt,
  });

  /// SHA-256 identity of the policy-filtered business generation.
  final String generation;

  /// Strong SHA-256 entity tag for the exact response bytes.
  final String etag;

  /// Time at which this representation was received.
  final DateTime fetchedAt;

  static final RegExp _digest = RegExp(r'^[a-f0-9]{64}$');
  static final RegExp _strongEtag = RegExp(r'^"[a-f0-9]{64}"$');
}

/// A validated dynamic OpenAPI document and its server cache identity.
final class KumweOpenApiContract {
  /// Creates a caller-specific contract representation.
  KumweOpenApiContract({required this.document, required this.metadata}) {
    final embeddedGeneration = document['x-kumwe-business-generation'];
    if (embeddedGeneration != metadata.generation) {
      throw ArgumentError.value(
        embeddedGeneration,
        'document',
        'The embedded business generation must match response metadata.',
      );
    }
  }

  /// Immutable OpenAPI JSON document.
  final KumweJsonObject document;

  /// Generation, entity tag, and fetch time returned with [document].
  final KumweContractMetadata metadata;
}

/// Result of a conditional contract read.
final class KumweContractFetchResult {
  /// Creates a result returned from the network or a validated cache entry.
  const KumweContractFetchResult({
    required this.contract,
    required this.notModified,
  });

  /// Current caller-specific contract.
  final KumweOpenApiContract contract;

  /// Whether Kumwe answered `304 Not Modified` and the cached body was reused.
  final bool notModified;
}
