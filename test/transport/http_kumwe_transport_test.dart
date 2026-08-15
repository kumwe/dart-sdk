import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'adapts request and response data without exposing package:http',
    () async {
      final mock = MockClient((incoming) async {
        expect(incoming.method, 'POST');
        expect(incoming.url, Uri.parse('https://kumwe.test/api/v1/example'));
        expect(incoming.headers['content-type'], 'application/json');
        expect(incoming.followRedirects, isFalse);
        expect(incoming.bodyBytes, <int>[123, 125]);
        return http.Response.bytes(
          <int>[111, 107],
          202,
          headers: {'Content-Type': 'text/plain', 'ETag': '"v1"'},
        );
      });
      final transport = HttpKumweTransport(client: mock);

      final response = await transport.send(
        KumweRequest(
          method: KumweHttpMethod.post,
          uri: Uri.parse('https://kumwe.test/api/v1/example'),
          headers: HeaderMap({'Content-Type': 'application/json'}),
          body: <int>[123, 125],
        ),
      );

      expect(response.statusCode, 202);
      expect(response.text, 'ok');
      expect(response.headers['etag'], '"v1"');
    },
  );

  test('fails locally after the transport is closed', () async {
    final transport = HttpKumweTransport(
      client: MockClient((_) async => http.Response('', 200)),
    );
    transport.close();

    await expectLater(
      transport.send(
        KumweRequest(
          method: KumweHttpMethod.get,
          uri: Uri.parse('https://kumwe.test/health/live'),
        ),
      ),
      throwsA(isA<KumweTransportException>()),
    );
  });

  test('stops reading responses that exceed the configured bound', () async {
    final transport = HttpKumweTransport(
      client: MockClient(
        (_) async => http.Response.bytes(<int>[1, 2, 3, 4], 200),
      ),
      maxResponseBytes: 3,
    );

    await expectLater(
      transport.send(
        KumweRequest(
          method: KumweHttpMethod.get,
          uri: Uri.parse('https://kumwe.test/api/v1'),
        ),
      ),
      throwsA(
        isA<KumweTransportException>().having(
          (error) => error.message,
          'message',
          contains('byte limit'),
        ),
      ),
    );
    expect(
      () => HttpKumweTransport(
        client: MockClient((_) async => http.Response('', 200)),
        maxResponseBytes: 0,
      ),
      throwsArgumentError,
    );
  });
}
