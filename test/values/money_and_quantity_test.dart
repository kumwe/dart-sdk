import 'package:kumwe_sdk/kumwe_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('money binds an exact amount to a three-letter currency', () {
    final price = KumweMoney(
      amount: KumweDecimal.parse('19.95'),
      currency: 'NAD',
    );
    expect(price.toJson(), {'amount': '19.95', 'currency': 'NAD'});
    expect(price, KumweMoney.fromJson({'amount': '19.95', 'currency': 'NAD'}));
  });

  test('money rejects non-ISO currency forms', () {
    for (final currency in ['', 'nad', 'NAD ', 'NADX', 'N\$', 'NA']) {
      expect(
        () =>
            KumweMoney(amount: KumweDecimal.parse('1.00'), currency: currency),
        throwsArgumentError,
        reason: currency,
      );
    }
  });

  test('money rejects open or mistyped wire objects', () {
    expect(
      () => KumweMoney.fromJson({'amount': '1.00'}),
      throwsFormatException,
    );
    expect(
      () => KumweMoney.fromJson({
        'amount': '1.00',
        'currency': 'NAD',
        'rounding': 'half-up',
      }),
      throwsFormatException,
    );
    expect(
      () => KumweMoney.fromJson({'amount': 1.0, 'currency': 'NAD'}),
      throwsFormatException,
    );
  });

  test('quantity binds an exact amount to a bounded portable unit', () {
    final speed = KumweQuantity(amount: KumweDecimal.parse('3.6'), unit: 'm/s');
    expect(speed.toJson(), {'amount': '3.6', 'unit': 'm/s'});
    expect(speed, KumweQuantity.fromJson({'amount': '3.6', 'unit': 'm/s'}));
  });

  test('quantity rejects unbounded or unsupported unit identifiers', () {
    for (final unit in ['', ' kg', 'k g', '/kg', 'a' * 64, 'kg™']) {
      expect(
        () => KumweQuantity(amount: KumweDecimal.parse('1'), unit: unit),
        throwsArgumentError,
        reason: unit,
      );
    }
    expect(
      () => KumweQuantity.fromJson({'amount': '1', 'unit': 'kg', 'x': true}),
      throwsFormatException,
    );
  });

  test('exact pairs never expose double conversion', () {
    final price = KumweMoney(
      amount: KumweDecimal.parse('0.10'),
      currency: 'EUR',
    );
    expect(price.amount.value, '0.10');
    expect(price.toJson()['amount'], '0.10');
  });
}
