import '../errors/domain_error.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/decimal_value.dart';
import '../value_objects/domain_id.dart';
import '../value_objects/money.dart';

final class ExchangeRate {
  ExchangeRate({
    required this.id,
    required this.fromCurrency,
    required this.toCurrency,
    required this.rate,
    required DateTime effectiveAt,
    required String source,
  }) : effectiveAt = effectiveAt.toUtc(),
       source = _requiredSource(source) {
    if (!rate.isPositive) {
      invalid(
        code: DomainErrorCode.invalidRange,
        field: 'rate',
        message: 'An exchange rate must be positive.',
      );
    }
  }

  final ExchangeRateId id;
  final CurrencyCode fromCurrency;
  final CurrencyCode toCurrency;
  final DecimalValue rate;
  final DateTime effectiveAt;
  final String source;

  static String _requiredSource(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      invalid(
        code: DomainErrorCode.emptyValue,
        field: 'source',
        message: 'Exchange-rate provenance requires a source.',
      );
    }
    return normalized;
  }
}

final class NormalizedMoney {
  NormalizedMoney({
    required this.original,
    required this.converted,
    required this.exchangeRate,
  }) {
    if (original.currency != exchangeRate.fromCurrency ||
        converted.currency != exchangeRate.toCurrency) {
      invalid(
        code: DomainErrorCode.relationshipMismatch,
        field: 'exchangeRate',
        message: 'Normalized money currencies must match the exchange rate.',
      );
    }
  }

  final Money original;
  final Money converted;
  final ExchangeRate exchangeRate;
}
