import 'dart:convert';

import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

import '../support/fake_transport.dart';

void main() {
  const generation =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const checksum =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('public discovery', () {
    test(
      'health probes use configured base routes without credentials',
      () async {
        final transport = FakeKumweTransport([
          _jsonResponse(200, {'status': 'alive', 'product': 'Kumwe CMS'}),
          _jsonResponse(200, {'status': 'ready'}),
        ]);
        final client = KumweClient(
          options: _options(authenticated: true),
          transport: transport,
        );
        expect((await client.liveness()).isAlive, isTrue);
        final readiness = await client.readiness();
        expect(readiness.isReady, isTrue);
        expect(readiness.state, KumweReadinessState.ready);
        expect(transport.requests.map((request) => request.uri.toString()), [
          'https://kumwe.test/cms/health/live',
          'https://kumwe.test/cms/health/ready',
        ]);
        for (final request in transport.requests) {
          expect(request.method, KumweHttpMethod.get);
          expect(request.headers['authorization'], isNull);
        }
      },
    );

    test(
      'liveness refuses malformed identity, status and HTTP outcome',
      () async {
        for (final (status, body, error)
            in <(int, Map<String, Object?>, Matcher)>[
              (
                200,
                {'status': 'alive', 'product': 'Another product'},
                isA<KumweProtocolException>(),
              ),
              (
                200,
                {'status': 'dead', 'product': 'Kumwe CMS'},
                isA<KumweProtocolException>(),
              ),
              (200, {'status': 'alive'}, isA<KumweProtocolException>()),
              (
                503,
                {'status': 'alive', 'product': 'Kumwe CMS'},
                isA<KumweApiException>(),
              ),
            ]) {
          final client = KumweClient(
            options: _options(),
            transport: FakeKumweTransport([_jsonResponse(status, body)]),
          );
          await expectLater(
            client.liveness(),
            throwsA(error),
            reason: '$status $body',
          );
        }
      },
    );

    test(
      'readiness refuses mismatched status/body and unexpected HTTP outcome',
      () async {
        for (final (status, body, error)
            in <(int, Map<String, Object?>, Matcher)>[
              (200, {'status': 'not_ready'}, isA<KumweProtocolException>()),
              (503, {'status': 'ready'}, isA<KumweProtocolException>()),
              (200, {'status': 'unknown'}, isA<KumweProtocolException>()),
              (200, {}, isA<KumweProtocolException>()),
              (404, {'status': 'ready'}, isA<KumweApiException>()),
            ]) {
          final client = KumweClient(
            options: _options(),
            transport: FakeKumweTransport([_jsonResponse(status, body)]),
          );
          await expectLater(
            client.readiness(),
            throwsA(error),
            reason: '$status $body',
          );
        }
      },
    );

    test('reads API identity beneath the configured base path', () async {
      final transport = FakeKumweTransport([
        _jsonResponse(200, {
          'product': 'Kumwe CMS',
          'api_version': 'v1',
          'status': 'available',
        }),
      ]);
      final client = KumweClient(options: _options(), transport: transport);

      final discovery = await client.discover();

      expect(discovery.product, 'Kumwe CMS');
      expect(discovery.apiVersion, 'v1');
      expect(
        transport.requests.single.uri,
        Uri.parse('https://kumwe.test/cms/api/v1'),
      );
      expect(
        transport.requests.single.headers['x-request-id'],
        'client-request-0001',
      );
      expect(transport.requests.single.headers['authorization'], isNull);
    });

    test('treats readiness 503 as a typed not-ready result', () async {
      final transport = FakeKumweTransport([
        _jsonResponse(503, {'status': 'not_ready'}),
      ]);
      final client = KumweClient(options: _options(), transport: transport);

      final readiness = await client.readiness();

      expect(readiness.isReady, isFalse);
      expect(readiness.state, KumweReadinessState.notReady);
    });

    test('rejects a superficially successful non-Kumwe document', () async {
      final transport = FakeKumweTransport([
        _jsonResponse(200, {
          'product': 'Another product',
          'api_version': 'v1',
          'status': 'available',
        }),
      ]);
      final client = KumweClient(options: _options(), transport: transport);

      await expectLater(
        client.discover(),
        throwsA(isA<KumweProtocolException>()),
      );
    });
  });

  group('OpenAPI contract', () {
    test('requires protected context when contract caching is enabled', () {
      expect(
        () => KumweClient(
          options: _options(),
          transport: FakeKumweTransport(const []),
          contractCache: InMemoryKumweContractCache(),
          authorizationPartition: 'actor-family-a',
        ),
        throwsArgumentError,
      );
    });

    test(
      'sends site-bound bearer auth and conditionally reuses cache',
      () async {
        final contractBody = <String, Object?>{
          'openapi': '3.1.0',
          'x-kumwe-business-generation': generation,
          'info': <String, Object?>{'title': 'Kumwe', 'version': '1.0.0'},
          'paths': <String, Object?>{},
        };
        final contractHeaders = HeaderMap({
          'Content-Type': 'application/vnd.oai.openapi+json;version=3.1',
          'ETag': '"$checksum"',
          'X-Kumwe-Contract-Generation': generation,
        });
        final transport = FakeKumweTransport([
          KumweResponse(
            statusCode: 200,
            headers: contractHeaders,
            body: utf8.encode(jsonEncode(contractBody)),
          ),
          KumweResponse(statusCode: 304, headers: contractHeaders),
        ]);
        final cache = InMemoryKumweContractCache();
        final client = KumweClient(
          options: _options(authenticated: true),
          transport: transport,
          contractCache: cache,
          authorizationPartition: 'actor-family-a',
        );

        final first = await client.fetchOpenApiContract();
        final second = await client.fetchOpenApiContract();

        expect(first.notModified, isFalse);
        expect(second.notModified, isTrue);
        expect(second.contract, same(first.contract));
        expect(
          transport.requests.first.headers['authorization'],
          'Bearer opaque-test-token',
        );
        expect(transport.requests.first.headers['kumwe-site'], 'default');
        expect(transport.requests.first.headers['if-none-match'], isNull);
        expect(transport.requests.last.headers['if-none-match'], '"$checksum"');
      },
    );

    test('requires both site and credential context', () async {
      final client = KumweClient(
        options: _options(),
        transport: FakeKumweTransport(const []),
      );

      await expectLater(
        client.fetchOpenApiContract(),
        throwsA(isA<KumweAuthenticationException>()),
      );
    });

    test('rejects a generation mismatch', () async {
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({
            'Content-Type': 'application/vnd.oai.openapi+json;version=3.1',
            'ETag': '"$checksum"',
            'X-Kumwe-Contract-Generation': generation,
          }),
          body: utf8.encode(
            jsonEncode({
              'openapi': '3.1.0',
              'x-kumwe-business-generation': checksum,
            }),
          ),
        ),
      ]);
      final client = KumweClient(
        options: _options(authenticated: true),
        transport: transport,
      );

      await expectLater(
        client.fetchOpenApiContract(),
        throwsA(isA<KumweProtocolException>()),
      );
    });

    test('rejects a contract with undeclared path parameters', () async {
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 200,
          headers: HeaderMap({
            'Content-Type': 'application/vnd.oai.openapi+json;version=3.1',
            'ETag': '"$checksum"',
            'X-Kumwe-Contract-Generation': generation,
          }),
          body: utf8.encode(
            jsonEncode({
              'openapi': '3.1.0',
              'x-kumwe-business-generation': generation,
              'info': {'title': 'Kumwe', 'version': '1.0.0'},
              'paths': {
                '/things/{id}': {
                  'get': {
                    'operationId': 'readThing',
                    'responses': {
                      '200': {'description': 'Okay'},
                    },
                  },
                },
              },
            }),
          ),
        ),
      ]);
      final client = KumweClient(
        options: _options(authenticated: true),
        transport: transport,
      );

      await expectLater(
        client.fetchOpenApiContract(),
        throwsA(isA<KumweProtocolException>()),
      );
    });

    test('revalidates a cached contract before accepting 304', () async {
      final invalidCachedContract = KumweOpenApiContract(
        document: KumweJsonObject.from({
          'openapi': '3.1.0',
          'x-kumwe-business-generation': generation,
          'info': {'title': 'Kumwe', 'version': '1.0.0'},
          'paths': {
            '/things/{id}': {
              'get': {
                'operationId': 'readThing',
                'responses': {
                  '200': {
                    'description': 'Okay',
                    'content': {
                      'application/json': {
                        'schema': {'type': 'object'},
                      },
                    },
                  },
                },
              },
            },
          },
        }),
        metadata: KumweContractMetadata(
          generation: generation,
          etag: '"$checksum"',
          fetchedAt: DateTime.utc(2026, 8, 15, 10),
        ),
      );
      final cache = InMemoryKumweContractCache();
      final options = _options(authenticated: true);
      await cache.write(
        KumweContractCacheKey(
          baseUri: options.baseUri,
          site: options.site!,
          authorizationPartition: 'actor-family-a',
        ),
        invalidCachedContract,
      );
      final transport = FakeKumweTransport([
        KumweResponse(
          statusCode: 304,
          headers: HeaderMap({
            'ETag': '"$checksum"',
            'X-Kumwe-Contract-Generation': generation,
          }),
        ),
      ]);
      final client = KumweClient(
        options: options,
        transport: transport,
        contractCache: cache,
        authorizationPartition: 'actor-family-a',
      );

      await expectLater(
        client.fetchOpenApiContract(),
        throwsA(isA<KumweProtocolException>()),
      );
    });
  });

  test('maps error responses to RFC 9457 exceptions', () async {
    final transport = FakeKumweTransport([
      KumweResponse(
        statusCode: 401,
        headers: HeaderMap({'Content-Type': 'application/problem+json'}),
        body: utf8.encode(
          jsonEncode({
            'type': 'urn:kumwe:problem:unauthorized',
            'title': 'Unauthorized',
            'status': 401,
          }),
        ),
      ),
    ]);
    final client = KumweClient(options: _options(), transport: transport);

    await expectLater(
      client.discover(),
      throwsA(
        isA<KumweApiException>().having(
          (error) => error.problem?.type,
          'problem type',
          'urn:kumwe:problem:unauthorized',
        ),
      ),
    );
  });
}

KumweClientOptions _options({bool authenticated = false}) {
  return KumweClientOptions(
    baseUri: Uri.parse('https://kumwe.test/cms'),
    site: authenticated ? 'default' : null,
    tokenProvider: authenticated
        ? StaticBearerTokenProvider('opaque-test-token')
        : null,
    requestIdFactory: () => 'client-request-0001',
    clock: () => DateTime.utc(2026, 8, 15, 10),
  );
}

KumweResponse _jsonResponse(int status, Map<String, Object?> body) {
  return KumweResponse(
    statusCode: status,
    headers: HeaderMap({'Content-Type': 'application/json'}),
    body: utf8.encode(jsonEncode(body)),
  );
}
