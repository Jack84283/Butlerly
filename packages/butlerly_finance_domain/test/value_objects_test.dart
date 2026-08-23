import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  test(
    'financial periods retain the persisted timezone and use date-only bounds',
    () {
      final period = FinancialPeriod.month(
        year: 2026,
        month: 8,
        timeZoneId: 'America/Los_Angeles',
      );

      expect(period.timeZoneId, 'America/Los_Angeles');
      expect(period.contains(DateTime(2026, 8, 1, 23, 59)), isTrue);
      expect(period.contains(DateTime(2026, 9, 1)), isFalse);
    },
  );

  test('handles month boundaries without extending the financial period', () {
    final period = FinancialPeriod.month(
      year: 2026,
      month: 3,
      timeZoneId: 'America/Los_Angeles',
    );

    expect(period.contains(DateTime.utc(2026, 3, 31, 23, 59)), isTrue);
    expect(period.contains(DateTime.utc(2026, 4, 1)), isFalse);
  });

  test('retains the selected timezone across a timezone preference change', () {
    final pacific = FinancialPeriod.month(
      year: 2026,
      month: 11,
      timeZoneId: 'America/Los_Angeles',
    );
    final shanghai = FinancialPeriod.month(
      year: 2026,
      month: 11,
      timeZoneId: 'Asia/Shanghai',
    );

    expect(pacific.timeZoneId, isNot(shanghai.timeZoneId));
    expect(pacific.startDate, shanghai.startDate);
    expect(pacific.endDate, shanghai.endDate);
  });

  test('period membership is independent of the device timezone', () {
    final period = FinancialPeriod.month(
      year: 2026,
      month: 3,
      timeZoneId: 'America/New_York',
    );

    expect(period.contains(DateTime.utc(2026, 3, 1)), isTrue);
    expect(period.contains(DateTime.utc(2026, 4, 1)), isFalse);
  });

  test('DST transition dates remain calendar dates, not elapsed-hour windows', () {
    final period = FinancialPeriod.month(
      year: 2026,
      month: 3,
      timeZoneId: 'America/Los_Angeles',
    );

    expect(period.contains(DateTime(2026, 3, 8, 1, 59)), isTrue);
    expect(period.contains(DateTime(2026, 3, 8, 3, 1)), isTrue);
  });
  group('DecimalValue', () {
    test('preserves exact decimal precision without floating point', () {
      expect(
        DecimalValue.parse('1234567890.123400').toString(),
        '1234567890.1234',
      );
      expect(DecimalValue.parse('-0.01').toString(), '-0.01');
    });

    test('rejects non-decimal values', () {
      expect(
        () => DecimalValue.parse('NaN'),
        throwsA(
          isA<DomainValidationException>().having(
            (error) => error.code,
            'code',
            DomainErrorCode.invalidDecimal,
          ),
        ),
      );
    });
  });

  group('Money', () {
    test('always includes an explicit normalized currency code', () {
      final money = Money(
        amount: DecimalValue.parse('42.50'),
        currency: CurrencyCode('usd'),
      );

      expect(money.currency.value, 'USD');
      expect(money.amount.toString(), '42.5');
    });

    test('rejects malformed currency codes', () {
      expect(
        () => CurrencyCode('US'),
        throwsA(isA<DomainValidationException>()),
      );
    });
  });

  test('domain identifiers require Butlerly-owned values', () {
    expect(
      () => TransactionId('  '),
      throwsA(isA<DomainValidationException>()),
    );
    expect(TransactionId('local-1'), TransactionId('local-1'));
  });
}
