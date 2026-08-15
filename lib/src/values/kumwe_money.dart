import 'kumwe_decimal.dart';

/// An exact amount bound to the ISO 4217 currency it is denominated in.
///
/// The wire shape is the closed object `{"amount": string, "currency": string}`
/// with the amount as a canonical decimal literal. Nothing in this type
/// converts between currencies, and no arithmetic mixes two currencies.
final class KumweMoney {
  /// Binds [amount] to a three-letter uppercase ISO 4217 [currency] code.
  factory KumweMoney({required KumweDecimal amount, required String currency}) {
    if (!_currencyPattern.hasMatch(currency)) {
      throw ArgumentError.value(
        currency,
        'currency',
        'A currency must be exactly three uppercase ISO 4217 letters.',
      );
    }
    return KumweMoney._(amount, currency);
  }

  /// Parses the closed `{"amount", "currency"}` wire object.
  ///
  /// Unknown members are rejected: the wire contract is a closed object, so an
  /// extra member indicates a contract violation rather than an extension.
  /// Every wire violation on this path throws a [FormatException].
  factory KumweMoney.fromJson(Map<String, Object?> json) {
    final amount = json['amount'];
    final currency = json['currency'];
    if (json.length != 2 ||
        amount is! String ||
        currency is! String ||
        !_currencyPattern.hasMatch(currency)) {
      throw FormatException(
        'Money is the closed {"amount", "currency"} pair of a canonical '
        'decimal string and a three-letter ISO 4217 code.',
        json.toString(),
      );
    }
    return KumweMoney(amount: KumweDecimal.parse(amount), currency: currency);
  }

  const KumweMoney._(this.amount, this.currency);

  /// Exact amount in the currency's own units at the field scale.
  final KumweDecimal amount;

  /// Uppercase ISO 4217 alphabetic code, such as `NAD`.
  final String currency;

  /// Returns the canonical closed wire object.
  Map<String, String> toJson() => {
    'amount': amount.value,
    'currency': currency,
  };

  @override
  bool operator ==(Object other) =>
      other is KumweMoney &&
      other.amount == amount &&
      other.currency == currency;

  @override
  int get hashCode => Object.hash(amount, currency);

  @override
  String toString() => 'KumweMoney(${amount.value} $currency)';

  static final RegExp _currencyPattern = RegExp(r'^[A-Z]{3}$');
}
