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
    await sources.save(
      PaymentSource(
        id: PaymentSourceId('checking'),
        name: 'Checking',
        type: PaymentSourceType.account,
      ),
    );
  });

  test('saves and lists a payment settlement', () async {
    final result = await SavePaymentSettlement(
      settlements,
      sources,
      clock,
    )(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      fundingPaymentSourceId: 'checking',
      payment: money('2846.72'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
      statementBalance: money('2846.72'),
    );

    expect(result, isA<ApplicationSuccess<PaymentSettlementDto>>());
    final listed = await ListPaymentSettlements(settlements)();
    expect(
      listed,
      isA<ApplicationSuccess<List<PaymentSettlementDto>>>().having(
        (value) => value.value.single.id,
        'id',
        'settlement-1',
      ),
    );
  });

  test('detail resolves current transactions on every read', () async {
    await SavePaymentSettlement(
      settlements,
      sources,
      clock,
    )(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('20.00'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );
    settlements.transactions.add(transaction('tx-1', now));

    final first = await GetPaymentSettlementDetail(settlements)(
      'settlement-1',
    );
    expect(
      (first as ApplicationSuccess<PaymentSettlementDetailDto>)
          .value
          .transactionCount,
      1,
    );

    settlements.transactions.add(transaction('tx-2', now));
    final second = await GetPaymentSettlementDetail(settlements)(
      'settlement-1',
    );
    expect(
      (second as ApplicationSuccess<PaymentSettlementDetailDto>)
          .value
          .transactionCount,
      2,
    );
  });

  test('status change is explicit workflow state', () async {
    await SavePaymentSettlement(
      settlements,
      sources,
      clock,
    )(
      id: 'settlement-1',
      paymentSourceId: 'visa',
      payment: money('20.00'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    final result = await SetPaymentSettlementStatus(
      settlements,
      clock,
    )('settlement-1', PaymentSettlementStatus.reconciled);

    expect(
      (result as ApplicationSuccess<PaymentSettlementDto>).value.status,
      PaymentSettlementStatus.reconciled,
    );
  });

  test('rejects a missing payment source', () async {
    final result = await SavePaymentSettlement(
      settlements,
      sources,
      clock,
    )(
      id: 'settlement-1',
      paymentSourceId: 'missing',
      payment: money('20.00'),
      paymentDate: '2026-09-20',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    expect(
      result,
      isA<ApplicationFailure<PaymentSettlementDto>>().having(
        (value) => value.failure.code,
        'code',
        ApplicationFailureCode.notFound,
      ),
    );
  });
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

Money money(String amount) => Money(
  amount: DecimalValue.parse(amount),
  currency: CurrencyCode('USD'),
);

Transaction transaction(String id, DateTime at) => Transaction(
  id: TransactionId(id),
  timing: KnownTransactionTime(at),
  money: money('10.00'),
  direction: TransactionDirection.expense,
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
