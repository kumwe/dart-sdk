import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('idempotency keys enforce the audited header contract', () {
    expect(IdempotencyKey('intent-0001').value, 'intent-0001');
    expect(IdempotencyKey('a1b2c3d4').value, 'a1b2c3d4');
    for (final value in [
      '',
      'short7c',
      '-startsdash',
      '.startsdot',
      'has space',
      'has/slash',
      'a' * 129,
    ]) {
      expect(() => IdempotencyKey(value), throwsArgumentError, reason: value);
    }
  });

  test('generated idempotency keys are valid, distinct, and high entropy', () {
    final first = IdempotencyKey.generate();
    final second = IdempotencyKey.generate();
    expect(first.value.length, 64);
    expect(IdempotencyKey(first.value), first);
    expect(first, isNot(second));
  });

  test('idempotency header names match the audited wire contract', () {
    expect(IdempotencyKey.headerName, 'Idempotency-Key');
    expect(IdempotencyKey.replayedHeaderName, 'Idempotency-Replayed');
  });

  test('entity tags accept strong validators and surface record versions', () {
    final tag = EntityTag('"v3"');
    expect(tag.recordVersion, 3);
    expect(tag.value, '"v3"');
    expect(EntityTag.recordVersion(12), EntityTag('"v12"'));
    expect(EntityTag('"abc123"').recordVersion, isNull);
    expect(EntityTag('""').value, '""');
    expect(EntityTag('"café"').value, '"café"');
  });

  test('entity tags reject weak or malformed validators', () {
    for (final value in ['', 'v3', '"v3', 'v3"', 'W/"v3"', '"v 3"', '"a"b"']) {
      expect(() => EntityTag(value), throwsArgumentError, reason: value);
    }
    expect(() => EntityTag.recordVersion(0), throwsArgumentError);
    expect(() => EntityTag.recordVersion(-1), throwsArgumentError);
  });

  test('entity tags return null for record versions beyond exact integers', () {
    expect(EntityTag('"v9223372036854775808"').recordVersion, isNull);
    expect(EntityTag('"v${'9' * 19}"').recordVersion, isNull);
    expect(EntityTag('"v${'9' * 18}"').recordVersion, int.parse('9' * 18));
  });

  test('entity tag header names match the audited wire contract', () {
    expect(EntityTag.headerName, 'ETag');
    expect(EntityTag.ifMatchHeaderName, 'If-Match');
  });
}
