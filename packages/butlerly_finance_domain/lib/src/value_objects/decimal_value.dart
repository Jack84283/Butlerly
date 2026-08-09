import '../errors/domain_error.dart';

final class DecimalValue implements Comparable<DecimalValue> {
  factory DecimalValue.parse(String input) {
    final normalized = input.trim();
    final match = RegExp(r'^([+-]?)(\d+)(?:\.(\d+))?$').firstMatch(normalized);
    if (match == null) {
      invalid(
        code: DomainErrorCode.invalidDecimal,
        field: 'amount',
        message: 'A finite base-10 decimal value is required.',
      );
    }

    final fractional = match.group(3) ?? '';
    final sign = match.group(1) == '-' ? -1 : 1;
    final digits = '${match.group(2)}$fractional';
    final coefficient = BigInt.parse(digits) * BigInt.from(sign);
    return DecimalValue._normalized(coefficient, fractional.length);
  }

  factory DecimalValue.fromParts({
    required BigInt coefficient,
    required int scale,
  }) {
    if (scale < 0) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'scale',
        message: 'Decimal scale cannot be negative.',
      );
    }
    return DecimalValue._normalized(coefficient, scale);
  }

  const DecimalValue._(this.coefficient, this.scale);

  factory DecimalValue._normalized(BigInt coefficient, int scale) {
    var normalizedCoefficient = coefficient;
    var normalizedScale = scale;
    while (normalizedScale > 0 &&
        normalizedCoefficient % BigInt.from(10) == BigInt.zero) {
      normalizedCoefficient ~/= BigInt.from(10);
      normalizedScale -= 1;
    }
    return DecimalValue._(normalizedCoefficient, normalizedScale);
  }

  final BigInt coefficient;
  final int scale;

  bool get isPositive => coefficient > BigInt.zero;
  bool get isNegative => coefficient < BigInt.zero;
  bool get isZero => coefficient == BigInt.zero;

  @override
  int compareTo(DecimalValue other) {
    final commonScale = scale > other.scale ? scale : other.scale;
    return _scaledCoefficient(
      commonScale,
    ).compareTo(other._scaledCoefficient(commonScale));
  }

  BigInt _scaledCoefficient(int targetScale) =>
      coefficient * BigInt.from(10).pow(targetScale - scale);

  @override
  bool operator ==(Object other) =>
      other is DecimalValue &&
      other.coefficient == coefficient &&
      other.scale == scale;

  @override
  int get hashCode => Object.hash(coefficient, scale);

  @override
  String toString() {
    if (scale == 0) return coefficient.toString();

    final negative = coefficient.isNegative;
    final digits = coefficient.abs().toString().padLeft(scale + 1, '0');
    final split = digits.length - scale;
    final value = '${digits.substring(0, split)}.${digits.substring(split)}';
    return negative ? '-$value' : value;
  }
}
