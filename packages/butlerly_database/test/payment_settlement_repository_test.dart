import 'dart:io';

import 'package:butlerly_database/butlerly_database.dart';
import 'package:butlerly_finance_domain/butlerly_finance_domain.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:test/test.dart';

void main() {
  sqfliteFfiInit();

  late ButlerlyDatabase database;
  late SqlitePaymentSettlementRepository settlements;
  late SqliteTransactionRepository transactions;

  setUp(() async {
    database = ButlerlyDatabase(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
      schemaSql: await File('database/schema/v1.sql').readAsString(),
    );
    await database.open();
    settlements = SqlitePaymentSettlementRepository(database);
    transactions = SqliteTransactionRepository(database);

    await _insertPaymentSource(database, 'visa', 'Visa');
    await _insertPaymentSource(database, 'checking', 'Checking');
    await _insertPaymentSource(database, 'amex', 'Amex');
  });

  tearDown(() => database.close());

  test('persists and hydrates a payment settlement', () async {
    final settlement = _settlement();

    await settlements.save(settlement);
    final loaded = await settlements.findById(settlement.id);

    expect(loaded, isNotNull);
    expect(loaded!.paymentSourceId, PaymentSourceId('visa'));
    expect(loaded.fundingPaymentSourceId, PaymentSourceId('checking'));
    expect(loaded.payment, settlement.payment);
    expect(loaded.periodStart, '2026-08-15');
    expect(loaded.periodEnd, '2026-09-14');
    expect(loaded.statementBalance, settlement.statementBalance);
  });

  test('resolves settlement transactions dynamically by source and period', () async {
    final settlement = _settlement();
    await settlements.save(settlement);
    await transactions.save(
      _transaction(
        id: 'inside',
        sourceId: 'visa',
        transactionDate: '2026-09-01',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'outside',
        sourceId: 'visa',
        transactionDate: '2026-09-15',
      ),
    );
    await transactions.save(
      _transaction(
        id: 'other-source',
        sourceId: 'amex',
        transactionDate: '2026-09-01',
      ),
    );

    final first = await settlements.listTransactions(settlement);
    expect(first.map((value) => value.id.value), ['inside']);

    await transactions.save(
      _transaction(
        id: 'late-import',
        sourceId: 'visa',
        transactionDate: '2026-08-20',
      ),
    );

    final refreshed = await settlements.listTransactions(settlement);
    expect(
      refreshed.map((value) => value.id.value).toSet(),
      {'inside', 'late-import'},
    );
  });

  test('does not create a persisted settlement membership table', () async {
    final rows = await database.connection.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name = 'payment_settlement_items'",
    );

    expect(rows, isEmpty);
  });
}

PaymentSettlement _settlement() {
  final at = DateTime.utc(2026, 9, 20, 12);
  return PaymentSettlement(
    id: PaymentSettlementId('settlement-1'),
    paymentSourceId: PaymentSourceId('visa'),
    fundingPaymentSourceId: PaymentSourceId('checking'),
    payment: Money(
      amount: DecimalValue.parse('2846.72'),
      currency: CurrencyCode('USD'),
    ),
    paymentDate: '2026-09-20',
    periodStart: '2026-08-15',
    periodEnd: '2026-09-14',
    statementBalance: Money(
      amount: DecimalValue.parse('2846.72'),
      currency: CurrencyCode('USD'),
    ),
    status: PaymentSettlementStatus.open,
    createdAt: at,
    updatedAt: at,
  );
}

Transaction _transaction({
  required String id,
  required String sourceId,
  required String transactionDate,
}) {
  final at = DateTime.parse('${transactionDate}T12:00:00Z');
  return Transaction(
    id: TransactionId(id),
    timing: KnownTransactionTime(at),
    money: Money(
      amount: DecimalValue.parse('10.00'),
      currency: CurrencyCode('USD'),
    ),
    direction: TransactionDirection.expense,
    sourceType: TransactionSourceType.import,
    paymentSourceId: PaymentSourceId(sourceId),
    provenance: [
      Provenance(
        id: ProvenanceId('provenance-$id'),
        sourceType: ProvenanceSourceType.import,
        capturedAt: at,
        originalRepresentation: id,
      ),
    ],
    transactionDate: transactionDate,
    createdAt: at,
    updatedAt: at,
  );
}

Future<void> _insertPaymentSource(
  ButlerlyDatabase database,
  String id,
  String name,
) => database.connection.insert('payment_sources', {
  'id': id,
  'name': name,
  'type': PaymentSourceType.card.name,
  'status': PaymentSourceStatus.active.name,
});
