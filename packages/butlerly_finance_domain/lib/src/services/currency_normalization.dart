import '../entities/exchange_rate.dart';
import '../value_objects/currency_code.dart';
import '../value_objects/decimal_value.dart';
import '../value_objects/money.dart';

enum NormalizationStatus { notRequired, resolved, missingRate }

enum NormalizationSource { userEntered, imported, exchangeRate }

final class CurrencyNormalizationResult {
  const CurrencyNormalizationResult({
    required this.status,
    required this.original,
    required this.baseCurrency,
    this.normalized,
    this.exchangeRate,
    this.source,
  });

  final NormalizationStatus status;
  final Money original;
  final CurrencyCode baseCurrency;
  final Money? normalized;
  final ExchangeRate? exchangeRate;
  final NormalizationSource? source;
}

CurrencyNormalizationResult normalizeMoney({
  required Money original,
  required CurrencyCode baseCurrency,
  ExchangeRate? exchangeRate,
  Money? userEnteredNormalized,
  NormalizationSource? source,
}) {
  if (original.currency == baseCurrency) {
    return CurrencyNormalizationResult(
      status: NormalizationStatus.notRequired,
      original: original,
      baseCurrency: baseCurrency,
      normalized: null,
    );
  }
  if (userEnteredNormalized != null &&
      userEnteredNormalized.currency == baseCurrency) {
    return CurrencyNormalizationResult(
      status: NormalizationStatus.resolved,
      original: original,
      baseCurrency: baseCurrency,
      normalized: userEnteredNormalized,
      source: source ?? NormalizationSource.userEntered,
    );
  }
  if (exchangeRate == null ||
      exchangeRate.fromCurrency != original.currency ||
      exchangeRate.toCurrency != baseCurrency) {
    return CurrencyNormalizationResult(
      status: NormalizationStatus.missingRate,
      original: original,
      baseCurrency: baseCurrency,
    );
  }
  final amount = DecimalValue.fromParts(
    coefficient:
        original.amount.coefficient * exchangeRate.rate.coefficient,
    scale: original.amount.scale + exchangeRate.rate.scale,
  );
  return CurrencyNormalizationResult(
    status: NormalizationStatus.resolved,
    original: original,
    baseCurrency: baseCurrency,
    normalized: Money(amount: amount, currency: baseCurrency),
    exchangeRate: exchangeRate,
    source: source ?? NormalizationSource.exchangeRate,
  );
}
