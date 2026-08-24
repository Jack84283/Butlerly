import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final usd = CurrencyCode('USD');
  final cny = CurrencyCode('CNY');
  final cny700 = Money(
    amount: DecimalValue.parse('700'),
    currency: cny,
  );

  test('same currency does not require normalization', () {
    final result = normalizeMoney(
      original: Money(amount: DecimalValue.parse('12.50'), currency: usd),
      baseCurrency: usd,
    );
    expect(result.status, NormalizationStatus.notRequired);
    expect(result.normalized, isNull);
  });

  test('missing rate never becomes one to one', () {
    final result = normalizeMoney(original: cny700, baseCurrency: usd);
    expect(result.status, NormalizationStatus.missingRate);
    expect(result.normalized, isNull);
  });

  test('preserves a user-entered normalized amount', () {
    final result = normalizeMoney(
      original: cny700,
      baseCurrency: usd,
      userEnteredNormalized: Money(
        amount: DecimalValue.parse('98.25'),
        currency: usd,
      ),
    );
    expect(result.status, NormalizationStatus.resolved);
    expect(result.source, NormalizationSource.userEntered);
    expect(result.normalized!.amount.toString(), '98.25');
  });
}
