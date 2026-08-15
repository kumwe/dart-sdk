import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../http/header_map.dart';
import '../http/kumwe_request.dart';
import '../http/kumwe_response.dart';
import '../http/kumwe_transport.dart';

/// A Kumwe transport backed by `package:http`.
final class HttpKumweTransport implements KumweTransport {
  /// Creates a transport.
  ///
  /// When [client] is omitted, this object owns the created client and closes it
  /// from [close]. An injected client remains owned by its caller.
  HttpKumweTransport({
    http.Client? client,
    int maxResponseBytes = 16 * 1024 * 1024,
  }) : _maxResponseBytes = _validateLimit(maxResponseBytes),
       _client = client ?? http.Client(),
       _ownsClient = client == null;

  final int _maxResponseBytes;
  final http.Client _client;
  final bool _ownsClient;
  bool _closed = false;

  /// Releases an internally created HTTP client.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    if (_ownsClient) {
      _client.close();
    }
  }

  @override
  Future<KumweResponse> send(KumweRequest request) async {
    if (_closed) {
      throw const KumweTransportException('The HTTP transport is closed.');
    }
    try {
      final outgoing = http.Request(request.method.wireName, request.uri)
        ..headers.addAll(request.headers.toMap())
        ..followRedirects = false
        ..bodyBytes = request.body;
      final streamed = await _client.send(outgoing);
      final declaredLength = streamed.contentLength;
      if (declaredLength != null && declaredLength > _maxResponseBytes) {
        throw KumweTransportException(
          'The HTTP response exceeds the configured byte limit.',
        );
      }
      final bytes = BytesBuilder(copy: false);
      var received = 0;
      await for (final chunk in streamed.stream) {
        received += chunk.length;
        if (received > _maxResponseBytes) {
          throw KumweTransportException(
            'The HTTP response exceeds the configured byte limit.',
          );
        }
        bytes.add(chunk);
      }
      return KumweResponse(
        statusCode: streamed.statusCode,
        headers: HeaderMap(streamed.headers),
        body: bytes.takeBytes(),
      );
    } on KumweTransportException {
      rethrow;
    } on Object catch (error) {
      throw KumweTransportException(
        'The HTTP request did not produce a response.',
        error,
      );
    }
  }

  static int _validateLimit(int value) {
    if (value <= 0) {
      throw ArgumentError.value(
        value,
        'maxResponseBytes',
        'The response byte limit must be positive.',
      );
    }
    return value;
  }
}
