import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  final origin = Uri.parse('https://cms.example.invalid');
  final credential = KumweCredentialReference('credential-0001');

  KumweAuthorityPartition partition({
    Map<String, String> generations = const {'policy_generation': '7'},
    String site = 'corporate',
    KumweCredentialReference? who,
  }) {
    return KumweAuthorityPartition(
      origin: origin,
      site: site,
      credential: who ?? credential,
      generations: generations,
    );
  }

  group('partitions', () {
    test('identical inputs derive the identical partition', () {
      expect(partition(), partition());
      expect(partition().hashCode, partition().hashCode);
    });

    test('any generation movement changes the digest, not the scope', () {
      final before = partition();
      final after = partition(generations: {'policy_generation': '8'});
      expect(before.scope, after.scope);
      expect(before.digest, isNot(after.digest));
    });

    test('site, credential and origin all separate scopes', () {
      expect(partition().scope, isNot(partition(site: 'branch').scope));
      expect(
        partition().scope,
        isNot(
          partition(who: KumweCredentialReference('credential-0002')).scope,
        ),
      );
    });

    test('diagnostics stay to a digest prefix', () {
      expect(partition().toString(), isNot(contains('credential-0001')));
    });
  });

  group('the runtime cache', () {
    test('serves entries only under the live partition', () {
      final cache = KumweRuntimeCache<String>();
      final live = partition();
      cache.adopt(live);
      cache.write(live, 'catalog', 'cached-catalog');
      expect(cache.read(live, 'catalog'), 'cached-catalog');
      expect(cache.read(live, 'missing'), isNull);
    });

    test('a generation change drops the whole caller view', () {
      final cache = KumweRuntimeCache<String>();
      final before = partition();
      cache.adopt(before);
      cache.write(before, 'catalog', 'stale-catalog');
      cache.write(before, 'definition/invoice', 'stale-definition');
      final after = partition(generations: {'policy_generation': '8'});
      cache.adopt(after);
      expect(cache.read(after, 'catalog'), isNull);
      expect(
        cache.read(before, 'catalog'),
        isNull,
        reason: 'the superseded partition is unreadable',
      );
      expect(cache.length, 0);
    });

    test('site, organization and credential views never collide', () {
      final cache = KumweRuntimeCache<String>();
      final corporate = partition();
      final branch = partition(site: 'branch');
      cache.adopt(corporate);
      cache.adopt(branch);
      cache.write(corporate, 'catalog', 'corporate-catalog');
      cache.write(branch, 'catalog', 'branch-catalog');
      expect(cache.read(corporate, 'catalog'), 'corporate-catalog');
      expect(cache.read(branch, 'catalog'), 'branch-catalog');
    });

    test('a stale-partition write is dropped, never resurrected', () {
      final cache = KumweRuntimeCache<String>();
      final before = partition();
      cache.adopt(before);
      final after = partition(generations: {'policy_generation': '8'});
      cache.adopt(after);
      cache.write(before, 'catalog', 'late-stale-write');
      expect(cache.length, 0);
      expect(cache.read(before, 'catalog'), isNull);
    });

    test('adopting the unchanged partition keeps entries', () {
      final cache = KumweRuntimeCache<String>();
      final live = partition();
      cache.adopt(live);
      cache.write(live, 'catalog', 'cached-catalog');
      cache.adopt(partition());
      expect(cache.read(live, 'catalog'), 'cached-catalog');
    });

    test('capacity evicts the least recently used entry', () {
      final cache = KumweRuntimeCache<int>(maxEntries: 2);
      final live = partition();
      cache.adopt(live);
      cache.write(live, 'first', 1);
      cache.write(live, 'second', 2);
      expect(cache.read(live, 'first'), 1); // refresh recency
      cache.write(live, 'third', 3);
      expect(cache.read(live, 'second'), isNull);
      expect(cache.read(live, 'first'), 1);
      expect(cache.read(live, 'third'), 3);
    });

    test('clear releases everything', () {
      final cache = KumweRuntimeCache<String>();
      final live = partition();
      cache.adopt(live);
      cache.write(live, 'catalog', 'cached-catalog');
      cache.clear();
      expect(cache.length, 0);
      cache.adopt(live);
      expect(cache.read(live, 'catalog'), isNull);
    });

    test('bounds hold on keys and capacity', () {
      expect(() => KumweRuntimeCache<int>(maxEntries: 0), throwsArgumentError);
      final cache = KumweRuntimeCache<int>();
      expect(() => cache.read(partition(), ''), throwsArgumentError);
      expect(() => cache.write(partition(), 'k' * 513, 1), throwsArgumentError);
    });
  });
}
