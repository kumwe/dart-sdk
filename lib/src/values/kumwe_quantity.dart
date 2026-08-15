import 'kumwe_decimal.dart';

/// An exact amount bound to the opaque portable unit it is measured in.
///
/// The wire shape is the closed object `{"amount": string, "unit": string}`
/// with the amount as a canonical decimal literal. The unit is an opaque
/// identifier: nothing in this type converts between units, so two quantities
/// are only comparable when their units are equal.
final class KumweQuantity {
  /// Binds [amount] to a bounded portable [unit] identifier such as `kg`.
  factory KumweQuantity({required KumweDecimal amount, required String unit}) {
    if (!_unitPattern.hasMatch(unit)) {
      throw ArgumentError.value(
        unit,
        'unit',
        'A quantity unit must be a bounded portable identifier of 1 to 63 '
            'supported characters.',
      );
    }
    return KumweQuantity._(amount, unit);
  }

  /// Parses the closed `{"amount", "unit"}` wire object.
  ///
  /// Unknown members are rejected: the wire contract is a closed object, so an
  /// extra member indicates a contract violation rather than an extension.
  factory KumweQuantity.fromJson(Map<String, Object?> json) {
    final amount = json['amount'];
    final unit = json['unit'];
    if (json.length != 2 || amount is! String || unit is! String) {
      throw FormatException(
        'Quantity is the closed {"amount", "unit"} string pair.',
        json.toString(),
      );
    }
    return KumweQuantity(amount: KumweDecimal.parse(amount), unit: unit);
  }

  const KumweQuantity._(this.amount, this.unit);

  /// Exact amount expressed in [unit] at the field scale.
  final KumweDecimal amount;

  /// Opaque portable unit identifier, such as `kg` or `m/s`.
  final String unit;

  /// Returns the canonical closed wire object.
  Map<String, String> toJson() => {'amount': amount.value, 'unit': unit};

  @override
  bool operator ==(Object other) =>
      other is KumweQuantity && other.amount == amount && other.unit == unit;

  @override
  int get hashCode => Object.hash(amount, unit);

  @override
  String toString() => 'KumweQuantity(${amount.value} $unit)';

  static final RegExp _unitPattern = RegExp(
    r'^[A-Za-z0-9][A-Za-z0-9._/-]{0,62}$',
  );
}
