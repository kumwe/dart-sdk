import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

final class _ResponseClient extends http.BaseClient {
  _ResponseClient(this.response);

  final http.StreamedResponse response;
  int closed = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      response;

  @override
  void close() => closed++;
}

KumweRequest _request() => KumweRequest(
  method: KumweHttpMethod.get,
  uri: Uri.parse('https://cms.example.invalid/api/v1'),
);

void main() {
  test('an oversized declared body releases its unconsumed stream', () async {
    var cancelled = 0;
    final stream = StreamController<List<int>>(onCancel: () => cancelled++);
    final client = _ResponseClient(
      http.StreamedResponse(stream.stream, 200, contentLength: 4),
    );
    final transport = HttpKumweTransport(client: client, maxResponseBytes: 3);
    await expectLater(
      transport.send(_request()),
      throwsA(isA<KumweTransportException>()),
    );
    expect(
      cancelled,
      1,
      reason: 'header refusal must release transport resources without waiting for body bytes',
    );
    transport.close();
    expect(
      client.closed,
      0,
      reason: 'an injected client remains application-owned',
    );
    unawaited(stream.close());
  });

  test(
    'a chunk crossing the limit cancels further response delivery',
    () async {
      var cancelled = 0;
      late StreamController<List<int>> stream;
      stream = StreamController<List<int>>(
        onListen: () => stream.add([1, 2, 3, 4]),
        onCancel: () => cancelled++,
      );
      final transport = HttpKumweTransport(
        client: _ResponseClient(http.StreamedResponse(stream.stream, 200)),
        maxResponseBytes: 3,
      );
      await expectLater(
        transport.send(_request()),
        throwsA(isA<KumweTransportException>()),
      );
      expect(cancelled, 1);
      unawaited(stream.close());
    },
  );

  test('the exact response byte ceiling succeeds across chunks', () async {
    final transport = HttpKumweTransport(
      client: _ResponseClient(
        http.StreamedResponse(
          Stream.fromIterable([
            [1],
            [2, 3],
          ]),
          200,
        ),
      ),
      maxResponseBytes: 3,
    );
    expect((await transport.send(_request())).body, [1, 2, 3]);
  });
}
