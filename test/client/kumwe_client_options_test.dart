import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('normalizes site and preserves a reverse-proxy base path', () {
    final options = KumweClientOptions(
      baseUri: Uri.parse('https://example.test/kumwe'),
      site: ' Site.Default ',
      requestIdFactory: () => 'request-id-0001',
    );

    expect(options.baseUri, Uri.parse('https://example.test/kumwe/'));
    expect(options.site, 'site.default');
    expect(
      options.resolveRoute('/api/v1'),
      Uri.parse('https://example.test/kumwe/api/v1'),
    );
  });

  test('rejects ambiguous bases and routes', () {
    expect(
      () => KumweClientOptions(baseUri: Uri.parse('ftp://example.test')),
      throwsArgumentError,
    );
    expect(
      () => KumweClientOptions(baseUri: Uri.parse('http://example.test')),
      throwsArgumentError,
    );
    expect(
      KumweClientOptions(
        baseUri: Uri.parse('http://localhost:8080'),
        allowInsecureHttp: true,
      ).baseUri,
      Uri.parse('http://localhost:8080/'),
    );
    expect(
      () =>
          KumweClientOptions(baseUri: Uri.parse('https://user@example.test/')),
      throwsArgumentError,
    );
    final options = KumweClientOptions(
      baseUri: Uri.parse('https://example.test/'),
    );
    expect(
      () => options.resolveRoute('//attacker.test/path'),
      throwsArgumentError,
    );
    expect(() => options.resolveRoute('/path?query=yes'), throwsArgumentError);
    expect(() => options.resolveRoute('/%2e%2e/escape'), throwsArgumentError);
  });

  test('default request IDs satisfy the server correlation format', () {
    final options = KumweClientOptions(
      baseUri: Uri.parse('https://example.test/'),
    );

    expect(options.requestIdFactory(), matches(RegExp(r'^[a-f0-9]{32}$')));
  });
}
