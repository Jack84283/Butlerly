import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 23, 12);
  late MemoryPaymentSettlements settlements;
  late MemoryPaymentSources sources;
  late FixedClock clock;

  setUp(() async {
    settlements = MemoryPaymentSettlements();
    sources = MemoryPaymentSources();
    clock = FixedClock(now);
    await sources.save(
      PaymentSource(
        id: PaymentSourceId('visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
      ),
    );
  });

  test('saves and lists an independent payment settlement', () async {
    final result = await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
      statementBalance: money('2846.72'),
    );

    expect(result, isA<ApplicationSuccess<PaymentSettlementDto>>());
    final listed = await ListPaymentSettlements(settlements)();
    final value =
        (listed as ApplicationSuccess<List<PaymentSettlementDto>>).value.single;
    expect(value.payment.amount, DecimalValue.parse('2846.72'));
    expect(value.payment.currency, CurrencyCode('USD'));
    expect(value.paymentDate, '2026-09-20');
  });

  test(
    'detail re-resolves statement activity without a payment transaction',
    () async {
      await SavePaymentSettlement(settlements, sources, clock)(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        payment: money('2846.72'),
        paymentDate: '2026-09-20',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
      );
      settlements.transactions.add(activity('tx-1', now));

      final first = await GetPaymentSettlementDetail(settlements)(
        'settlement-1',
      );
      final firstValue =
          (first as ApplicationSuccess<PaymentSettlementDetailDto>).value;
      expect(firstValue.transactionCount, 1);

      settlements.transactions.add(activity('tx-2', now));
      final second = await GetPaymentSettlementDetail(settlements)(
        'settlement-1',
      );
      expect(
        (second as ApplicationSuccess<PaymentSettlementDetailDto>)
            .value
            .transactionCount,
        2,
      );
    },
  );

  test(
    'detail compares net recorded activity with settlement payment',
    () async {
      await SavePaymentSettlement(settlements, sources, clock)(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        payment: money('85.00'),
        paymentDate: '2026-09-20',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
      );
      settlements.transactions.add(activity('expense', now, amount: '100.00'));
      settlements.transactions.add(
        activity(
          'refund',
          now,
          amount: '15.00',
          direction: TransactionDirection.refund,
        ),
      );

      final result = await GetPaymentSettlementDetail(settlements)(
        'settlement-1',
      );
      final detail =
          (result as ApplicationSuccess<PaymentSettlementDetailDto>).value;

      expect(detail.recordedTransactionTotal!.amount, DecimalValue.parse('85'));
      expect(detail.recordedTransactionTotal!.currency, CurrencyCode('USD'));
      expect(detail.paymentDifference!.amount, DecimalValue.parse('0'));
    },
  );

  test('detail normalizes signed amounts before applying direction', () async {
    await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('85.00'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );
    settlements.transactions.add(activity('expense', now, amount: '-100.00'));
    settlements.transactions.add(
      activity(
        'refund',
        now,
        amount: '-15.00',
        direction: TransactionDirection.refund,
      ),
    );

    final result = await GetPaymentSettlementDetail(settlements)(
      'settlement-1',
    );
    final detail =
        (result as ApplicationSuccess<PaymentSettlementDetailDto>).value;

    expect(detail.recordedTransactionTotal!.amount, DecimalValue.parse('85'));
    expect(detail.paymentDifference!.amount, DecimalValue.parse('0'));
  });

  test(
    'detail comparison is unavailable for mixed transaction currencies',
    () async {
      await SavePaymentSettlement(settlements, sources, clock)(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        payment: money('85.00'),
        paymentDate: '2026-09-20',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
      );
      settlements.transactions.add(activity('usd', now, amount: '50.00'));
      settlements.transactions.add(
        activity('eur', now, amount: '35.00', currency: 'EUR'),
      );

      final result = await GetPaymentSettlementDetail(settlements)(
        'settlement-1',
      );
      final detail =
          (result as ApplicationSuccess<PaymentSettlementDetailDto>).value;

      expect(detail.recordedTransactionTotal, isNull);
      expect(detail.paymentDifference, isNull);
    },
  );

  test('detail comparison is unavailable for adjustments', () async {
    await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('85.00'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );
    settlements.transactions.add(
      activity(
        'adjustment',
        now,
        amount: '5.00',
        direction: TransactionDirection.adjustment,
      ),
    );

    final result = await GetPaymentSettlementDetail(settlements)(
      'settlement-1',
    );
    final detail =
        (result as ApplicationSuccess<PaymentSettlementDetailDto>).value;

    expect(detail.recordedTransactionTotal, isNull);
    expect(detail.paymentDifference, isNull);
  });

  test('rejects a missing payment source', () async {
    final result = await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'missing',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    expect(result, isA<ApplicationFailure<PaymentSettlementDto>>());
  });

  test('rejects a statement balance in another currency', () async {
    final result = await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
      statementBalance: Money(
        amount: DecimalValue.parse('2846.72'),
        currency: CurrencyCode('EUR'),
      ),
    );

    expect(result, isA<ApplicationFailure<PaymentSettlementDto>>());
  });

  test('status change preserves settlement-owned payment facts', () async {
    await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    final result = await SetPaymentSettlementStatus(settlements, clock)(
      'settlement-1',
      PaymentSettlementStatus.reconciled,
    );

    final value = (result as ApplicationSuccess<PaymentSettlementDto>).value;
    expect(value.status, PaymentSettlementStatus.reconciled);
    expect(value.payment.amount, DecimalValue.parse('2846.72'));
    expect(value.paymentDate, '2026-09-20');
  });

  test('editing payment facts updates the settlement directly', () async {
    await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    final result = await SavePaymentSettlement(settlements, sources, clock)(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('2900.00'),
      paymentDate: '2026-09-21',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    final value = (result as ApplicationSuccess<PaymentSettlementDto>).value;
    expect(value.payment.amount, DecimalValue.parse('2900.00'));
    expect(value.paymentDate, '2026-09-21');
  });

  test(
    'editing reconciled payment facts marks the settlement needs review',
    () async {
      await SavePaymentSettlement(settlements, sources, clock)(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        payment: money('2846.72'),
        paymentDate: '2026-09-20',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
      );
      await SetPaymentSettlementStatus(settlements, clock)(
        'settlement-1',
        PaymentSettlementStatus.reconciled,
      );

      final result = await SavePaymentSettlement(settlements, sources, clock)(
        id: 'settlement-1',
        paymentSourceId: 'visa',
        payment: money('2900.00'),
        paymentDate: '2026-09-21',
        periodStart: '2026-08-15',
        periodEnd: '2026-09-14',
        status: PaymentSettlementStatus.reconciled,
      );

      final value = (result as ApplicationSuccess<PaymentSettlementDto>).value;
      expect(value.status, PaymentSettlementStatus.needsReview);
    },
  );
}

final class FixedClock implements ApplicationClock {
  const FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

final class MemoryPaymentSettlements implements PaymentSettlementRepository {
  final values = <String, PaymentSettlement>{};
  final transactions = <Transaction>[];

  @override
  Future<PaymentSettlement?> findById(PaymentSettlementId id) async =>
      values[id.value];

  @override
  Future<List<PaymentSettlement>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> listTransactions(
    PaymentSettlement settlement,
  ) async => List.of(transactions);

  @override
  Future<void> remove(PaymentSettlementId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(PaymentSettlement settlement) async {
    values[settlement.id.value] = settlement;
  }
}

final class MemoryPaymentSources implements PaymentSourceRepository {
  final values = <String, PaymentSource>{};

  @override
  Future<PaymentSource?> findById(PaymentSourceId id) async => values[id.value];

  @override
  Future<List<PaymentSource>> listAll() async => values.values.toList();

  @override
  Future<void> save(PaymentSource paymentSource) async {
    values[paymentSource.id.value] = paymentSource;
  }
}

Money money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));

Transaction activity(
  String id,
  DateTime at, {
  String amount = '10.00',
  String currency = 'USD',
  TransactionDirection direction = TransactionDirection.expense,
}) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(at),
  money: Money(
    amount: DecimalValue.parse(amount),
    currency: CurrencyCode(currency),
  ),
  direction: direction,
  sourceType: TransactionSourceType.manual,
  paymentSourceId: PaymentSourceId('visa'),
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-$id'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: at,
    ),
  ],
  transactionDate: '2026-09-01',
  createdAt: at,
  updatedAt: at,
);
