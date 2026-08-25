import 'package:kumwe_sdk/kumwe_sdk.dart';

void main() {
  final origin = Uri.parse('https://cms.example.invalid');
  final cred1 = KumweCredentialReference('credential-0001');
  final cred2 = KumweCredentialReference('credential-0002');

  final p1 = KumweAuthorityPartition(
    origin: origin,
    site: 'corporate',
    credential: cred1,
    generations: {'policy_generation': '7'},
  );
  // Session rejected cred1, refreshed to cred2; policy generation moved 7->8.
  final p2 = KumweAuthorityPartition(
    origin: origin,
    site: 'corporate',
    credential: cred2,
    generations: {'policy_generation': '8'},
  );

  print('scopes equal: ${p1.scope == p2.scope}');

  final cache = KumweRuntimeCache<String>();
  cache.adopt(p1);
  cache.write(p1, 'definition/invoice', 'pre-policy-change-disclosure');

  // Normal recovery: session adopts the rotated token's partition.
  cache.adopt(p2);

  final leaked = cache.read(p1, 'definition/invoice');
  print('read under superseded credential after rotation: $leaked');
  print('entries still held: ${cache.length}');

  // Contrast: same-credential generation move (the tested path) does drop.
  final cache2 = KumweRuntimeCache<String>();
  final q1 = KumweAuthorityPartition(
    origin: origin, site: 'corporate', credential: cred1,
    generations: {'policy_generation': '7'},
  );
  final q2 = KumweAuthorityPartition(
    origin: origin, site: 'corporate', credential: cred1,
    generations: {'policy_generation': '8'},
  );
  cache2.adopt(q1);
  cache2.write(q1, 'definition/invoice', 'pre-policy-change-disclosure');
  cache2.adopt(q2);
  print('same-credential move read: ${cache2.read(q1, 'definition/invoice')}');
  print('same-credential move entries: ${cache2.length}');

  // Write again under the dead scope: is it accepted (still "live")?
  cache.write(p1, 'another', 'written-after-credential-invalidated');
  print('stale-scope write accepted: ${cache.read(p1, 'another')}');
}
