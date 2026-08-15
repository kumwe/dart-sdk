import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('parses canonical wire literals and derives their scale', () {
    expect(KumweDecimal.parse('0').scale, 0);
    expect(KumweDecimal.parse('19.95').value, '19.95');
    expect(KumweDecimal.parse('19.95').scale, 2);
    expect(KumweDecimal.parse('-12.500').scale, 3);
    expect(KumweDecimal.parse('0.00').isZero, isTrue);
    expect(KumweDecimal.parse('-12.500').isNegative, isTrue);
  });

  test('rejects non-canonical wire literals instead of repairing them', () {
    const violations = [
      '',
      ' 1',
      '1 ',
      '+1',
      '01',
      '1.',
      '.5',
      '1e3',
      '1E3',
      '0x10',
      '1,5',
      '--1',
      'NaN',
      'Infinity',
      '-0',
      '-0.00',
    ];
    for (final value in violations) {
      expect(
        () => KumweDecimal.parse(value),
        throwsFormatException,
        reason: value,
      );
    }
  });

  test('canonicalizes application literals against a field contract', () {
    final padded = KumweDecimal.forField('19.9', precision: 10, scale: 2);
    expect(padded.value, '19.90');
    expect(padded.scale, 2);
    expect(
      KumweDecimal.forField('-0.0', precision: 10, scale: 2).value,
      '0.00',
    );
    expect(KumweDecimal.forField('7', precision: 5, scale: 0).value, '7');
    expect(KumweDecimal.fromInt(-42, precision: 10, scale: 3).value, '-42.000');
  });

  test('enforces field precision, scale, and range bounds', () {
    expect(
      () => KumweDecimal.forField('1.234', precision: 10, scale: 2),
      throwsFormatException,
    );
    expect(
      () => KumweDecimal.forField('1234', precision: 5, scale: 2),
      throwsFormatException,
    );
    expect(
      () => KumweDecimal.forField('1', precision: 0, scale: 0),
      throwsArgumentError,
    );
    expect(
      () => KumweDecimal.forField('1', precision: 66, scale: 0),
      throwsArgumentError,
    );
    expect(
      () => KumweDecimal.forField('1', precision: 5, scale: 6),
      throwsArgumentError,
    );
  });

  test('orders values of one scale exactly, beyond float precision', () {
    final smaller = KumweDecimal.parse('12345678901234567890.10');
    final larger = KumweDecimal.parse('12345678901234567890.11');
    expect(smaller.compareTo(larger), isNegative);
    expect(larger.compareTo(smaller), isPositive);
    expect(smaller.compareTo(KumweDecimal.parse('12345678901234567890.10')), 0);
    expect(
      KumweDecimal.parse('-2.00').compareTo(KumweDecimal.parse('-10.00')),
      isPositive,
    );
    expect(
      KumweDecimal.parse('-1.00').compareTo(KumweDecimal.parse('1.00')),
      isNegative,
    );
    expect(
      KumweDecimal.parse('9.50').compareTo(KumweDecimal.parse('11.00')),
      isNegative,
    );
  });

  test('refuses to order values from different field scales', () {
    expect(
      () => KumweDecimal.parse('1.00').compareTo(KumweDecimal.parse('1.000')),
      throwsArgumentError,
    );
  });

  test('round-trips the canonical literal without float conversion', () {
    final value = KumweDecimal.parse('99999999999999999999999999999999.99');
    expect(value.toJson(), '99999999999999999999999999999999.99');
    expect(value.toString(), value.value);
    expect(value, KumweDecimal.parse('99999999999999999999999999999999.99'));
  });
}
