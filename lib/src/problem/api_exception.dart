import '../http/kumwe_response.dart';
import 'problem_details.dart';

/// An HTTP response that did not satisfy an SDK operation.
final class KumweApiException implements Exception {
  /// Creates an API failure from [response].
  factory KumweApiException.fromResponse(KumweResponse response) {
    final problem = ProblemDetails.tryParse(response);
    return KumweApiException._(
      response: response,
      problem: problem,
      requestId:
          _safeRequestId(response.headers['x-request-id']) ??
          problem?.requestId,
    );
  }

  const KumweApiException._({
    required this.response,
    required this.problem,
    required this.requestId,
  });

  /// Complete response for recovery or diagnostics.
  final KumweResponse response;

  /// Parsed Problem Details document, when the server supplied a valid one.
  final ProblemDetails? problem;

  /// Correlation identity returned by Kumwe.
  final String? requestId;

  @override
  String toString() {
    final correlation = requestId == null ? '' : ' Request ID: $requestId.';
    return 'KumweApiException(${response.statusCode}): Request failed.$correlation';
  }

  static String? _safeRequestId(String? value) {
    return value != null && RegExp(r'^[A-Za-z0-9._-]{8,64}$').hasMatch(value)
        ? value
        : null;
  }
}

/// A successful HTTP exchange whose representation violates the SDK contract.
final class KumweProtocolException implements Exception {
  /// Creates a protocol failure.
  const KumweProtocolException(this.message, {this.response, this.cause});

  /// Failure summary.
  final String message;

  /// Response that violated the expected protocol, when available.
  final KumweResponse? response;

  /// Parsing or validation failure, when available.
  final Object? cause;

  @override
  String toString() => 'KumweProtocolException: $message';
}

/// No usable bearer token or site context was available for a protected call.
final class KumweAuthenticationException implements Exception {
  /// Creates a client-side authentication configuration failure.
  const KumweAuthenticationException(this.message);

  /// Failure summary.
  final String message;

  @override
  String toString() => 'KumweAuthenticationException: $message';
}
