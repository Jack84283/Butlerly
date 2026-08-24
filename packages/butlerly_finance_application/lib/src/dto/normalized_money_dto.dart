import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';

final class NormalizedMoneyDto {
  const NormalizedMoneyDto({
    required this.amount,
    required this.currency,
    required this.rateSource,
    required this.effectiveAt,
  });

  final String amount;
  final String currency;
  final String rateSource;
  final DateTime effectiveAt;

  factory NormalizedMoneyDto.fromDomain(NormalizedMoney value) =>
      NormalizedMoneyDto(
        amount: value.converted.amount.toString(),
        currency: value.converted.currency.value,
        rateSource: value.exchangeRate?.source ?? value.source.name,
        effectiveAt: value.exchangeRate?.effectiveAt ?? value.updatedAt,
      );
}
