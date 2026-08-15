/// An exact fixed-scale base-10 value carried as its canonical wire string.
///
/// Kumwe core stores decimal, money and quantity amounts as canonical string
/// literals and rejects binary floats outright, so this type never converts
/// through `double`. A value is canonical when it matches
/// `^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$`, carries no exponent, no leading `+`,
/// no insignificant leading zeros and never spells zero with a negative sign.
final class KumweDecimal implements Comparable<KumweDecimal> {
  /// Parses a canonical wire literal, deriving the scale from its fraction.
  ///
  /// Server-produced values are already canonical at their field scale, so a
  /// literal that is not canonical is a contract violation and is rejected
  /// rather than repaired.
  factory KumweDecimal.parse(String value) {
    if (!_canonical.hasMatch(value)) {
      throw FormatException(
        'An exact decimal must be a canonical base-10 string.',
        value,
      );
    }
    if (value.startsWith('-') && _isZero(value.substring(1))) {
      throw FormatException(
        'An exact decimal never spells zero with a negative sign.',
        value,
      );
    }
    return KumweDecimal._(value, _scaleOf(value));
  }

  /// Canonicalizes an application-authored literal against a field contract.
  ///
  /// This mirrors the server rules: [precision] must be 1 to 65 and [scale]
  /// 0 to [precision]; a fraction wider than [scale] or an integer part wider
  /// than the remaining digit budget is rejected rather than rounded, while a
  /// shorter fraction is padded and negative zero is normalized to zero.
  factory KumweDecimal.forField(
    String value, {
    required int precision,
    required int scale,
  }) {
    if (precision < 1 || precision > 65 || scale < 0 || scale > precision) {
      throw ArgumentError(
        'Decimal precision or scale is outside the portable database range.',
      );
    }
    if (!_canonical.hasMatch(value)) {
      throw FormatException(
        'An exact decimal must be a canonical base-10 string.',
        value,
      );
    }
    final negative = value.startsWith('-');
    final unsigned = negative ? value.substring(1) : value;
    final separator = unsigned.indexOf('.');
    final integer = separator < 0 ? unsigned : unsigned.substring(0, separator);
    var fraction = separator < 0 ? '' : unsigned.substring(separator + 1);
    if (fraction.length > scale) {
      throw FormatException(
        'An exact decimal has more fractional digits than the field scale.',
        value,
      );
    }
    if (integer != '0' && integer.length > precision - scale) {
      throw FormatException(
        'An exact decimal exceeds the field precision.',
        value,
      );
    }
    fraction = fraction.padRight(scale, '0');
    final zero = integer == '0' && !fraction.contains(RegExp('[1-9]'));
    final canonical =
        '${negative && !zero ? '-' : ''}$integer'
        '${scale > 0 ? '.$fraction' : ''}';
    return KumweDecimal._(canonical, scale);
  }

  /// Lifts a whole number into a field contract, zero-filling the fraction.
  factory KumweDecimal.fromInt(
    int value, {
    required int precision,
    required int scale,
  }) {
    return KumweDecimal.forField(
      value.toString(),
      precision: precision,
      scale: scale,
    );
  }

  const KumweDecimal._(this.value, this.scale);

  /// Canonical base-10 literal exactly as it travels on the wire.
  final String value;

  /// Number of fractional digits the literal carries.
  final int scale;

  /// Whether the value sorts below zero.
  bool get isNegative => value.startsWith('-');

  /// Whether the value is exactly zero at its scale.
  bool get isZero => _isZero(isNegative ? value.substring(1) : value);

  /// Orders this value against another of the same scale by exact digits.
  ///
  /// Values of different scales come from different field contracts, so the
  /// mismatch is surfaced as an error instead of being aligned silently.
  @override
  int compareTo(KumweDecimal other) {
    if (other.scale != scale) {
      throw ArgumentError.value(
        other,
        'other',
        'Exact decimals are only ordered against the same field scale.',
      );
    }
    if (isNegative != other.isNegative) {
      return isNegative ? -1 : 1;
    }
    final magnitude = _compareMagnitude(
      isNegative ? value.substring(1) : value,
      other.isNegative ? other.value.substring(1) : other.value,
    );
    return isNegative ? -magnitude : magnitude;
  }

  /// Returns the canonical literal for JSON encoding.
  String toJson() => value;

  @override
  bool operator ==(Object other) =>
      other is KumweDecimal && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;

  static int _compareMagnitude(String left, String right) {
    final leftSeparator = left.indexOf('.');
    final rightSeparator = right.indexOf('.');
    final leftInteger = leftSeparator < 0
        ? left
        : left.substring(0, leftSeparator);
    final rightInteger = rightSeparator < 0
        ? right
        : right.substring(0, rightSeparator);
    if (leftInteger.length != rightInteger.length) {
      return leftInteger.length < rightInteger.length ? -1 : 1;
    }
    final byInteger = leftInteger.compareTo(rightInteger);
    if (byInteger != 0) {
      return byInteger.sign;
    }
    final leftFraction = leftSeparator < 0
        ? ''
        : left.substring(leftSeparator + 1);
    final rightFraction = rightSeparator < 0
        ? ''
        : right.substring(rightSeparator + 1);
    return leftFraction.compareTo(rightFraction).sign;
  }

  static bool _isZero(String unsigned) => !unsigned.contains(RegExp('[1-9]'));

  static int _scaleOf(String value) {
    final separator = value.indexOf('.');
    return separator < 0 ? 0 : value.length - separator - 1;
  }

  static final RegExp _canonical = RegExp(
    r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?$',
  );
}
