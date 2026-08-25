import '../json/canonical_json.dart';
import '../json/kumwe_json.dart';
import '../result/kumwe_result.dart';
import 'entity_tag.dart';
import 'idempotency_key.dart';

/// One mutation intent, canonicalized exactly once.
///
/// The intent freezes the canonical bytes of its body and binds them to one
/// idempotency key at construction, so every retry of this intent reuses the
/// identical bytes, key and precondition by construction — a changed body
/// can never travel under an old key, because an intent is immutable and a
/// new body means a new intent with a new key.
final class KumweMutationIntent {
  /// Canonicalizes [body] and binds it to a fresh or supplied [key].
  ///
  /// Throws [FormatException] when the body cannot be canonicalized, for
  /// example because it carries a binary floating-point number where the
  /// contract expects an exact value string.
  factory KumweMutationIntent({
    required KumweJsonValue body,
    IdempotencyKey? key,
    EntityTag? ifMatch,
  }) {
    final bytes = KumweCanonicalJson.encode(body);
    return KumweMutationIntent._(
      canonicalBytes: bytes,
      bodyDigest: KumweCanonicalJson.sha256Hex(body),
      key: key ?? IdempotencyKey.generate(),
      ifMatch: ifMatch,
    );
  }

  const KumweMutationIntent._({
    required this.canonicalBytes,
    required this.bodyDigest,
    required this.key,
    required this.ifMatch,
  });

  /// Canonical UTF-8 request bytes, identical on every retry.
  final List<int> canonicalBytes;

  /// Lowercase hexadecimal SHA-256 digest of [canonicalBytes].
  final String bodyDigest;

  /// Caller-minted key retained until the terminal result is known.
  final IdempotencyKey key;

  /// Strong precondition for existing-resource mutations, when required.
  final EntityTag? ifMatch;

  /// Headers this intent contributes to its request.
  Map<String, String> headers() {
    return {
      IdempotencyKey.headerName: key.value,
      if (ifMatch != null) 'If-Match': ifMatch!.value,
    };
  }

  /// Whether [candidate] carries byte-identical canonical content, so a
  /// retry under this intent's key is provably the same operation.
  bool matches(KumweJsonValue candidate) {
    try {
      return KumweCanonicalJson.sha256Hex(candidate) == bodyDigest;
    } on FormatException {
      return false;
    }
  }

  @override
  String toString() =>
      'KumweMutationIntent(key: ${key.value}, '
      '${canonicalBytes.length} canonical bytes)';
}

/// How one mutation attempt terminated.
enum KumweMutationDisposition {
  /// The server applied the mutation now.
  applied,

  /// The server replayed the stored response of an earlier identical
  /// attempt; the mutation happened once, earlier.
  replayed,

  /// The attempt failed with an expected API problem.
  refused,

  /// The transport failed after the request may have reached the server,
  /// or the server answered with an error that leaves the commit state
  /// unknown; the mutation may or may not have committed. The intent and
  /// key are retained, and only an identical retry or an operation-status
  /// read may settle the question — never a fresh key.
  ambiguous,
}

/// Terminal knowledge about one mutation attempt.
///
/// An outcome never reports "not applied" without server evidence: a
/// transport failure after send becomes [KumweMutationDisposition.ambiguous]
/// and keeps the intent alive for an identical retry.
final class KumweMutationOutcome<T> {
  /// Classifies a successful exchange from its [metadata].
  factory KumweMutationOutcome.fromSuccess(
    T value,
    KumweResponseMetadata metadata,
  ) {
    return KumweMutationOutcome._(
      disposition: metadata.idempotencyReplayed
          ? KumweMutationDisposition.replayed
          : KumweMutationDisposition.applied,
      result: KumweResult<T>.success(value, metadata),
    );
  }

  /// Wraps an expected API refusal.
  factory KumweMutationOutcome.fromProblem(KumweResult<T> result) {
    if (result is! KumweProblemResult<T>) {
      throw ArgumentError.value(
        result,
        'result',
        'A refused outcome wraps a problem result.',
      );
    }
    return KumweMutationOutcome._(
      disposition: KumweMutationDisposition.refused,
      result: result,
    );
  }

  /// Marks an attempt whose commit state is unknown.
  const KumweMutationOutcome.ambiguous()
    : disposition = KumweMutationDisposition.ambiguous,
      result = null;

  /// Marks an attempt a server error left in an unknown commit state,
  /// keeping the server's problem report beside the ambiguity.
  ///
  /// A 5xx answer is not evidence of refusal: an intermediary or a core
  /// that failed mid-request may have answered after the mutation
  /// committed, so the intent stays alive for an identical retry while
  /// the problem still carries the declared retry guidance.
  factory KumweMutationOutcome.ambiguousServerError(KumweResult<T> result) {
    if (result is! KumweProblemResult<T>) {
      throw ArgumentError.value(
        result,
        'result',
        'An ambiguous server error wraps a problem result.',
      );
    }
    return KumweMutationOutcome._(
      disposition: KumweMutationDisposition.ambiguous,
      result: result,
    );
  }

  const KumweMutationOutcome._({
    required this.disposition,
    required this.result,
  });

  /// How the attempt terminated.
  final KumweMutationDisposition disposition;

  /// The operation result; `null` only for an ambiguous attempt whose
  /// transport failed outright. An ambiguous attempt answered with a
  /// server error keeps that problem here.
  final KumweResult<T>? result;

  /// Whether the mutation is known to have taken effect, now or earlier.
  bool get isCommitted =>
      disposition == KumweMutationDisposition.applied ||
      disposition == KumweMutationDisposition.replayed;

  @override
  String toString() => 'KumweMutationOutcome(${disposition.name})';
}
