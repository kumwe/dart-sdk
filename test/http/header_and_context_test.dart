import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  group('HeaderMap', () {
    test('looks up and overlays names case-insensitively', () {
      final headers = HeaderMap({
        'Content-Type': 'application/json',
      }).overlay({'content-type': 'application/problem+json', 'ETag': '"v1"'});

      expect(headers['CONTENT-TYPE'], 'application/problem+json');
      expect(headers['etag'], '"v1"');
      expect(headers.length, 2);
      expect(() => headers.toMap()['new'] = 'value', throwsUnsupportedError);
    });

    test('rejects duplicate names and response splitting', () {
      expect(
        () => HeaderMap({'X-Test': 'one', 'x-test': 'two'}),
        throwsArgumentError,
      );
      expect(
        () => HeaderMap({'X-Test': 'safe\r\nInjected: value'}),
        throwsArgumentError,
      );
      expect(
        () => HeaderMap({'X-Test': 'unsafe\u0000value'}),
        throwsArgumentError,
      );
    });
  });

  group('KumweRequestContext', () {
    test('serializes validated protocol headers', () {
      final context = KumweRequestContext(
        requestId: 'client-request-0001',
        idempotencyKey: 'create-record-0001',
        ifMatch: '"v7"',
        ifNoneMatch: '"checksum"',
      );

      expect(context.toHeaders(), {
        'X-Request-ID': 'client-request-0001',
        'Idempotency-Key': 'create-record-0001',
        'If-Match': '"v7"',
        'If-None-Match': '"checksum"',
      });
    });

    test('rejects unsafe or weak values', () {
      expect(
        () => KumweRequestContext(requestId: 'short'),
        throwsArgumentError,
      );
      expect(
        () => KumweRequestContext(idempotencyKey: 'has spaces'),
        throwsArgumentError,
      );
      expect(() => KumweRequestContext(ifMatch: 'W/"v1"'), throwsArgumentError);
      expect(
        () => KumweRequestContext(ifNoneMatch: '"bad value"'),
        throwsArgumentError,
      );
    });
  });
}
