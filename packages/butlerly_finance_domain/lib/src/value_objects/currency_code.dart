import '../errors/domain_error.dart';

final class CurrencyCode {
  factory CurrencyCode(String value) {
    final normalized = value.trim().toUpperCase();
    if (!RegExp(r'^[A-Z0-9]{3,8}$').hasMatch(normalized)) {
      invalid(
        code: DomainErrorCode.invalidCurrency,
        field: 'currency',
        message: 'Currency must be a 3-8 character code.',
      );
    }
    return CurrencyCode._(normalized);
  }

  const CurrencyCode._(this.value);

  final String value;

  @override
  bool operator ==(Object other) =>
      other is CurrencyCode && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}
