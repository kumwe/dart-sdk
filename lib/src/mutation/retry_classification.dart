import '../http/kumwe_response.dart';

/// How a failed operation may be retried safely.
///
/// The vocabulary matches the proposed stable problem-code registry. Until
/// core adopts that registry (`CORE-API-002`), classification is derived only
/// from generic HTTP semantics and is deliberately conservative: an outcome
/// whose safety cannot be proven is [unspecified], never a silent retry.
enum KumweRetryClass {
  /// The same request will keep failing; correct it before retrying.
  never,

  /// The request may be retried after the advertised or a backed-off delay,
  /// keeping the identical bytes, context and idempotency key.
  afterDelay,

  /// The credential must be refreshed or reissued once before one retry;
  /// a second authentication failure terminates the attempt.
  afterReauthentication,

  /// The precondition is stale: re-read the resource, then decide with the
  /// fresh entity tag or version.
  afterPreconditionRefresh,

  /// The classification cannot be proven from generic HTTP semantics.
  unspecified,
}

/// Conservative HTTP-layer retry classification.
///
/// The classifier never inspects problem `detail` text and never fabricates
/// stable problem codes. A `409` stays [KumweRetryClass.unspecified] because
/// the audited core uses it both for retryable in-progress conflicts and for
/// permanent idempotency-key reuse, which only a stable code can separate.
final class KumweRetryClassifier {
  /// Creates the stateless classifier.
  const KumweRetryClassifier();

  /// Classifies [response] from its status code alone.
  KumweRetryClass classify(KumweResponse response) {
    return switch (response.statusCode) {
      401 => KumweRetryClass.afterReauthentication,
      408 || 425 || 429 || 502 || 503 || 504 => KumweRetryClass.afterDelay,
      412 || 428 => KumweRetryClass.afterPreconditionRefresh,
      400 ||
      403 ||
      404 ||
      405 ||
      406 ||
      410 ||
      413 ||
      414 ||
      415 ||
      422 => KumweRetryClass.never,
      _ => KumweRetryClass.unspecified,
    };
  }

  /// Reads a delta-seconds `Retry-After` header as a duration.
  ///
  /// Returns `null` when the header is absent or uses a form other than
  /// non-negative delta seconds; HTTP-date parsing needs a trusted clock and
  /// belongs to the application.
  Duration? retryAfter(KumweResponse response) {
    final value = response.headers['retry-after']?.trim();
    if (value == null || !RegExp(r'^[0-9]{1,9}$').hasMatch(value)) {
      return null;
    }
    return Duration(seconds: int.parse(value));
  }
}
