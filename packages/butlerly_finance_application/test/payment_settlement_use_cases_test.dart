import 'package:butlerly_finance_application/butlerly_finance_application.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:test/test.dart';

void main() {
  final now = DateTime.utc(2026, 9, 23, 12);
  late MemoryPaymentSettlements settlements;
  late MemoryPaymentSources sources;
  late MemoryTransactions transactions;
  late FixedClock clock;

  setUp(() async {
    settlements = MemoryPaymentSettlements();
    sources = MemoryPaymentSources();
    transactions = MemoryTransactions();
    clock = FixedClock(now);
    await sources.save(
      PaymentSource(
        id: PaymentSourceId('visa'),
        name: 'Visa',
        type: PaymentSourceType.card,
      ),
    );
    await transactions.save(paymentTransfer(now));
  });

  test('saves and lists a payment settlement', () async {
    final result =
        await SavePaymentSettlement(settlements, sources, transactions, clock)(
          id: 'settlement-1',
          settlementTransactionId: 'payment-transfer',
          paymentSourceId: 'visa',
          periodStart: '2026-08-15',
          periodEnd: '2026-09-14',
          statementBalance: money('2846.72'),
        );

    expect(result, isA<ApplicationSuccess<PaymentSettlementDto>>());
    final listed = await ListPaymentSettlements(settlements)();
    expect(
      listed,
      isA<ApplicationSuccess<List<PaymentSettlementDto>>>().having(
        (value) => value.value.single.settlementTransactionId,
        'settlement transaction',
        'payment-transfer',
      ),
    );
  });

  test('detail returns canonical payment and re-resolves activity', () async {
    await SavePaymentSettlement(settlements, sources, transactions, clock)(
      id: 'settlement-1',
      settlementTransactionId: 'payment-transfer',
      paymentSourceId: 'visa',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );
    settlements.transactions.add(activity('tx-1', now));

    final first = await GetPaymentSettlementDetail(settlements, transactions)(
      'settlement-1',
    );
    final firstValue =
        (first as ApplicationSuccess<PaymentSettlementDetailDto>).value;
    expect(firstValue.paymentTransaction.id, 'payment-transfer');
    expect(firstValue.transactionCount, 1);

    settlements.transactions.add(activity('tx-2', now));
    final second = await GetPaymentSettlementDetail(settlements, transactions)(
      'settlement-1',
    );
    expect(
      (second as ApplicationSuccess<PaymentSettlementDetailDto>)
          .value
          .transactionCount,
      2,
    );
  });

  test('rejects a non-transfer settlement transaction', () async {
    await transactions.save(activity('expense-1', now));

    final result =
        await SavePaymentSettlement(settlements, sources, transactions, clock)(
          id: 'settlement-1',
          settlementTransactionId: 'expense-1',
          paymentSourceId: 'visa',
          periodStart: '2026-08-15',
          periodEnd: '2026-09-14',
        );

    expect(result, isA<ApplicationFailure<PaymentSettlementDto>>());
  });

  test('rejects a settlement transaction without a financial date', () async {
    await transactions.save(paymentTransfer(now, transactionDate: null));

    final result =
        await SavePaymentSettlement(settlements, sources, transactions, clock)(
          id: 'settlement-1',
          settlementTransactionId: 'payment-transfer',
          paymentSourceId: 'visa',
          periodStart: '2026-08-15',
          periodEnd: '2026-09-14',
        );

    expect(result, isA<ApplicationFailure<PaymentSettlementDto>>());
  });

  test('status change is explicit workflow state', () async {
    await SavePaymentSettlement(settlements, sources, transactions, clock)(
      id: 'settlement-1',
      settlementTransactionId: 'payment-transfer',
      paymentSourceId: 'visa',
      periodStart: '2026-08-15',
      periodEnd: '2026-09-14',
    );

    final result = await SetPaymentSettlementStatus(settlements, clock)(
      'settlement-1',
      PaymentSettlementStatus.reconciled,
    );

    expect(
      (result as ApplicationSuccess<PaymentSettlementDto>).value.status,
      PaymentSettlementStatus.reconciled,
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

final class MemoryTransactions implements TransactionRepository {
  final values = <String, Transaction>{};

  @override
  Future<Transaction?> findById(TransactionId id) async => values[id.value];

  @override
  Future<List<Transaction>> listAll() async => values.values.toList();

  @override
  Future<List<Transaction>> query(TransactionRepositoryQuery query) async =>
      values.values.toList();

  @override
  Future<void> removePermanently(TransactionId id) async {
    values.remove(id.value);
  }

  @override
  Future<void> save(Transaction transaction) async {
    values[transaction.id.value] = transaction;
  }
}

Money money(String amount) =>
    Money(amount: DecimalValue.parse(amount), currency: CurrencyCode('USD'));

Transaction paymentTransfer(
  DateTime at, {
  String? transactionDate = '2026-09-20',
}) => Transaction(
  id: TransactionId('payment-transfer'),
  timing: KnownTransactionTime(at),
  money: money('2846.72'),
  direction: TransactionDirection.transfer,
  sourceType: TransactionSourceType.manual,
  paymentSourceId: PaymentSourceId('visa'),
  provenance: [
    Provenance(
      id: ProvenanceId('provenance-payment'),
      sourceType: ProvenanceSourceType.userEntry,
      capturedAt: at,
    ),
  ],
  transactionDate: transactionDate,
  createdAt: at,
  updatedAt: at,
);

Transaction activity(String id, DateTime at) => Transaction(
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
