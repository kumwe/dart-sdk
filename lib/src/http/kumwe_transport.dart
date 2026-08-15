import 'kumwe_request.dart';
import 'kumwe_response.dart';

/// Sends transport-independent Kumwe requests.
abstract interface class KumweTransport {
  /// Sends [request] and returns its complete response.
  Future<KumweResponse> send(KumweRequest request);
}

/// A transport-level failure before an HTTP response was obtained.
final class KumweTransportException implements Exception {
  /// Creates a transport failure.
  const KumweTransportException(this.message, [this.cause]);

  /// Human-readable failure summary.
  final String message;

  /// Underlying platform or client failure.
  final Object? cause;

  @override
  String toString() => 'KumweTransportException: $message';
}
