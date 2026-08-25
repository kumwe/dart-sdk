import '../http/kumwe_response.dart';
import '../problem/kumwe_problem.dart';

/// Non-secret response facts carried beside a decoded success value.
final class KumweResponseMetadata {
  /// Creates validated response metadata.
  factory KumweResponseMetadata({
    required int statusCode,
    String? requestId,
    String? etag,
    bool idempotencyReplayed = false,
  }) {
    if (statusCode < 100 || statusCode > 599) {
      throw ArgumentError.value(
        statusCode,
        'statusCode',
        'HTTP status codes are between 100 and 599.',
      );
    }
    if (requestId != null && !_requestIdPattern.hasMatch(requestId)) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Correlation identifiers need 8 to 64 supported characters.',
      );
    }
    if (etag != null && (etag.isEmpty || etag.length > 256)) {
      throw ArgumentError.value(
        etag,
        'etag',
        'Entity tags need 1 to 256 characters.',
      );
    }
    return KumweResponseMetadata._(
      statusCode: statusCode,
      requestId: requestId,
      etag: etag,
      idempotencyReplayed: idempotencyReplayed,
    );
  }

  /// Extracts metadata from a transport [response].
  factory KumweResponseMetadata.fromResponse(KumweResponse response) {
    final requestId = response.headers['x-request-id'];
    return KumweResponseMetadata(
      statusCode: response.statusCode,
      requestId: requestId != null && _requestIdPattern.hasMatch(requestId)
          ? requestId
          : null,
      etag: response.headers['etag'],
      idempotencyReplayed:
          response.headers['idempotency-replayed']?.trim().toLowerCase() ==
          'true',
    );
  }

  const KumweResponseMetadata._({
    required this.statusCode,
    required this.requestId,
    required this.etag,
    required this.idempotencyReplayed,
  });

  /// HTTP status of the exchange.
  final int statusCode;

  /// Correlation identifier returned by Kumwe, when valid.
  final String? requestId;

  /// Raw entity tag header, when present.
  final String? etag;

  /// Whether Kumwe marked the response as a stored idempotent replay.
  final bool idempotencyReplayed;

  @override
  String toString() =>
      'KumweResponseMetadata($statusCode'
      '${requestId == null ? '' : ', request $requestId'}'
      '${idempotencyReplayed ? ', replayed' : ''})';

  static final RegExp _requestIdPattern = RegExp(r'^[A-Za-z0-9._-]{8,64}$');
}

/// The outcome of one SDK operation.
///
/// Expected API failures are data, not exceptions: authentication expiry,
/// denial, stale preconditions, validation and temporary unavailability all
/// arrive as [KumweProblemResult]. A service the current deployment or
/// contract state cannot offer answers [KumweUnsupportedResult] before any
/// request is sent. Programmer errors still throw.
sealed class KumweResult<T> {
  const KumweResult();

  /// Wraps a successful [value] with its [metadata].
  const factory KumweResult.success(T value, KumweResponseMetadata metadata) =
      KumweValueResult<T>;

  /// Wraps an expected API [problem].
  const factory KumweResult.problem(KumweProblem problem) =
      KumweProblemResult<T>;

  /// Marks the operation unavailable before any request was sent.
  const factory KumweResult.unsupported(KumweUnsupportedReason reason) =
      KumweUnsupportedResult<T>;

  /// The success value, or `null` for a failure or unsupported outcome.
  T? get valueOrNull => switch (this) {
    KumweValueResult<T>(:final value) => value,
    _ => null,
  };

  /// The problem, or `null` for a success or unsupported outcome.
  KumweProblem? get problemOrNull => switch (this) {
    KumweProblemResult<T>(:final problem) => problem,
    _ => null,
  };

  /// Whether this outcome carries a success value.
  bool get isSuccess => this is KumweValueResult<T>;

  /// Maps the success value while preserving failure and unsupported
  /// outcomes unchanged.
  KumweResult<R> map<R>(R Function(T value) transform) {
    return switch (this) {
      KumweValueResult<T>(:final value, :final metadata) => KumweValueResult<R>(
        transform(value),
        metadata,
      ),
      KumweProblemResult<T>(:final problem) => KumweProblemResult<R>(problem),
      KumweUnsupportedResult<T>(:final reason) => KumweUnsupportedResult<R>(
        reason,
      ),
    };
  }
}

/// A successful operation outcome.
final class KumweValueResult<T> extends KumweResult<T> {
  /// Creates a success carrying [value] and [metadata].
  const KumweValueResult(this.value, this.metadata);

  /// Decoded operation value.
  final T value;

  /// Non-secret response facts.
  final KumweResponseMetadata metadata;
}

/// An expected API failure outcome.
final class KumweProblemResult<T> extends KumweResult<T> {
  /// Creates a failure carrying [problem].
  const KumweProblemResult(this.problem);

  /// Stable-coded failure report.
  final KumweProblem problem;
}

/// Why an operation was unavailable before any request was sent.
enum KumweUnsupportedReason {
  /// The deployment has not adopted the contract the operation needs.
  contractNotAdopted,

  /// The deployment's discovery document does not advertise the capability.
  capabilityNotAdvertised,

  /// The current session's credential or context cannot host the operation.
  contextUnavailable,
}

/// A typed compatibility outcome: the operation cannot be offered.
final class KumweUnsupportedResult<T> extends KumweResult<T> {
  /// Creates an unsupported outcome for [reason].
  const KumweUnsupportedResult(this.reason);

  /// Why the operation is unavailable.
  final KumweUnsupportedReason reason;
}
