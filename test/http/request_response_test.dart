import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'request and response bodies cannot be mutated through the public API',
    () {
      final source = <int>[1, 2, 3];
      final request = KumweRequest(
        method: KumweHttpMethod.post,
        uri: Uri.parse('https://kumwe.test/api/v1/example'),
        body: source,
      );
      final response = KumweResponse(statusCode: 200, body: source);
      source[0] = 9;

      expect(request.body, <int>[1, 2, 3]);
      expect(response.body, <int>[1, 2, 3]);
      expect(() => request.body[0] = 8, throwsUnsupportedError);
      expect(() => response.body.add(4), throwsUnsupportedError);
    },
  );

  test('response status codes must use the HTTP three-digit range', () {
    expect(() => KumweResponse(statusCode: 99), throwsArgumentError);
    expect(() => KumweResponse(statusCode: 600), throwsArgumentError);
    expect(KumweResponse(statusCode: 503).statusCode, 503);
  });

  test('request and response bodies reject values outside one byte', () {
    expect(
      () => KumweRequest(
        method: KumweHttpMethod.post,
        uri: Uri.parse('https://kumwe.test/api/v1/example'),
        body: const [-1],
      ),
      throwsArgumentError,
    );
    expect(
      () => KumweResponse(statusCode: 200, body: const [256]),
      throwsArgumentError,
    );
  });
}
