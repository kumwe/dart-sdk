import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  const generation =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const checksum =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  test('binds an OpenAPI document to its server generation', () {
    final metadata = KumweContractMetadata(
      generation: generation,
      etag: '"$checksum"',
      fetchedAt: DateTime.parse('2026-08-15T12:00:00+02:00'),
    );
    final contract = KumweOpenApiContract(
      document: KumweJsonObject.from({
        'openapi': '3.1.0',
        'x-kumwe-business-generation': generation,
      }),
      metadata: metadata,
    );

    expect(contract.metadata.fetchedAt.isUtc, isTrue);
    expect(
      contract.metadata.fetchedAt.toIso8601String(),
      '2026-08-15T10:00:00.000Z',
    );
  });

  test('rejects malformed or inconsistent identities', () {
    expect(
      () => KumweContractMetadata(
        generation: 'not-a-digest',
        etag: '"$checksum"',
        fetchedAt: DateTime.now(),
      ),
      throwsArgumentError,
    );
    final metadata = KumweContractMetadata(
      generation: generation,
      etag: '"$checksum"',
      fetchedAt: DateTime.now(),
    );
    expect(
      () => KumweOpenApiContract(
        document: KumweJsonObject.from({
          'openapi': '3.1.0',
          'x-kumwe-business-generation': checksum,
        }),
        metadata: metadata,
      ),
      throwsArgumentError,
    );
  });

  test('in-memory cache isolates authorization partitions', () async {
    final cache = InMemoryKumweContractCache();
    final metadata = KumweContractMetadata(
      generation: generation,
      etag: '"$checksum"',
      fetchedAt: DateTime.now(),
    );
    final contract = KumweOpenApiContract(
      document: KumweJsonObject.from({
        'openapi': '3.1.0',
        'x-kumwe-business-generation': generation,
      }),
      metadata: metadata,
    );
    final first = KumweContractCacheKey(
      baseUri: Uri.parse('https://kumwe.test/'),
      site: 'default',
      authorizationPartition: 'actor-a',
    );
    final second = KumweContractCacheKey(
      baseUri: Uri.parse('https://kumwe.test/'),
      site: 'default',
      authorizationPartition: 'actor-b',
    );

    await cache.write(first, contract);

    expect(await cache.read(first), same(contract));
    expect(await cache.read(second), isNull);
    await cache.remove(first);
    expect(await cache.read(first), isNull);
  });
}
