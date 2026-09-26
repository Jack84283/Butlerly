import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final createdAt = DateTime.utc(2026, 9, 23, 12);

  test('constructs a valid payment settlement', () {
    final settlement = buildSettlement(createdAt);

    expect(settlement.id, PaymentSettlementId('settlement-1'));
    expect(settlement.paymentSourceId, PaymentSourceId('visa'));
    expect(settlement.payment.amount, DecimalValue.parse('2846.72'));
    expect(settlement.payment.currency, CurrencyCode('USD'));
    expect(settlement.paymentDate, '2026-09-20');
    expect(settlement.periodStart, '2026-08-15');
    expect(settlement.periodEnd, '2026-09-14');
    expect(settlement.status, PaymentSettlementStatus.open);
  });

  test('rejects a reversed settlement period', () {
    expect(
      () => PaymentSettlement(
        id: PaymentSettlementId('settlement-1'),
        paymentSourceId: PaymentSourceId('visa'),
        payment: money('2846.72'),
        paymentDate: '2026-09-20',
        periodStart: '2026-09-14',
        periodEnd: '2026-08-15',
        status: PaymentSettlementStatus.open,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('requires canonical financial dates', () {
    expect(
      () => PaymentSettlement(
        id: PaymentSettlementId('settlement-1'),
        paymentSourceId: PaymentSourceId('visa'),
        payment: money('2846.72'),
        paymentDate: '09/20/2026',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
        status: PaymentSettlementStatus.open,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });

  test('requires statement balance currency to match payment currency', () {
    expect(
      () => PaymentSettlement(
        id: PaymentSettlementId('settlement-1'),
        paymentSourceId: PaymentSourceId('visa'),
        payment: money('2846.72'),
        paymentDate: '2026-09-20',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
        statementBalance: Money(
          amount: DecimalValue.parse('2846.72'),
          currency: CurrencyCode('EUR'),
        ),
        status: PaymentSettlementStatus.open,
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      throwsA(isA<DomainValidationException>()),
    );
  });
}

PaymentSettlement buildSettlement(DateTime createdAt) => PaymentSettlement(
  id: PaymentSettlementId('settlement-1'),
  paymentSourceId: PaymentSourceId('visa'),
  payment: money('2846.72'),
  paymentDate: '2026-09-20',
  periodStart: '2026-08-15',
  periodEnd: '2026-09-14',
  statementBalance: money('2846.72'),
  status: PaymentSettlementStatus.open,
  createdAt: createdAt,
  updatedAt: createdAt,
);

Money money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));
